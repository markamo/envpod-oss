# Tutorial: Let an AI Agent Build and Deploy Your Service

An AI agent builds your service from scratch. You review the diff. Expose the ports. It's live. One command to undo if it goes wrong.

No Docker. No CI/CD. No deployment pipeline. The agent builds, you govern.

## What You'll Do

```
1. Start an empty governed pod
2. Tell the agent what to build
3. Agent writes code (in COW overlay — your files untouched)
4. Review what it created (envpod diff)
5. Agent registers its own health checks
6. You expose the ports it chose
7. Live on the internet
8. Don't like it? One command rollback
```

## Prerequisites

- envpod installed (`curl -fsSL https://envpod.dev/install.sh | sh`)
- An LLM API key (Anthropic, OpenAI, or local Ollama)
- Cloudflare Tunnel (optional — for internet exposure)

## Step 1: Create an Empty Pod

```yaml
# builder.yaml
name: builder
type: standard

filesystem:
  system_access: advanced
  workspace: /workspace
  tracking:
    watch: [/workspace]
    ignore: [/var/cache, /var/lib/apt, /tmp, /run]

network:
  mode: Monitored
  dns:
    mode: Denylist
    deny: []

processor:
  cores: 4.0
  memory: "4GB"
  max_pids: 512

vault:
  env:
    - ANTHROPIC_API_KEY

budget:
  max_duration: "4h"

audit:
  action_log: true

setup:
  - "apt-get update && apt-get install -y python3 python3-pip curl git nodejs npm"
  - "pip install flask gunicorn requests"
```

```bash
sudo envpod init builder -c builder.yaml
echo -n "sk-ant-..." | sudo envpod vault builder set ANTHROPIC_API_KEY
```

## Step 2: Let the Agent Build

```bash
# Enter the pod
sudo envpod run builder --root -- bash

# Inside the pod — tell the agent what to build:
# Option A: Use Claude Code
claude "Build a REST API for a bookmark manager.
  - POST /api/bookmarks (url, title, tags)
  - GET /api/bookmarks (list all, filter by tag)
  - DELETE /api/bookmarks/:id
  - GET /health
  Use Flask, SQLite, save to /workspace/bookmarks.db.
  Create server.py in /workspace.
  Make it production-ready with error handling."

# Option B: Use any coding agent
# python3 my_agent.py "Build a bookmark API..."

# Option C: Build it yourself
# vim /workspace/server.py
```

The agent writes code. Every file goes to the COW overlay — your host is untouched.

## Step 3: Review What the Agent Created

```bash
# Exit the pod (Ctrl+D), then:
sudo envpod diff builder
```

```
Modified files in builder:
  A /workspace/server.py          (+142 lines)
  A /workspace/requirements.txt   (+4 lines)
  A /workspace/README.md          (+28 lines)
```

Read the code:
```bash
sudo envpod run builder -- cat /workspace/server.py
```

**This is the governance moment.** You see exactly what the agent wrote before anything goes live. No surprises.

## Step 4: Test It Inside the Pod

```bash
sudo envpod run builder --root -- bash

# Inside the pod:
cd /workspace
python3 server.py &

# Test it
curl http://localhost:5000/health
# → {"status":"ok"}

curl -X POST http://localhost:5000/api/bookmarks \
  -H "Content-Type: application/json" \
  -d '{"url":"https://envpod.dev","title":"envpod","tags":["tools","ai"]}'
# → {"id":1,"url":"https://envpod.dev",...}

curl http://localhost:5000/api/bookmarks
# → [{"id":1,...}]

# Works! Kill the test server
kill %1
exit
```

## Step 5: Accept or Reject

**Happy with it:**
```bash
sudo envpod commit builder /workspace
# Agent's code is now permanent in the overlay
```

**Not happy:**
```bash
sudo envpod rollback builder
# Everything the agent wrote is gone. Clean slate. Try again.
```

## Step 6: Expose the Ports

The agent built on port 5000. Expose it:

```bash
# Expose the port the agent chose
sudo envpod expose builder --add 5000

# Verify
sudo envpod expose builder --list
# Exposed ports:
#   5000
```

## Step 7: Add Health Check

```bash
sudo envpod health builder add \
  --name api \
  --endpoint /health \
  --port 5000 \
  --retries 3
```

Now envpod monitors the service. Crashes → auto-restart.

## Step 8: Make It Production

Update the start command to use gunicorn:

```bash
# Run with gunicorn instead of dev server
sudo envpod run builder --root -- bash -c \
  "cd /workspace && gunicorn -b 0.0.0.0:5000 -w 2 -D server:app"
```

## Step 9: Expose to the Internet

**Option A: ngrok (quick, prototyping)**
```bash
# On host:
ngrok http 10.200.1.2:5000
# → https://abc123.ngrok.io — live on the internet
```

**Option B: Cloudflare Tunnel (production)**

In Cloudflare dashboard:
```
bookmarks.yourdomain.com → http://10.200.1.2:5000
```

```bash
curl https://bookmarks.yourdomain.com/health
# → {"status":"ok"}
```

## Step 10: Register as Service

```bash
sudo envpod service register builder
# Auto-starts on boot, restarts on crash
```

## The Full Flow — 60 Seconds

```bash
# Create pod
sudo envpod init builder -c builder.yaml

# Agent builds
sudo envpod run builder --root -- claude "Build a bookmark REST API with Flask"

# Review
sudo envpod diff builder

# Accept
sudo envpod commit builder /workspace

# Expose
sudo envpod expose builder --add 5000

# Health check
sudo envpod health builder add --name api --endpoint /health --port 5000

# Live
ngrok http 10.200.1.2:5000

# Undo everything if needed
sudo envpod rollback builder
```

Agent built it. You reviewed it. You exposed it. It's live. One command to undo.

## Why This Only Works with envpod

| Step | Docker | VM | envpod |
|---|---|---|---|
| Agent writes code | On host filesystem (risky) | Inside VM (heavy) | COW overlay (safe, tracked) |
| Review changes | `git diff` (if committed) | SSH in and look | `envpod diff` (automatic) |
| Accept changes | Manual copy | Snapshot | `envpod commit` (one command) |
| Reject changes | Manual cleanup | Delete VM | `envpod rollback` (instant) |
| Expose ports | Edit Dockerfile, rebuild | Port forward config | `envpod expose --add` (live) |
| Health monitoring | Restart entire container | External tool | `envpod health add` (live, per-service) |
| Undo deployment | Rebuild from scratch | Restore snapshot | `envpod rollback` (instant) |

## What the Agent Can't Do

Even with full code access inside the pod:

- Can't modify your host files (COW overlay)
- Can't access your network (namespace isolation)
- Can't see your other pods (bilateral discovery required)
- Can't expose its own ports (only you can `envpod expose`)
- Can't register its own services (only you can `envpod service register`)
- Can't escape the pod (seccomp-BPF, NO_NEW_PRIVS, namespace isolation)

The agent has creative freedom. You have governance control. Both are necessary.

## Next Steps

- **Add API keys** — use vault for customer authentication (see TUTORIAL-PAID-API.md)
- **Multiple agents** — one builds frontend, another builds backend, review both diffs
- **Auto-deploy pipeline** — agent builds → tests pass → auto-commit → auto-expose
- **Premium features** — multi-check health, recovery sequences, OPA policy, scorecard
