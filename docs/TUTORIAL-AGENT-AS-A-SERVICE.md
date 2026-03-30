# Tutorial: Expose an AI Agent as a Service

Run an AI agent as a live production service on the internet. Every tool call governed, every file write tracked, every action auditable. No Docker, no Kubernetes, no cloud platform.

## The Problem

You built an AI agent. It can read files, write code, run shell commands, call APIs. Now you want to expose it as a service — let users hit an endpoint, the agent does the work, results come back.

Without guardrails, this is dangerous:
- The agent has tool access. A malicious prompt could exfiltrate data.
- The agent writes files. One bad run could corrupt the workspace for the next request.
- The agent calls external APIs. Nothing stops it from hitting anything on the internet.
- The agent runs shell commands. One `rm -rf` and you're done.
- There's no record of what the agent did per-request.

You need a runtime that lets the agent work freely while enforcing hard boundaries around what it can touch. That's envpod.

## What You'll Build

An AI agent exposed as an HTTPS endpoint:
- Users send a task over HTTP
- The agent runs inside a governed envpod pod
- envpod controls what files, network, and tools the agent can access
- Every action is logged in an audit trail
- Filesystem changes are tracked and reversible
- Health-checked with auto-restart
- Exposed to the internet via ngrok (prototype) or Cloudflare Tunnel (production)

## Prerequisites

- Linux machine (local, VPS, or cloud)
- envpod installed (`curl -fsSL https://envpod.dev/install.sh | sh`)
- An LLM API key (OpenAI, Anthropic, or any provider)
- For prototyping: `ngrok` installed (free at [ngrok.com](https://ngrok.com))
- For production: Cloudflare account (free) with a domain, `cloudflared` installed on the host

## Step 1: Write the Agent Service (3 minutes)

Create a folder for your agent:

```bash
mkdir -p /opt/agent-service && cd /opt/agent-service
```

Create `agent.py` — a tool-using agent exposed as an HTTP endpoint:

```python
#!/usr/bin/env python3
"""AI agent exposed as a web service."""

import os
import json
import subprocess
import functools
from flask import Flask, request, jsonify
from openai import OpenAI

app = Flask(__name__)

VALID_TOKENS = set(k for k in os.environ.get("AUTH_TOKENS", "").split(",") if k)
client = OpenAI(api_key=os.environ.get("LLM_API_KEY", ""))

WORKSPACE = "/workspace"

# Tools the agent can use
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read a file from the workspace",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Relative path within /workspace"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Write content to a file in the workspace",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Relative path within /workspace"},
                    "content": {"type": "string", "description": "File content"}
                },
                "required": ["path", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": "Run a shell command in the workspace",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Shell command to execute"}
                },
                "required": ["command"]
            }
        }
    }
]


def require_auth(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        token = request.headers.get("Authorization", "").replace("Bearer ", "")
        if token not in VALID_TOKENS or not token:
            return jsonify({"error": "unauthorized"}), 401
        return f(*args, **kwargs)
    return wrapper


def execute_tool(name, args):
    """Execute a tool call. envpod governs what actually happens."""
    if name == "read_file":
        filepath = os.path.join(WORKSPACE, args["path"])
        try:
            with open(filepath, "r") as f:
                return f.read()
        except Exception as e:
            return f"Error: {e}"

    elif name == "write_file":
        filepath = os.path.join(WORKSPACE, args["path"])
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, "w") as f:
            f.write(args["content"])
        return f"Written to {args['path']}"

    elif name == "run_command":
        try:
            result = subprocess.run(
                args["command"], shell=True, capture_output=True,
                text=True, timeout=30, cwd=WORKSPACE
            )
            output = result.stdout + result.stderr
            return output[:4000] if output else "(no output)"
        except subprocess.TimeoutExpired:
            return "Error: command timed out (30s)"

    return "Error: unknown tool"


def run_agent(task):
    """Run the agent loop: LLM plans, tools execute, envpod governs."""
    messages = [
        {"role": "system", "content": (
            "You are an AI agent running inside a governed sandbox. "
            "You have tools to read files, write files, and run shell commands. "
            "All actions are logged and auditable. Work within /workspace."
        )},
        {"role": "user", "content": task}
    ]

    # Agent loop (max 10 iterations)
    for _ in range(10):
        response = client.chat.completions.create(
            model="gpt-4o",
            messages=messages,
            tools=TOOLS
        )

        choice = response.choices[0]

        # No tool calls — agent is done
        if choice.finish_reason == "stop":
            return choice.message.content

        # Execute tool calls
        messages.append(choice.message)
        for tool_call in choice.message.tool_calls:
            args = json.loads(tool_call.function.arguments)
            result = execute_tool(tool_call.function.name, args)
            messages.append({
                "role": "tool",
                "tool_call_id": tool_call.id,
                "content": result
            })

    return "Agent reached iteration limit."


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/agent/run", methods=["POST"])
@require_auth
def agent_run():
    data = request.get_json(force=True)
    task = data.get("task", "")
    if not task:
        return jsonify({"error": "missing 'task' field"}), 400

    result = run_agent(task)
    return jsonify({"result": result})


@app.route("/agent/workspace", methods=["GET"])
@require_auth
def list_workspace():
    """List files the agent has created or modified."""
    files = []
    for root, dirs, filenames in os.walk(WORKSPACE):
        for fname in filenames:
            full = os.path.join(root, fname)
            rel = os.path.relpath(full, WORKSPACE)
            files.append(rel)
    return jsonify({"files": files})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
```

This agent accepts a task, uses tools to complete it, and returns the result. It can read files, write files, and run commands. envpod governs every one of those actions.

## Step 2: Write pod.yaml (2 minutes)

Create `pod.yaml`:

```yaml
name: agent-service
type: standard

filesystem:
  system_access: advanced
  mount_cwd: true
  workspace: /workspace
  tracking:
    watch: [/workspace]
    ignore: [/var/cache, /var/lib/apt, /tmp, /run]

network:
  mode: Monitored
  dns:
    mode: Allowlist
    allow:
      - archive.ubuntu.com
      - "*.ubuntu.com"
      - pypi.org
      - "*.pypi.org"
      - files.pythonhosted.org
      - api.openai.com         # LLM provider
  expose:
    - 8080

processor:
  cores: 2.0
  memory: "1GB"
  max_pids: 128

vault:
  env:
    - AUTH_TOKENS
    - LLM_API_KEY

budget:
  max_duration: "720h"

audit:
  action_log: true

health:
  endpoint: /health
  port: 8080
  interval: 30
  timeout: 5
  retries: 3
  action: restart
  grace_period: 10

setup:
  - "apt-get update && apt-get install -y --no-install-recommends python3 python3-pip"
  - "pip install flask gunicorn openai"
  - "mkdir -p /workspace && chmod 777 /workspace"

start_command: ["bash", "-c", "cd /opt/agent-service && gunicorn -b 0.0.0.0:8080 -w 2 --timeout 120 agent:app"]
```

Notice the DNS allowlist. The agent can reach `api.openai.com` to call the LLM and `pypi.org` to install packages. It cannot reach anything else. If a prompt injection tries to make the agent exfiltrate data to `evil.com`, the DNS request is blocked at the kernel level.

## Step 3: Deploy (2 minutes)

```bash
cd /opt/agent-service && sudo envpod init agent-service -c pod.yaml

# Store secrets in vault
echo -n "tok_user1_abc,tok_user2_def" | sudo envpod vault agent-service set AUTH_TOKENS
echo -n "sk-your-openai-key-here" | sudo envpod vault agent-service set LLM_API_KEY

# Start
sudo envpod start agent-service

# Verify
sudo envpod ls
# → agent-service    running    10.200.1.2

curl http://10.200.1.2:8080/health
# → {"status":"ok"}
```

## Step 4: Test the Agent (2 minutes)

Send the agent a task:

```bash
curl -X POST http://10.200.1.2:8080/agent/run \
  -H "Authorization: Bearer tok_user1_abc" \
  -d '{"task": "Create a Python script that generates the first 20 Fibonacci numbers and save it to fib.py, then run it"}'
```

Response:
```json
{
  "result": "Done. I created fib.py and ran it. The first 20 Fibonacci numbers are: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597, 2584, 4181"
}
```

Check what the agent created:

```bash
curl -H "Authorization: Bearer tok_user1_abc" \
  http://10.200.1.2:8080/agent/workspace
# → {"files": ["fib.py"]}
```

See what changed at the envpod level:

```bash
sudo envpod diff agent-service
# → + /workspace/fib.py

sudo envpod audit agent-service
# → [timestamp] write_file /workspace/fib.py
# → [timestamp] run_command "python3 fib.py"
```

## Step 5: Expose to the Internet

### Option A: ngrok (prototype in 30 seconds)

One command. Public HTTPS URL. No domain, no DNS, no dashboard.

```bash
# Get the pod IP
POD_IP=$(sudo envpod ls | grep agent-service | awk '{print $3}')

# Expose it
ngrok http ${POD_IP}:8080
```

ngrok gives you a URL like `https://a1b2c3d4.ngrok-free.app`. Test it:

```bash
curl -X POST https://a1b2c3d4.ngrok-free.app/agent/run \
  -H "Authorization: Bearer tok_user1_abc" \
  -d '{"task": "List all Python files in the workspace and summarize what each one does"}'
```

Your agent is live on the internet. Share the URL, demo it, iterate.

> ngrok is ideal for demos, testing webhooks, and sharing prototypes. For always-on production services, use Cloudflare Tunnel below.

### Option B: Cloudflare Tunnel (production)

Stable URL, custom domain, DDoS protection, zero-trust.

In Cloudflare Zero Trust dashboard:
1. Networks → Tunnels → your tunnel → Public Hostname
2. Add: `agent.yourdomain.com → http://10.200.1.2:8080`

Test:

```bash
curl -X POST https://agent.yourdomain.com/agent/run \
  -H "Authorization: Bearer tok_user1_abc" \
  -d '{"task": "List all Python files in the workspace and summarize what each one does"}'
```

Your agent is live on a stable production URL.

## Step 6: Auto-Start on Boot (1 minute)

```bash
sudo envpod service register agent-service
```

Survives reboots, restarts on crash, health-checked.

## What's Protecting You

The agent has real tool access — file I/O, shell commands, network calls. envpod enforces the boundaries:

```
✓ DNS allowlist — agent can only reach the LLM provider, nothing else
✓ Filesystem tracking — every file the agent creates or modifies is diffed
✓ Audit trail — every tool call logged with timestamps
✓ COW filesystem — rollback the workspace to any prior state
✓ Vault — LLM keys and auth tokens encrypted, never in code
✓ seccomp-BPF — dangerous syscalls blocked at kernel level
✓ PID/network/mount namespaces — full isolation from host
✓ Max PIDs — agent can't fork-bomb the system
✓ Health checks — auto-restart if the service goes down
✓ Gunicorn timeout — no single request runs forever (120s)
```

A prompt injection can try to make the agent call `curl evil.com`. The DNS allowlist blocks it. It can try `rm -rf /`. Namespace isolation and seccomp stop it. It can try to read `/etc/shadow`. Filesystem permissions deny it. envpod doesn't trust the agent. It governs the agent.

## Operations

### Review agent activity

```bash
# What files has the agent changed?
sudo envpod diff agent-service

# Full action log
sudo envpod audit agent-service
sudo envpod audit agent-service --json

# Commit a good state
sudo envpod commit agent-service -m "clean workspace after batch run"
```

### Reset the workspace

```bash
# Roll back all agent changes since last commit
sudo envpod rollback agent-service
sudo envpod service restart agent-service
```

### Swap LLM providers

Switch from OpenAI to Anthropic — update the vault and DNS allowlist:

```yaml
# In pod.yaml, change:
network:
  dns:
    allow:
      - api.anthropic.com    # swap provider
```

```bash
echo -n "sk-ant-your-key" | sudo envpod vault agent-service set LLM_API_KEY
# Update agent.py to use Anthropic SDK
sudo envpod service restart agent-service
```

The DNS allowlist ensures the agent can only reach the provider you choose. Swap one line, the agent can never call the old provider again.

### Add a token

```bash
CURRENT=$(sudo envpod vault agent-service get AUTH_TOKENS)
echo -n "${CURRENT},tok_newuser_xyz" | sudo envpod vault agent-service set AUTH_TOKENS
sudo envpod service restart agent-service
```

### Revoke a token

```bash
CURRENT=$(sudo envpod vault agent-service get AUTH_TOKENS)
UPDATED=$(echo "$CURRENT" | tr ',' '\n' | grep -v "tok_user2_def" | paste -sd ',')
echo -n "$UPDATED" | sudo envpod vault agent-service set AUTH_TOKENS
sudo envpod service restart agent-service
```

## Scaling Up

### Per-request isolation (Premium)

Each request gets its own ephemeral workspace — no bleed between users:

```yaml
# Premium: per-request COW snapshot
isolation:
  mode: per_request
  workspace_snapshot: true
  cleanup: on_response
```

### Rate limiting (Premium)

```yaml
policy:
  enabled: true
  # l7.rego: 10 agent runs per minute per token
```

### Multiple agents (Premium)

```yaml
health:
  checks:
    - name: api
      endpoint: /health
      port: 8080
    - name: worker
      command: "pgrep -f celery"
    - name: redis
      command: "redis-cli ping | grep PONG"
```

### GPU access

For agents that run local models:

```yaml
processor:
  cores: 4.0
  memory: "16GB"
  gpu:
    enabled: true
    devices: [0]
```

## Cost

| Component | Cost |
|---|---|
| envpod CE | $0 |
| ngrok (prototype) | $0 (free tier) |
| Cloudflare Tunnel (production) | $0 (free tier) |
| LLM API | usage-based |
| VPS (optional) | $5-10/month |
| Domain (production only) | $10/year |
| **Total** | **$0 to prototype, $5-10/month in production + LLM usage** |

Compare: AWS Lambda + API Gateway + Secrets Manager + CloudWatch + custom sandboxing = $50+/month before you even start.

## The Pattern

Any agent, any framework, same flow:

```bash
mkdir /opt/my-agent && cd /opt/my-agent
# Write agent code + pod.yaml
sudo envpod init my-agent -c pod.yaml
echo -n "sk-key" | sudo envpod vault my-agent set LLM_API_KEY
echo -n "tokens" | sudo envpod vault my-agent set AUTH_TOKENS
sudo envpod start my-agent
sudo envpod service register my-agent
# Prototype: ngrok http $(sudo envpod ls | grep my-agent | awk '{print $3}'):8080
# Production: CF tunnel → my-agent.example.com → pod IP
```

LangChain agents. CrewAI crews. AutoGen teams. Raw API tool-calling loops. Any framework, any model. envpod doesn't care what the agent is built with. It governs what the agent can do.

The agent runs. envpod governs. ngrok or Cloudflare exposes. You sleep at night.
