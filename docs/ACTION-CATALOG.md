# Action Catalog

> **EnvPod v0.2.0** — Zero-trust governance environments for AI agents
> Author: Mark Amoboateng · mark@envpod.com · m.amoboateng@gmail.com
> Copyright 2026 Xtellix Inc. · Licensed under Apache-2.0

---

The action catalog is the host-defined menu of what an agent is **allowed to do**. Agents discover available actions at runtime, call them by name, and envpod executes them on the agent's behalf — after validation, policy checks, and any required human approval. The agent never makes the call directly.

This is the same model as [MCP tool use](https://modelcontextprotocol.io/), but governed: every call flows through the action queue, every execution is audited, and credentials are fetched from the vault at execution time so the agent never sees them.

---

## Table of Contents

- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [Built-in Action Types](#built-in-action-types)
  - [HTTP](#http)
  - [Filesystem](#filesystem)
  - [Git](#git)
  - [Messaging](#messaging)
  - [Database](#database)
  - [System](#system)
- [Action Tiers](#action-tiers)
- [Action Scope: Internal vs External](#action-scope-internal-vs-external)
- [Creating Actions](#creating-actions)
  - [Built-in Type Action](#built-in-type-action)
  - [Custom Action](#custom-action)
  - [Configuring Auth from the Vault](#configuring-auth-from-the-vault)
- [actions.json Reference](#actionsjson-reference)
- [CLI Reference](#cli-reference)
- [Agent Protocol (Socket API)](#agent-protocol-socket-api)
- [Security Model](#security-model)
- [Full Example: Agent with Email + Git + Slack](#full-example-agent-with-email--git--slack)

---

## How It Works

```
  HOST                                  POD
  ────────────────────────              ─────────────────────────
  actions.json  ◄── host edits         agent
  (catalog)                              │
       │                                 │  {"type":"list_actions"}
       │                                 ▼
  ActionCatalog                     /run/envpod/queue.sock
  (live reload)    ◄────────────────────────────────────────
       │
       │  return: [{name, description, tier, scope, params}, ...]
       ├─────────────────────────────────────────────────────►
                                          │
                                          │  {"type":"call","action":"send_email",
                                          │   "params":{"to":"...","subject":"..."}}
                                          ▼
  validate_call()  ◄────────────────────────────────────────
       │  (check required params, reject unknown keys)
       │
  Queue entry (status: Queued)
       │
   tier check:
   ├─ Immediate → execute now
   ├─ Delayed   → execute after timeout (cancelable)
   ├─ Staged    → wait for human: envpod approve <id>
   └─ Blocked   → reject immediately
       │
  ActionExecutor (host-side)
       │  fetches secrets from vault at execution time
       │  agent never sees the credential
       ▼
  audit.jsonl entry
```

Key points:
- `actions.json` lives at `{pod_dir}/actions.json` — host-side only. The agent can query it but never write it.
- The catalog is **hot-reloaded** on every query — change it while a pod is running with no restart.
- Params are **validated against the schema** before queuing — no injection possible.
- Auth secrets are **never in the action call** — reference a vault key name in `config`, envpod fetches the value at execution time.

---

## Quick Start

### 1. Create the pod

```yaml
# myagent/pod.yaml
name: myagent
network:
  mode: Filtered
  allow:
    - api.sendgrid.com
    - api.github.com
queue:
  socket: true       # expose /run/envpod/queue.sock inside pod
```

### 2. Define the catalog

Create `myagent/actions.json` (or use the CLI — see below):

```json
[
  {
    "name": "send_status_email",
    "description": "Send a task completion email to the team",
    "action_type": "send_email",
    "tier": "staged",
    "config": {
      "provider": "sendgrid",
      "auth_vault_key": "SENDGRID_API_KEY",
      "from": "agent@mycompany.com"
    }
  },
  {
    "name": "commit_work",
    "description": "Commit completed work to the repository",
    "action_type": "git_commit",
    "tier": "staged"
  }
]
```

### 3. Run the pod

```bash
sudo envpod run myagent -- python agent.py
```

### 4. Agent discovers and calls actions

Inside the pod, the agent communicates over `/run/envpod/queue.sock`:

```python
import socket, json

def queue_call(msg):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect("/run/envpod/queue.sock")
    sock.sendall(json.dumps(msg).encode() + b"\n")
    return json.loads(sock.recv(4096))

# Discover available actions
actions = queue_call({"type": "list_actions"})
# → [{"name": "send_status_email", "description": "...", "tier": "staged",
#     "scope": "external", "params": [{"name": "to", "required": true}, ...]}, ...]

# Call an action — returns immediately with a queue ID
result = queue_call({
    "type": "call",
    "action": "send_status_email",
    "params": {
        "to": "team@mycompany.com",
        "subject": "Task complete",
        "body": "The analysis finished successfully."
    }
})
# → {"ok": true, "id": "a1b2c3...", "status": "queued", "tier": "staged"}

# Poll for completion
status = queue_call({"type": "poll", "id": result["id"]})
# → {"ok": true, "status": "executed"} (after human approves)
```

### 5. Approve from the host

```bash
# See what's waiting
sudo envpod queue myagent

# Approve
sudo envpod approve myagent <action-id>
```

---

## Built-in Action Types

Built-in types give you a fixed, validated parameter schema and a host-side executor. You do not need to write execution code — envpod makes the call.

### HTTP

| Type | Default Tier | Scope | Description |
|---|---|---|---|
| `http_get` | immediate | external | GET request, returns response body |
| `http_post` | staged | external | POST with JSON or text body |
| `http_put` | staged | external | PUT to replace a resource |
| `http_patch` | staged | external | PATCH to update part of a resource |
| `http_delete` | staged | external | DELETE a resource |
| `webhook` | staged | external | POST a JSON payload to a webhook URL |

**`http_get` params:**
| Param | Required | Description |
|---|:---:|---|
| `url` | ✓ | Full URL to GET |
| `headers` | | JSON object of extra request headers |

**`http_post` / `http_put` / `http_patch` params:**
| Param | Required | Description |
|---|:---:|---|
| `url` | ✓ | Full URL |
| `body` | | Request body (JSON string or plain text) |
| `content_type` | | Content-Type header (default: `application/json`) |
| `headers` | | JSON object of extra request headers |

**`http_delete` params:**
| Param | Required | Description |
|---|:---:|---|
| `url` | ✓ | Full URL to DELETE |
| `headers` | | JSON object of extra request headers |

**`webhook` params:**
| Param | Required | Description |
|---|:---:|---|
| `url` | ✓ | Webhook URL (HTTPS) |
| `payload` | ✓ | JSON payload to POST |
| `secret_header` | | Header name for HMAC signature (e.g. `X-Hub-Signature`) |
| `headers` | | JSON object of extra request headers |

**Auth config** (set in `config` field of the action definition):
- `auth_vault_key` — vault key holding the bearer token, API key, or password
- `auth_scheme` — `bearer` (default), `basic`, or a full header like `X-API-Key: {value}`

---

### Filesystem

All filesystem actions operate **only inside the pod's copy-on-write overlay**. Paths that attempt to escape the overlay (via `..` or absolute paths outside the pod) are rejected. Because the overlay is COW, all filesystem actions are fully reversible with `envpod rollback`.

| Type | Default Tier | Scope | Description |
|---|---|---|---|
| `file_create` | immediate | internal | Create a new file inside the pod |
| `file_write` | immediate | internal | Write or append content to a file |
| `file_delete` | delayed (30s) | internal | Delete a file (grace period) |
| `file_copy` | immediate | internal | Copy a file |
| `file_move` | delayed (30s) | internal | Move or rename a file (grace period) |
| `dir_create` | immediate | internal | Create a directory |
| `dir_delete` | delayed (30s) | internal | Delete a directory |

**`file_create` params:**
| Param | Required | Description |
|---|:---:|---|
| `path` | ✓ | File path inside pod (e.g. `/workspace/out.txt`) |
| `content` | | Initial content (empty if omitted) |

**`file_write` params:**
| Param | Required | Description |
|---|:---:|---|
| `path` | ✓ | File path inside pod |
| `content` | ✓ | Content to write |
| `append` | | `"true"` to append instead of overwrite |

**`file_delete` / `dir_delete` params:**
| Param | Required | Description |
|---|:---:|---|
| `path` | ✓ | Path inside pod |
| `recursive` | | `"true"` to remove directory and all contents (default: true) |

**`file_copy` / `file_move` params:**
| Param | Required | Description |
|---|:---:|---|
| `src` | ✓ | Source path inside pod |
| `dst` | ✓ | Destination path inside pod |

**`dir_create` params:**
| Param | Required | Description |
|---|:---:|---|
| `path` | ✓ | Directory path inside pod |

---

### Git

Git actions run `git` commands inside the pod workspace. Auth for remote operations comes from the vault.

| Type | Default Tier | Scope | Description |
|---|---|---|---|
| `git_commit` | staged | internal | Commit changes in the pod workspace |
| `git_push` | staged | internal | Push commits to a remote |
| `git_pull` | immediate | internal | Pull/fetch from a remote |
| `git_checkout` | immediate | internal | Checkout a branch or ref |
| `git_branch` | immediate | internal | Create or delete a branch |
| `git_tag` | immediate | internal | Create (and optionally push) a tag |

**`git_commit` params:**
| Param | Required | Description |
|---|:---:|---|
| `message` | ✓ | Commit message |
| `paths` | | Space-separated paths to commit (default: all staged) |
| `working_dir` | | Working directory (default: pod workspace) |

**`git_push` params:**
| Param | Required | Description |
|---|:---:|---|
| `remote` | | Remote name (default: `origin`) |
| `branch` | | Branch to push (default: current) |
| `working_dir` | | Working directory |

**`git_pull` params:**
| Param | Required | Description |
|---|:---:|---|
| `remote` | | Remote name (default: `origin`) |
| `branch` | | Branch to pull (default: current) |
| `working_dir` | | Working directory |

**`git_checkout` params:**
| Param | Required | Description |
|---|:---:|---|
| `branch` | ✓ | Branch or ref to checkout |
| `create` | | `"true"` to create the branch (`git checkout -b`) |
| `working_dir` | | Working directory |

**`git_branch` params:**
| Param | Required | Description |
|---|:---:|---|
| `name` | ✓ | Branch name |
| `delete` | | `"true"` to delete the branch |
| `working_dir` | | Working directory |

**`git_tag` params:**
| Param | Required | Description |
|---|:---:|---|
| `name` | ✓ | Tag name |
| `message` | | Annotation message (creates annotated tag if set) |
| `push` | | `"true"` to push tag to remote after creating |
| `working_dir` | | Working directory |

**Auth config** for push/pull to private repos:
```json
{
  "config": {
    "auth_vault_key": "GITHUB_TOKEN"
  }
}
```

---

### Messaging

All messaging actions have `staged` default tier — a human sees and approves the message before it is sent. Effects are irreversible (message already delivered) once approved.

| Type | Default Tier | Scope | Description |
|---|---|---|---|
| `send_email` | staged | external | Send email via SendGrid, SMTP, or Mailgun |
| `send_sms` | staged | external | Send SMS via Twilio |
| `slack_message` | staged | external | Post to Slack via webhook or API |
| `discord_message` | staged | external | Post to Discord via webhook |
| `teams_message` | staged | external | Post to Microsoft Teams via webhook |

**`send_email` params:**
| Param | Required | Description |
|---|:---:|---|
| `to` | ✓ | Recipient address (or comma-separated list) |
| `subject` | ✓ | Email subject |
| `body` | ✓ | Email body (plain text or HTML) |
| `cc` | | CC addresses |
| `bcc` | | BCC addresses |
| `html` | | `"true"` if body is HTML |

**`send_email` config:**
| Key | Description |
|---|---|
| `provider` | `sendgrid` (default), `smtp`, `mailgun` |
| `auth_vault_key` | Vault key for API key or SMTP password |
| `from` | Sender address |
| `smtp_host` | SMTP host (only for `provider: smtp`) |
| `smtp_port` | SMTP port (default: 587) |

**`send_sms` params:**
| Param | Required | Description |
|---|:---:|---|
| `to` | ✓ | Recipient phone number (E.164, e.g. `+14155550123`) |
| `body` | ✓ | Message text (max 160 chars for single segment) |

**`send_sms` config:**
| Key | Description |
|---|---|
| `auth_vault_key` | Vault key for Twilio Auth Token |
| `account_sid` | Twilio Account SID |
| `from` | Twilio phone number |

**`slack_message` params:**
| Param | Required | Description |
|---|:---:|---|
| `text` | ✓ | Message text (supports Slack mrkdwn) |
| `channel` | | Channel or DM override |
| `username` | | Bot display name override |
| `icon_emoji` | | Emoji icon (e.g. `:robot_face:`) |
| `attachments` | | JSON array of Slack attachment objects |

**`slack_message` config:**
| Key | Description |
|---|---|
| `auth_vault_key` | Vault key for webhook URL or Bot token |

**`discord_message` params:**
| Param | Required | Description |
|---|:---:|---|
| `content` | ✓ | Message content (max 2000 chars) |
| `username` | | Override webhook username |
| `avatar_url` | | Override webhook avatar URL |
| `embeds` | | JSON array of Discord embed objects |

**`teams_message` params:**
| Param | Required | Description |
|---|:---:|---|
| `text` | ✓ | Message text (Markdown supported) |
| `title` | | Card title |
| `theme_color` | | Card accent color (hex, e.g. `0076D7`) |

---

### Database

Database actions connect to external databases. The connection string always comes from the vault — never from the action call itself.

| Type | Default Tier | Scope | Description |
|---|---|---|---|
| `db_query` | immediate | external | SQL SELECT (read-only) |
| `db_execute` | staged | external | SQL INSERT / UPDATE / DELETE |

**`db_query` / `db_execute` params:**
| Param | Required | Description |
|---|:---:|---|
| `query` | ✓ | SQL query or statement |
| `connection_vault_key` | ✓ | Vault key holding the connection string |
| `params` | | JSON array of query parameters (parameterized queries) |

---

### System

| Type | Default Tier | Scope | Description |
|---|---|---|---|
| `shell_command` | **blocked** | internal | Run a shell command inside the pod |

`shell_command` is blocked by default — it would give the agent arbitrary code execution. You can override the tier in the action definition if you have a controlled use case, but think carefully before unblocking it.

**`shell_command` params:**
| Param | Required | Description |
|---|:---:|---|
| `command` | ✓ | Shell command to execute |
| `args` | | JSON array of arguments |
| `working_dir` | | Working directory inside pod |
| `timeout_secs` | | Timeout in seconds (default: 30) |

---

## Action Tiers

Every action has a **reversibility tier** that controls how envpod handles it:

| Tier | Behavior | Use When |
|---|---|---|
| `immediate` | Executes synchronously. Inside COW overlay for filesystem ops. | Safe reads, COW-protected writes |
| `delayed` | Queues with a timeout (default 30s). Executes automatically unless cancelled. | Destructive but cancelable operations |
| `staged` | Queues and waits for human approval (`envpod approve`). | Irreversible external effects |
| `blocked` | Queued with Blocked status. Cannot be approved — permanently denied. | Operations the host forbids entirely |

Built-in types have **default tiers** (shown in the tables above). You can override the default by setting `tier` in the action definition:

```json
{
  "name": "send_status_email",
  "action_type": "send_email",
  "tier": "immediate"
}
```

> **Warning:** Overriding `staged` → `immediate` for external actions (email, HTTP POST) means the agent can trigger irreversible effects without any human checkpoint. Only do this for actions where the consequences are fully understood and acceptable.

---

## Action Scope: Internal vs External

Every action has a **scope** that tells you whether it operates inside the pod or reaches the outside world:

| Scope | What it means | Examples |
|---|---|---|
| `internal` | Operates only within the pod's COW overlay or workspace. Fully reversible via `envpod rollback`. A failed or malicious internal action leaves no external footprint. | `file_create`, `file_delete`, `git_commit`, `git_push` |
| `external` | Makes calls outside the pod. Effects may be irreversible (money charged, message sent, data written to an external DB). Require stronger governance. | `http_post`, `send_email`, `send_sms`, `db_execute` |

Scope is shown in the `list_actions` response so agents can understand the weight of each action, and it is shown in the web dashboard queue tab.

> **Note on `git_push`:** Git push is classified as `internal` because it operates on the pod workspace. However, it does make a network call to a remote. If the remote is public or shared, treat it like an external action governance-wise by keeping its tier as `staged`.

---

## Creating Actions

### Built-in Type Action

Use a built-in type when you want envpod to execute the action for you with a fixed, validated schema. You only need to provide the `action_type` and any executor `config`:

```json
[
  {
    "name": "notify_slack",
    "description": "Post a completion message to #agent-updates",
    "action_type": "slack_message",
    "tier": "staged",
    "config": {
      "auth_vault_key": "SLACK_WEBHOOK_URL"
    }
  }
]
```

The params schema for `slack_message` is auto-derived — `text` is required, `channel`, `username`, `icon_emoji`, `attachments` are optional. You do not list them in `params`.

#### Overriding the schema

If you want to restrict which params the agent can set (for example, lock the `from` address so the agent cannot change it), you can provide explicit `params` even with a built-in type. When `params` is non-empty, it takes precedence:

```json
{
  "name": "send_status_email",
  "description": "Send a status update (to/subject/body only — no cc/bcc)",
  "action_type": "send_email",
  "tier": "staged",
  "config": {
    "provider": "sendgrid",
    "auth_vault_key": "SENDGRID_API_KEY",
    "from": "noreply@mycompany.com"
  },
  "params": [
    {"name": "to",      "description": "Recipient",     "required": true},
    {"name": "subject", "description": "Email subject",  "required": true},
    {"name": "body",    "description": "Plain text body","required": true}
  ]
}
```

Now the agent cannot pass `cc`, `bcc`, or `html` — those are not in the schema, so envpod rejects them.

---

### Custom Action

A custom action has no built-in executor — `envpod` queues it, and the host is responsible for execution (e.g. a script, a webhook receiver, or an external system). Use this for domain-specific actions.

```json
{
  "name": "create_jira_ticket",
  "description": "Create a Jira ticket from a bug report",
  "tier": "staged",
  "params": [
    {"name": "title",       "description": "Ticket title",      "required": true},
    {"name": "description", "description": "Bug description",   "required": true},
    {"name": "priority",    "description": "low/medium/high",   "required": false},
    {"name": "labels",      "description": "Comma-separated",   "required": false}
  ]
}
```

When approved, the host can poll the queue and execute it:

```bash
# See all approved custom actions waiting
sudo envpod queue myagent --status approved

# Read the payload
sudo envpod queue myagent --id <id> --json | jq .payload

# Mark it executed after your system handles it
sudo envpod approve myagent <id>
```

---

### Configuring Auth from the Vault

Never put API keys or passwords in `actions.json`. Reference a vault key by name in the `config` field:

```json
{
  "name": "charge_customer",
  "description": "Create a Stripe payment intent",
  "action_type": "http_post",
  "tier": "staged",
  "config": {
    "auth_vault_key": "STRIPE_SECRET_KEY",
    "auth_scheme": "bearer"
  }
}
```

Store the actual secret in the vault:

```bash
sudo envpod vault set myagent STRIPE_SECRET_KEY sk-live-...
```

At execution time, envpod fetches `STRIPE_SECRET_KEY` from the vault and injects it into the request header. The agent never sees the value — it only passes the `url` and `body` params.

**Auth schemes:**

| Scheme | What envpod injects |
|---|---|
| `bearer` (default) | `Authorization: Bearer <value>` |
| `basic` | `Authorization: Basic <base64(key:value)>` |
| Any other string | Used literally with `{value}` replaced, e.g. `X-API-Key: {value}` |

---

## actions.json Reference

The catalog is a JSON array of action definitions. File path: `{pod_dir}/actions.json`.

### ActionDef fields

| Field | Type | Required | Description |
|---|---|:---:|---|
| `name` | string | ✓ | Unique action name. Used by agents to call it. |
| `description` | string | ✓ | Human-readable description shown in dashboard and `list_actions`. |
| `tier` | string | | `immediate`, `delayed`, `staged`, `blocked`. Default: `staged`. |
| `action_type` | string | | Built-in type name (snake_case). When set, param schema is auto-derived and envpod executes the action on approval. |
| `config` | object | | Non-secret executor config. Secrets must be in the vault — reference them by vault key name here. |
| `params` | array | | Explicit param schema. Overrides built-in schema when non-empty. Required when `action_type` is absent. |

### ParamDef fields

| Field | Type | Required | Description |
|---|---|:---:|---|
| `name` | string | ✓ | Parameter name (used as key in the call's `params` map). |
| `description` | string | | Human-readable description shown in `list_actions`. |
| `required` | bool | | Whether this parameter must be present in the call. Default: `false`. |

### Full example

```json
[
  {
    "name": "send_alert",
    "description": "Send a Slack alert when something goes wrong",
    "action_type": "slack_message",
    "tier": "immediate",
    "config": {
      "auth_vault_key": "SLACK_WEBHOOK_URL"
    }
  },
  {
    "name": "create_pr",
    "description": "Open a pull request on GitHub",
    "action_type": "http_post",
    "tier": "staged",
    "config": {
      "auth_vault_key": "GITHUB_TOKEN",
      "auth_scheme": "bearer"
    }
  },
  {
    "name": "save_output",
    "description": "Write agent output to a file",
    "action_type": "file_write",
    "tier": "immediate"
  },
  {
    "name": "log_event",
    "description": "Append a structured event to the audit log",
    "tier": "immediate",
    "params": [
      {"name": "event",   "description": "Event name",      "required": true},
      {"name": "payload", "description": "JSON payload",    "required": false}
    ]
  }
]
```

---

## CLI Reference

### List defined actions

```bash
sudo envpod actions myagent ls
```

Output:
```
NAME              TIER       SCOPE      TYPE
send_alert        immediate  external   slack_message
create_pr         staged     external   http_post
save_output       immediate  internal   file_write
log_event         immediate  internal   (custom)
```

### Add a built-in action

```bash
sudo envpod actions myagent add \
  --name notify_complete \
  --description "Notify team when task finishes" \
  --type send_email \
  --tier staged
```

Then edit `myagent/actions.json` to add the `config` block with your vault key references.

### Add a custom action

```bash
sudo envpod actions myagent add \
  --name create_jira_ticket \
  --description "Create a Jira ticket" \
  --tier staged \
  --param "title:required" \
  --param "description:required" \
  --param "priority"
```

### Remove an action

```bash
sudo envpod actions myagent remove send_alert
```

### Change an action's tier

```bash
sudo envpod actions myagent set-tier send_alert staged
```

---

## Agent Protocol (Socket API)

Agents communicate over `/run/envpod/queue.sock` (Unix domain socket, newline-delimited JSON).

The socket accepts up to **120 requests/min globally** and **20 free-form `submit` requests/min**. All request types including `list_actions` are rate-limited to prevent abuse.

### `list_actions`

Discover available actions:

```json
{"type": "list_actions"}
```

Response:
```json
{
  "ok": true,
  "actions": [
    {
      "name": "send_alert",
      "description": "Send a Slack alert when something goes wrong",
      "tier": "immediate",
      "scope": "external",
      "action_type": "slack_message",
      "params": [
        {"name": "text",        "required": true,  "description": "Message text"},
        {"name": "channel",     "required": false, "description": "Channel or DM"},
        {"name": "username",    "required": false, "description": "Bot display name override"},
        {"name": "icon_emoji",  "required": false, "description": "Emoji icon"},
        {"name": "attachments", "required": false, "description": "JSON array of Slack attachments"}
      ]
    }
  ]
}
```

### `call`

Call a catalog action by name:

```json
{
  "type": "call",
  "action": "send_alert",
  "params": {
    "text": "Task complete: processed 1,423 records",
    "icon_emoji": ":white_check_mark:"
  }
}
```

Response (immediate queue):
```json
{"ok": true, "id": "a1b2c3d4...", "status": "queued", "tier": "immediate"}
```

### `poll`

Check action status:

```json
{"type": "poll", "id": "a1b2c3d4..."}
```

Response:
```json
{"ok": true, "status": "executed"}
```

Possible statuses: `queued`, `approved`, `executed`, `cancelled`, `blocked`.

### `submit`

Submit a free-form (non-catalog) action for approval:

```json
{
  "type": "submit",
  "tier": "staged",
  "description": "Refactor the authentication module to use JWT"
}
```

This is the low-governance path — the agent controls the label. Use catalog `call` instead whenever possible.

---

## Security Model

### What agents can do

- `list_actions` — read the catalog (query, not write)
- `call` — submit a catalog action for execution (validated, queued, executed by envpod)
- `poll` — check their own action status
- `submit` — submit a free-form action for human approval

### What agents cannot do

- Write `actions.json` (host filesystem, not in the overlay)
- Change action tiers at runtime
- Execute actions directly (envpod always intermediates)
- See vault secrets (referenced by name only in config)
- Pass params not in the catalog schema (rejected before queuing)
- Escape the pod via filesystem actions (`..` traversal rejected, path must stay inside overlay)

### Tier override security

If you change a `staged` action to `immediate`, you are trusting that the agent cannot abuse it. For external actions (email, HTTP POST, SMS), consider carefully:
- Is the endpoint read-only? → `immediate` is fine (`http_get`, `db_query`)
- Does the action send money or irreversible messages? → keep `staged`
- Is the blast radius limited? → use `delayed` so you can cancel within the grace window

### Blocked actions

`blocked` tier is **absolute** — blocked actions are queued with Blocked status and cannot be approved via `envpod approve`. This is the enforcement mechanism for actions the host categorically forbids.

---

## Full Example: Agent with Email + Git + Slack

This example defines a catalog for a coding agent that can commit its work, notify the team on Slack, and email a completion report — all with appropriate governance.

### pod.yaml

```yaml
name: coding-agent
network:
  mode: Filtered
  allow:
    - github.com
    - api.github.com
    - api.sendgrid.com
    - hooks.slack.com
queue:
  socket: true
  require_commit_approval: false
```

### actions.json

```json
[
  {
    "name": "commit_work",
    "description": "Commit completed changes to the feature branch",
    "action_type": "git_commit",
    "tier": "staged"
  },
  {
    "name": "push_branch",
    "description": "Push the feature branch to GitHub",
    "action_type": "git_push",
    "tier": "staged",
    "config": {
      "auth_vault_key": "GITHUB_TOKEN",
      "auth_scheme": "bearer"
    }
  },
  {
    "name": "notify_team",
    "description": "Post a Slack update when work is ready for review",
    "action_type": "slack_message",
    "tier": "staged",
    "config": {
      "auth_vault_key": "SLACK_WEBHOOK_URL"
    }
  },
  {
    "name": "email_report",
    "description": "Email a detailed completion report to the project owner",
    "action_type": "send_email",
    "tier": "staged",
    "config": {
      "provider": "sendgrid",
      "auth_vault_key": "SENDGRID_API_KEY",
      "from": "agent@mycompany.com"
    }
  },
  {
    "name": "write_summary",
    "description": "Write a markdown summary of completed work to /workspace/SUMMARY.md",
    "action_type": "file_write",
    "tier": "immediate",
    "params": [
      {"name": "content", "description": "Markdown content", "required": true}
    ],
    "config": {
      "path": "/workspace/SUMMARY.md"
    }
  }
]
```

### Vault setup

```bash
sudo envpod vault set coding-agent GITHUB_TOKEN ghp_...
sudo envpod vault set coding-agent SENDGRID_API_KEY SG....
sudo envpod vault set coding-agent SLACK_WEBHOOK_URL https://hooks.slack.com/services/...
```

### Run

```bash
sudo envpod run coding-agent -- python agent.py
```

### Approval workflow

```bash
# Agent completes work, calls commit_work and notify_team
# Both land in the queue as staged

sudo envpod queue coding-agent
# ID        TIER    STATUS   ACTION
# a1b2c3    staged  queued   commit_work: "feat: add OAuth2 login flow"
# a1b2c4    staged  queued   notify_team: "OAuth2 PR ready for review"

# Review and approve both
sudo envpod approve coding-agent a1b2c3
sudo envpod approve coding-agent a1b2c4
```

---

*Copyright 2026 Xtellix Inc. All rights reserved.*
