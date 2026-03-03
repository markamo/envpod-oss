# envpod Feature Tiers

> "Docker isolates. Envpod governs."

envpod follows an open-core model. The full isolation and governance
primitives are OSS. High-value security and workflow features are Premium.
Fleet management, compliance, and managed infrastructure are Enterprise.

---

## Quick Comparison

| | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Price | Free | ~$49–99/seat/mo | Custom / annual |
| Source | Apache-2.0 | Proprietary | Proprietary |
| Deployment | Single machine | Single machine | Multi-machine |
| Support | Community / GitHub | Email | SLA + dedicated |

---

## Feature Table

### Isolation

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Linux namespaces (PID / net / mount / UTS / user) | ✓ | ✓ | ✓ |
| cgroups v2 (CPU / memory / IO limits) | ✓ | ✓ | ✓ |
| OverlayFS copy-on-write filesystem | ✓ | ✓ | ✓ |
| seccomp-BPF syscall filtering | ✓ | ✓ | ✓ |
| Network namespace + veth pairs | ✓ | ✓ | ✓ |
| x86\_64 Linux (static musl binary) | ✓ | ✓ | ✓ |
| ARM64 (Raspberry Pi 4/5, Jetson Orin) | ✓ | ✓ | ✓ |
| Pod encryption at rest | — | ✓ | ✓ |
| Custom rootfs (Alpine / debootstrap / OCI image) | — | ✓ | ✓ |
| Docker backend | — | ✓ | ✓ |
| Firecracker microVM backend | — | — | ✓ |

---

### Filesystem Governance

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Diff / Commit / Rollback (CLI) | ✓ | ✓ | ✓ |
| Selective commit (paths / exclude) | ✓ | ✓ | ✓ |
| Commit to custom output directory | ✓ | ✓ | ✓ |
| Basic diff dashboard (file list + kind) | ✓ | ✓ | ✓ |
| Inline git-style diff (per-hunk +/− lines) | — | ✓ | ✓ |
| Per-file / per-hunk selective staging | — | ✓ | ✓ |
| Side-by-side diff view | — | ✓ | ✓ |

---

### Snapshots

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Create / restore / delete snapshots | ✓ | ✓ | ✓ |
| Named snapshots (human-readable labels) | ✓ | ✓ | ✓ |
| Auto-snapshot before each run | ✓ | ✓ | ✓ |
| Auto-prune (keep N, oldest-auto-first) | ✓ | ✓ | ✓ |
| Snapshot dashboard tab | ✓ | ✓ | ✓ |
| Promote snapshot → new clonable base | — | ✓ | ✓ |
| Diff between two snapshots | — | ✓ | ✓ |
| Snapshot export / import (`.tar.gz`) | — | ✓ | ✓ |
| Snapshot timeline visualization | — | ✓ | ✓ |

---

### Base Pods & Cloning

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Base pod create (init + setup → snapshot) | ✓ | ✓ | ✓ |
| Fast clone from base (~130 ms) | ✓ | ✓ | ✓ |
| Clone from current state (`--current`) | ✓ | ✓ | ✓ |
| Base pod export / import (`.tar.gz`) | — | ✓ | ✓ |
| Shared base registry (team-wide) | — | — | ✓ |

---

### Credential Vault

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Encrypted vault (ChaCha20-Poly1305) | ✓ | ✓ | ✓ |
| Env var injection at run time | ✓ | ✓ | ✓ |
| **Vault proxy injection** | — | ✓ | ✓ |
| → Agent-blind API keys (never in env / memory) | — | ✓ | ✓ |
| → TLS MITM with per-pod ephemeral CA | — | ✓ | ✓ |
| → SNI-based header injection (any domain) | — | ✓ | ✓ |
| Vault import from `.env` file | — | ✓ | ✓ |
| Vault export (encrypted) | — | ✓ | ✓ |
| HSM / cloud KMS backend | — | — | ✓ |

> **Why vault proxy is Premium:** Once OSS, any container runtime (Docker,
> cloud providers, e2b, Modal) can absorb the feature in weeks. It is the
> single strongest argument for security-conscious buyers and must stay
> proprietary to protect revenue.

---

### Network

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| DNS allow / deny lists | ✓ | ✓ | ✓ |
| DNS remap / monitor modes | ✓ | ✓ | ✓ |
| Anti-DNS-tunneling | ✓ | ✓ | ✓ |
| Port forwarding (localhost / public / pod-to-pod) | ✓ | ✓ | ✓ |
| Live port mutation (no pod restart) | ✓ | ✓ | ✓ |
| Pod-to-pod discovery (`*.pods.local`) | ✓ | ✓ | ✓ |
| Bandwidth / rate limiting | ✓ | ✓ | ✓ |
| TLS inspection + per-connection audit | — | ✓ | ✓ |
| Full packet audit (PCAP per pod) | — | — | ✓ |
| Tailscale VPN integration | — | — | ✓ |
| Cross-machine pod networking | — | — | ✓ |

---

### Action Queue & Reversibility

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Staged / delayed / blocked / immediate tiers | ✓ | ✓ | ✓ |
| Human approval for staged actions | ✓ | ✓ | ✓ |
| Undo registry (per-action rollback) | ✓ | ✓ | ✓ |
| Queue Unix socket (`/run/envpod/queue.sock`) | ✓ | ✓ | ✓ |
| Commit / rollback gated by queue approval | ✓ | ✓ | ✓ |
| Budget enforcement (action cost caps) | — | ✓ | ✓ |
| Policy-driven auto-approval rules | — | ✓ | ✓ |

---

### Action Catalog

The host-defined menu of what an agent is allowed to do. Agents discover available
actions at runtime via the queue socket, call them by name, and envpod executes
them — after validation, tier checks, and any required human approval.
Credentials are fetched from the vault at execution time; the agent never sees them.

**OSS ships 20 built-in types** covering the full coding and development workflow.
**Premium adds 8 types** with real-world consequences: messaging (irreversible sends),
database writes (production data), and system shell (arbitrary execution).

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Host-defined action catalog (`actions.json`) | ✓ | ✓ | ✓ |
| MCP-style tool discovery (`list_actions`) | ✓ | ✓ | ✓ |
| Param schema validation (required / unknown key rejection) | ✓ | ✓ | ✓ |
| Action scope: internal (reversible) vs external (irreversible) | ✓ | ✓ | ✓ |
| Filesystem containment (no `..` traversal, overlay-only) | ✓ | ✓ | ✓ |
| Auth from vault (`auth_vault_key` in config) | ✓ | ✓ | ✓ |
| Hot-reload catalog without pod restart | ✓ | ✓ | ✓ |
| Rate limiting (120 req/min global, 20 submit/min) | ✓ | ✓ | ✓ |
| **OSS action types — 20 types** | | | |
| → HTTP: GET / POST / PUT / PATCH / DELETE / webhook (6) | ✓ | ✓ | ✓ |
| → Filesystem: create / write / delete / copy / move / mkdir / rmdir (7) | ✓ | ✓ | ✓ |
| → Git: commit / push / pull / checkout / branch / tag (6) | ✓ | ✓ | ✓ |
| → Custom: host-defined schema, host-side executor (1) | ✓ | ✓ | ✓ |
| **Premium action types — 8 types** | | | |
| → Messaging: email / SMS / Slack / Discord / Teams (5) | — | ✓ | ✓ |
| → Database: query (SELECT) / execute (INSERT·UPDATE·DELETE) (2) | — | ✓ | ✓ |
| → System: `shell_command` — arbitrary shell, blocked by default (1) | — | ✓ | ✓ |

> **Why Messaging / Database / Shell are Premium:** these actions have consequences
> outside the pod that cannot be rolled back — a sent message cannot be unsent,
> a `DELETE FROM orders` cannot be undone, a shell command can do anything.
> Operators who need them are the same buyers who need governance guarantees,
> audit trails, and compliance reports. The governance burden matches the risk.

---

### Prompt & Tool Screening

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Tool call interception hooks | ✓ | ✓ | ✓ |
| Prompt / instruction screening | — | ✓ | ✓ |
| Tool call policy engine (allow / deny / rewrite) | — | ✓ | ✓ |
| FEBO ML-powered policy engine | — | ✓ | ✓ |
| Custom policy rules (YAML) | — | ✓ | ✓ |

---

### AI Monitoring Agent

The governance ceiling includes an AI-powered monitoring layer that the operator
configures per pod. Unlike rule-based policy engines, the AI monitoring agent
understands **context** — what the pod is supposed to be doing — and identifies
deviations based on intent, not just fixed patterns.

**How it works:**

1. Operator defines context in `pod.yaml` — what the agent is, what it's allowed
   to do, and what counts as suspicious (plain language, like a system prompt).
2. AI model is configured with BYOK (bring your own key, stored in vault).
   Supports any model: Claude, GPT-4o, Gemini, or a local Llama endpoint.
3. **Pre-execution screening** — the AI reviews staged actions *before* the human
   approval prompt appears. It can pass through, flag as suspicious (with reasoning
   shown to the operator), or block outright.
4. **Post-execution audit analysis** — the AI streams `audit.jsonl` in real time,
   detecting behavioral patterns: rapid deletes, repeated blocked attempts, scope
   creep into unexpected paths, unusual outbound domains.
5. **Intervention hooks** — the AI can trigger: escalate tier, freeze pod, call
   an alert webhook, or append a note to the audit log.

```yaml
# pod.yaml — AI monitoring agent
monitoring:
  ai:
    enabled: true
    model: claude-opus-4-6           # or gpt-4o, gemini-1.5-pro, http://localhost:11434
    auth_vault_key: ANTHROPIC_API_KEY
    context: |
      This pod runs a coding assistant working on a Python web app.
      Normal behaviour: read/write files in /workspace/src, HTTP calls to
      pypi.org and github.com, git commits to the current branch.
      Suspicious: writing outside /workspace, deleting .git, HTTP calls to
      unknown hosts, any attempt to read /etc or environment variables.
    screen_actions: true    # review staged actions before human sees them
    screen_audit: true      # analyze audit stream for anomalies
    intervention:
      suspicious: escalate  # change tier to staged, show AI reasoning
      violation: freeze     # freeze pod immediately
      alert_webhook: https://hooks.slack.com/...
```

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Rule-based anomaly detection (rapid writes, blocked patterns) | ✓ | ✓ | ✓ |
| AI monitoring agent (BYOK) | — | ✓ | ✓ |
| → Context definition per pod (plain-language intent + constraints) | — | ✓ | ✓ |
| → Pre-execution action screening (AI reviews before human prompt) | — | ✓ | ✓ |
| → AI reasoning shown alongside staged action (operator sees why) | — | ✓ | ✓ |
| → Post-execution audit log analysis (behavioral pattern detection) | — | ✓ | ✓ |
| → Intervention hooks (escalate / freeze / alert webhook) | — | ✓ | ✓ |
| → Any model: Claude / GPT / Gemini / local Llama endpoint | — | ✓ | ✓ |
| → Auth key stored in vault (model never sees raw key) | — | ✓ | ✓ |
| Managed AI monitoring (Xtellix-hosted, no user key required) | — | — | ✓ |
| Cross-pod behavioral correlation (fleet-wide anomaly detection) | — | — | ✓ |
| Pre-trained agent behavior models (tuned on envpod audit data) | — | — | ✓ |

> **Why BYOK for Premium:** the operator controls model choice and cost. An
> operator running 50 pods may choose a cheap fast model for routine screening
> and a powerful model only when the rule-based layer raises a flag. Enterprise
> removes the key management burden entirely — Xtellix hosts the inference,
> operators get fleet-wide behavioral intelligence with zero config.

---

### Monitoring & Audit

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Action audit log (`audit.jsonl`) | ✓ | ✓ | ✓ |
| Static security audit (`--security`) | ✓ | ✓ | ✓ |
| Live resource monitoring (cgroup stats) | ✓ | ✓ | ✓ |
| Rule-based anomaly detection | ✓ | ✓ | ✓ |
| AI monitoring agent (see section above) | — | ✓ | ✓ |
| Budget tracking (cost per pod) | — | ✓ | ✓ |
| Tamper-proof signed audit log | — | ✓ | ✓ |
| Audit retention policy + archival | — | — | ✓ |
| Compliance report export (SOC2 / HIPAA) | — | — | ✓ |
| Certified audit (third-party attestation) | — | — | ✓ |

---

### Dashboard & Remote Control

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Web dashboard — fleet overview | ✓ | ✓ | ✓ |
| Web dashboard — pod detail (basic) | ✓ | ✓ | ✓ |
| Web dashboard — audit tab | ✓ | ✓ | ✓ |
| Web dashboard — resources tab | ✓ | ✓ | ✓ |
| Web dashboard — basic diff tab | ✓ | ✓ | ✓ |
| Web dashboard — snapshots tab | ✓ | ✓ | ✓ |
| Web dashboard — inline diff (Premium tab) | — | ✓ | ✓ |
| Remote control API (freeze / kill / restrict) | ✓ | ✓ | ✓ |
| Slack / Telegram / WhatsApp alerts | — | — | ✓ |
| Mobile app (iOS / Android) | — | — | ✓ |

---

### Fleet Management (Enterprise only)

| Feature | OSS | Premium | Enterprise |
|---|:---:|:---:|:---:|
| Single machine | ✓ | ✓ | ✓ |
| Multi-machine fleet | — | — | ✓ |
| RBAC / team permissions | — | — | ✓ |
| SSO / SAML / OIDC | — | — | ✓ |
| Centralized policy management | — | — | ✓ |
| Air-gapped / offline deployment | — | — | ✓ |
| Managed SaaS (hosted envpod) | — | — | ✓ |
| SLA + dedicated support | — | — | ✓ |
| Custom integrations | — | — | ✓ |

---

## Why This Split Works

### OSS is genuinely useful
The full isolation stack, diff/commit/rollback, vault (env injection),
DNS filtering, action queue, 20 built-in action types, snapshots, and web
dashboard — these are production-ready on their own. Solo developers and
small teams running coding agents, research agents, or CI/CD automation
can use envpod for free forever with no artificial limits.

The OSS action types are not an afterthought. HTTP + Filesystem + Git cover
the entire coding agent workflow: fetch docs, write code, commit, push. That
is the primary use case and it is fully unlocked at zero cost.

### Premium solves high-consequence problems
**Vault proxy injection** is the clearest example: "your agents literally
cannot exfiltrate API keys, ever" is a statement no OSS tool can make
once the implementation is public.

**AI monitoring agent** is the second: context-aware pre-execution screening
that understands *what the agent is supposed to be doing* rather than matching
fixed rules. This is not reproducible by copying the OSS codebase — the value
is in the inference layer, the context schema, and the integration between the
audit stream and the action queue.

**Premium action types** (Messaging / Database / Shell) are gated because the
operators who need them are also the operators who need governance. A team
letting an agent send Slack messages or modify a production database needs the
full premium governance stack — AI screening, signed audit, tamper-proof logs
— before enabling those capabilities. The gate is intentional: it prevents
high-consequence actions from being enabled in a low-governance environment.

### Enterprise solves organizational problems
Compliance, fleet management, and SSO are budget line items in regulated
industries. These are sold as annual contracts with SLAs, not seat licenses.
The managed AI monitoring service (no user API key, cross-pod behavioral
intelligence) is the clearest Enterprise differentiator.

---

## Competitive Risk of Going OSS Too Far

Features that would destroy revenue if released as OSS:

| Feature | Who Absorbs It | Time to Clone | Revenue Impact |
|---|---|---|---|
| Vault proxy injection | Docker, AWS, e2b, Modal | 1–2 weeks | Critical |
| AI monitoring agent (context-aware screening) | AWS Bedrock Guardrails, Anthropic | 4–8 weeks | Critical |
| Messaging / Database / Shell action types | Any fork adding 8 executors | 1 week | High |
| TLS inspection (agent-specific) | Cloudflare, AWS WAF | 2–4 weeks | High |
| Prompt / tool screening | AWS Guardrails, Azure Content Safety | 2–4 weeks | High |
| Tamper-proof signed audit | Any fork satisfying SOC2 auditors | 1 week | High |
| Budget tracking per pod | Datadog, cloud cost tools | 1 week | Medium |
| Per-hunk diff staging | Any fork with a React dev | 1 week | Medium |
| FEBO policy engine (framework) | Competitors plug in own models | 2–4 weeks | High |

---

*Copyright 2026 Xtellix Inc. All rights reserved.*
