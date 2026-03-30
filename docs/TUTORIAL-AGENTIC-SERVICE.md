# Tutorial: Expose an Agentic Service to the Web

Your AI agent just built a service. Now ship it to production — governed, auditable, reversible. No Docker, no Kubernetes, no cloud platform.

## The Problem

AI agents can write and run code. But putting an agent-built service on the public internet? Without guardrails, that's a liability. The agent could:
- Hardcode secrets in source files
- Open network access to anywhere
- Install packages with known vulnerabilities
- Modify system files outside its workspace
- Leave no record of what it actually did

envpod solves this. The agent works freely inside a governed pod. You review the diff, then expose it.

## What You'll Build

An agent writes a web service inside an envpod pod. You:
- Review exactly what the agent created
- Store secrets in an encrypted vault (not in code)
- Expose only one port through a DNS allowlist
- Ship it to the internet via Cloudflare Tunnel
- Get health checks, auto-restart, and a full audit trail

## Prerequisites

- Linux machine (local, VPS, or cloud)
- envpod installed (`curl -fsSL https://envpod.dev/install.sh | sh`)
- Cloudflare account (free) with a domain
- `cloudflared` installed on the host

## Step 1: Create the Pod (1 minute)

Create a folder and `pod.yaml`:

```bash
mkdir -p /opt/my-service && cd /opt/my-service
```

```yaml
name: my-service
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
  expose:
    - 8080

processor:
  cores: 1.0
  memory: "512MB"
  max_pids: 64

vault:
  env:
    - AUTH_TOKENS

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
  - "pip install flask gunicorn"
  - "mkdir -p /workspace && chmod 777 /workspace"

start_command: ["bash", "-c", "cd /opt/my-service && gunicorn -b 0.0.0.0:8080 -w 2 server:app"]
```

Init the pod:

```bash
cd /opt/my-service && sudo envpod init my-service -c pod.yaml
```

The agent now has a governed workspace. It can install packages from PyPI, write files in `/workspace`, and listen on port 8080. Nothing else.

## Step 2: Agent Builds the Service

Point your agent at the pod. It writes `server.py`:

```python
#!/usr/bin/env python3
"""Web service built by an AI agent."""

import os
import functools
from flask import Flask, request, jsonify

app = Flask(__name__)

# Auth tokens loaded from vault (injected as env var)
VALID_TOKENS = set(k for k in os.environ.get("AUTH_TOKENS", "").split(",") if k)

def require_auth(f):
    """Check token in Authorization header."""
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        token = request.headers.get("Authorization", "").replace("Bearer ", "")
        if token not in VALID_TOKENS or not token:
            return jsonify({"error": "unauthorized"}), 401
        return f(*args, **kwargs)
    return wrapper

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

@app.route("/api/v1/analyze", methods=["POST"])
@require_auth
def analyze():
    data = request.get_json(force=True)
    text = data.get("text", "")
    result = {
        "text": text,
        "word_count": len(text.split()),
        "char_count": len(text),
    }
    return jsonify(result)

@app.route("/api/v1/status")
@require_auth
def status():
    return jsonify({"status": "active"})

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
```

The agent can write whatever it wants. envpod tracked every file it created, every package it installed, every network call it made.

## Step 3: Review What the Agent Did (1 minute)

Before this goes anywhere near the internet:

```bash
# See every file the agent created or modified
sudo envpod diff my-service
# → + /opt/my-service/server.py
# → + /workspace/...

# Check the audit trail
sudo envpod audit my-service
# → [timestamp] pip install flask gunicorn
# → [timestamp] wrote /opt/my-service/server.py (42 lines)

# Satisfied? Commit the state
sudo envpod commit my-service -m "agent: initial service build"
```

If something looks wrong:

```bash
# Undo everything the agent did
sudo envpod rollback my-service
```

This is the step that makes agentic deployment safe. You see exactly what changed before anything goes live.

## Step 4: Add Secrets and Start (2 minutes)

Secrets go in the vault, not in code:

```bash
# Add auth tokens to vault (comma-separated)
echo -n "tok_abc123,tok_def456" | sudo envpod vault my-service set AUTH_TOKENS

# Start the service
sudo envpod start my-service

# Verify
sudo envpod ls
# → my-service    running    10.200.1.2

curl http://10.200.1.2:8080/health
# → {"status":"ok"}

curl -X POST http://10.200.1.2:8080/api/v1/analyze \
  -H "Authorization: Bearer tok_abc123" \
  -d '{"text": "Built by an agent, governed by envpod"}'
# → {"text":"Built by an agent, governed by envpod","word_count":7,"char_count":38}

# Without auth
curl http://10.200.1.2:8080/api/v1/analyze
# → {"error":"unauthorized"}
```

## Step 5: Expose to the Internet (2 minutes)

In Cloudflare Zero Trust dashboard:
1. Networks → Tunnels → your tunnel → Public Hostname
2. Add: `service.yourdomain.com → http://10.200.1.2:8080`

Test:

```bash
curl https://service.yourdomain.com/health
# → {"status":"ok"}

curl -X POST https://service.yourdomain.com/api/v1/analyze \
  -H "Authorization: Bearer tok_abc123" \
  -d '{"text": "Live on the internet"}'
# → {"text":"Live on the internet","word_count":4,"char_count":20}
```

## Step 6: Auto-Start on Boot (1 minute)

```bash
sudo envpod service register my-service
```

Survives reboots, restarts on crash, health-checked every 30 seconds.

## What's Protecting You

The agent built the service. envpod enforces the boundaries:

```
✓ DNS allowlist — pod can only reach PyPI and Ubuntu repos, nothing else
✓ Secrets in encrypted vault — never in source, never in env files
✓ COW filesystem — diff and rollback any change the agent made
✓ Audit trail — every action logged with timestamps
✓ Health checks — auto-restart on failure, no silent downtime
✓ seccomp-BPF — syscall filtering blocks dangerous kernel calls
✓ Namespace isolation — PID, network, mount all sandboxed
✓ Port exposure — only 8080, nothing else reachable
✓ TLS + DDoS protection — Cloudflare handles the edge
✓ Auto-start on boot — systemd service, survives reboots
```

## Operations

### Agent updates the service

```bash
# Agent makes changes inside the pod
# ...

# Review what changed
sudo envpod diff my-service

# Good? Commit and restart
sudo envpod commit my-service -m "agent: add caching layer"
sudo envpod service restart my-service

# Bad? Rollback
sudo envpod rollback my-service
```

### Add a token

```bash
CURRENT=$(sudo envpod vault my-service get AUTH_TOKENS)
echo -n "${CURRENT},tok_newuser_xyz789" | sudo envpod vault my-service set AUTH_TOKENS
sudo envpod service restart my-service
```

### Revoke a token

```bash
CURRENT=$(sudo envpod vault my-service get AUTH_TOKENS)
UPDATED=$(echo "$CURRENT" | tr ',' '\n' | grep -v "tok_def456" | paste -sd ',')
echo -n "$UPDATED" | sudo envpod vault my-service set AUTH_TOKENS
sudo envpod service restart my-service
```

### Check audit trail

```bash
sudo envpod audit my-service
sudo envpod audit my-service --json
```

## Scaling Up

### More workers

```yaml
processor:
  cores: 4.0
  memory: "2GB"

start_command: ["bash", "-c", "cd /opt/my-service && gunicorn -b 0.0.0.0:8080 -w 8 server:app"]
```

### Database

```yaml
vault:
  env:
    - AUTH_TOKENS
    - DATABASE_URL
```

### Rate limiting (Premium)

```yaml
policy:
  enabled: true
  # l7.rego: per-path, per-token rate limiting via OPA
```

### Multiple processes (Premium)

```yaml
health:
  checks:
    - name: web
      endpoint: /health
      port: 8080
    - name: worker
      command: "pgrep -f worker.py"
    - name: redis
      command: "redis-cli ping | grep PONG"
```

## Cost

| Component | Cost |
|---|---|
| envpod CE | $0 |
| Cloudflare Tunnel | $0 (free tier) |
| VPS (optional) | $5-10/month |
| Domain | $10/year |
| **Total** | **$5-10/month** |

Compare: AWS API Gateway + Lambda + Secrets Manager + CloudWatch = $50+/month minimum.

## The Pattern

Any agent-built service, same flow:

```bash
mkdir /opt/my-service && cd /opt/my-service
# Write pod.yaml
sudo envpod init my-service -c pod.yaml
# Agent builds inside the pod
sudo envpod diff my-service          # review
sudo envpod commit my-service        # accept
echo -n "secret" | sudo envpod vault my-service set MY_SECRET
sudo envpod start my-service
sudo envpod service register my-service
# CF tunnel: my-service.example.com → pod IP
```

The agent builds. You review. envpod governs. Cloudflare exposes. That's it.
