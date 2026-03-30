# Tutorial: Deploy a Paid API in 10 Minutes

Build and deploy a paid API service with envpod. Governed, health-checked, auto-restart, secrets encrypted — no Docker, no Kubernetes, no cloud platform.

## What You'll Build

A simple API that:
- Serves paying customers with API keys
- Runs isolated in an envpod pod
- Health-checked with auto-restart
- Secrets in encrypted vault (never in config)
- Exposed to the internet via Cloudflare Tunnel
- Auto-starts on boot
- Full audit trail

## Prerequisites

- Linux machine (local, VPS, or cloud)
- envpod installed (`curl -fsSL https://envpod.dev/install.sh | sh`)
- Cloudflare account (free) with a domain
- `cloudflared` installed on the host

## Step 1: Write Your API (2 minutes)

Create a folder for your service:

```bash
mkdir -p /opt/my-api && cd /opt/my-api
```

Create `server.py`:

```python
#!/usr/bin/env python3
"""Simple paid API with key authentication."""

import os
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

# API keys loaded from vault (injected as env var)
VALID_KEYS = set(os.environ.get("API_KEYS", "").split(","))

def require_key(f):
    """Check API key in Authorization header."""
    def wrapper(*args, **kwargs):
        key = request.headers.get("Authorization", "").replace("Bearer ", "")
        if key not in VALID_KEYS or not key:
            return jsonify({"error": "invalid API key"}), 401
        return f(*args, **kwargs)
    wrapper.__name__ = f.__name__
    return wrapper

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

@app.route("/api/v1/analyze", methods=["POST"])
@require_key
def analyze():
    data = request.get_json(force=True)
    text = data.get("text", "")
    # Your logic here
    result = {
        "text": text,
        "word_count": len(text.split()),
        "char_count": len(text),
    }
    return jsonify(result)

@app.route("/api/v1/status")
@require_key
def status():
    return jsonify({"plan": "active", "requests_today": 0})

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
```

## Step 2: Write pod.yaml (2 minutes)

Create `pod.yaml`:

```yaml
name: my-api
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
    - API_KEYS

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

start_command: ["bash", "-c", "cd /opt/my-api && gunicorn -b 0.0.0.0:8080 -w 2 server:app"]
```

## Step 3: Deploy (3 minutes)

```bash
# Init the pod
cd /opt/my-api && sudo envpod init my-api -c pod.yaml

# Add API keys to vault (comma-separated)
echo -n "key_customer1_abc123,key_customer2_def456" | sudo envpod vault my-api set API_KEYS

# Start
sudo envpod start my-api

# Get pod IP
sudo envpod ls
# → my-api    running    10.200.1.2

# Test locally
curl http://10.200.1.2:8080/health
# → {"status":"ok"}

curl -X POST http://10.200.1.2:8080/api/v1/analyze \
  -H "Authorization: Bearer key_customer1_abc123" \
  -d '{"text": "Hello world from my paid API"}'
# → {"text":"Hello world from my paid API","word_count":6,"char_count":27}

# Test without key
curl http://10.200.1.2:8080/api/v1/analyze
# → {"error":"invalid API key"}
```

## Step 4: Expose to Internet (2 minutes)

In Cloudflare Zero Trust dashboard:
1. Networks → Tunnels → your tunnel → Public Hostname
2. Add: `api.yourdomain.com → http://10.200.1.2:8080`

Test:
```bash
curl https://api.yourdomain.com/health
# → {"status":"ok"}

curl -X POST https://api.yourdomain.com/api/v1/analyze \
  -H "Authorization: Bearer key_customer1_abc123" \
  -d '{"text": "Live on the internet"}'
# → {"text":"Live on the internet","word_count":4,"char_count":20}
```

## Step 5: Auto-Start on Boot (1 minute)

```bash
sudo envpod service register my-api
```

Done. Survives reboots, restarts on crash, health-checked.

## What You Get

```
✓ API running at https://api.yourdomain.com
✓ API key authentication (keys in encrypted vault)
✓ Health check every 30 seconds (auto-restart on failure)
✓ Auto-start on boot (systemd service)
✓ TLS + DDoS protection (Cloudflare)
✓ Only port 8080 exposed (firewall)
✓ DNS allowlist (pod can only reach PyPI, nothing else)
✓ Full audit trail (every request logged)
✓ COW filesystem (rollback any changes)
✓ seccomp-BPF syscall filtering
✓ Namespace isolation (PID, network, mount)
```

Total time: ~10 minutes. No Docker. No Kubernetes. No cloud platform.

## Managing Customers

### Add a new API key

```bash
# Read current keys, add new one, update vault
CURRENT=$(sudo envpod vault my-api get API_KEYS)
echo -n "${CURRENT},key_newcustomer_xyz789" | sudo envpod vault my-api set API_KEYS

# Restart to pick up new key
sudo envpod service restart my-api
```

### Remove a customer

```bash
# Read current, remove key, update vault
# Then restart
sudo envpod service restart my-api
```

### Check audit trail

```bash
# See all API activity
sudo envpod audit my-api

# JSON for analysis
sudo envpod audit my-api --json
```

### Rollback a bad deploy

```bash
# See what changed
sudo envpod diff my-api

# Undo everything
sudo envpod rollback my-api

# Restart
sudo envpod service restart my-api
```

## Scaling Up

### More workers

```yaml
# In pod.yaml:
processor:
  cores: 4.0
  memory: "2GB"

start_command: ["bash", "-c", "cd /opt/my-api && gunicorn -b 0.0.0.0:8080 -w 8 server:app"]
```

### Database

```yaml
vault:
  env:
    - API_KEYS
    - DATABASE_URL    # postgres://user:pass@db.example.com/mydb
```

### Rate limiting

Add to your Flask app, or upgrade to Premium for L7 OPA rate limiting:

```yaml
# Premium: per-path, per-key rate limiting via OPA
policy:
  enabled: true
  # l7.rego: limit /api/v1/analyze to 100 req/min per key
```

### Multiple services

Upgrade to Premium for multi-check health monitoring:

```yaml
# Premium: API + worker + cache, each health-checked independently
health:
  checks:
    - name: api
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

This same pattern works for any service:

```bash
mkdir /opt/my-service
# Add: server code + pod.yaml
cd /opt/my-service
sudo envpod init my-service -c pod.yaml
echo -n "secret" | sudo envpod vault my-service set MY_SECRET
sudo envpod start my-service
sudo envpod service register my-service
# CF tunnel: my-service.example.com → pod IP
```

Webhook receivers, chatbots, ML model APIs, license servers, file processors, cron jobs — all the same pattern. One folder, one yaml, one command.
