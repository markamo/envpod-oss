# Quickstart

> Copyright 2026 Mark Amo-Boateng / Xtellix Inc. · GNU Affero General Public License v3.0

Get a governed AI agent pod running in under 60 seconds.

---

## Prerequisites

envpod installed. If not, run:
```bash
curl -fsSL https://envpod.dev/install.sh | sh
```

---

## Step 1 — Create a pod

```bash
sudo envpod init my-agent
```

Creates a pod named `my-agent` with default settings (Isolated network, 2 CPU cores, 2 GB memory).

To create from a config file:
```bash
sudo envpod init my-agent --config pod.yaml
```

---

## Step 2 — Run a command inside the pod

```bash
sudo envpod run my-agent -- bash
```

You are now inside the governed environment. Anything you do here is sandboxed — filesystem writes go to an overlay, not your real system.

Run a quick test:
```bash
# Inside the pod:
echo "hello from agent" > /home/agent/test.txt
ls /home/agent/
exit
```

---

## Step 3 — Review what changed

```bash
sudo envpod diff my-agent
```

Shows every file the agent created, modified, or deleted — nothing has touched the real filesystem yet.

---

## Step 4 — Commit or roll back

Apply the changes to your real filesystem:
```bash
sudo envpod commit my-agent
```

Or discard everything (host unchanged):
```bash
sudo envpod rollback my-agent
```

---

## Minimal pod.yaml

Create a file named `pod.yaml`:

```yaml
name: my-agent
network:
  mode: Isolated
  dns:
    mode: Whitelist
    allow:
      - api.anthropic.com
processor:
  cores: 2.0
  memory: "4GB"
```

Then:
```bash
sudo envpod init my-agent --config pod.yaml
sudo envpod run my-agent -- bash
```

---

## Useful commands

```bash
sudo envpod ls                        # list all pods
sudo envpod diff my-agent             # review changes
sudo envpod commit my-agent           # apply changes to host
sudo envpod rollback my-agent         # discard changes
sudo envpod audit my-agent            # view action audit log
sudo envpod audit my-agent --security # static security scan
sudo envpod vault set my-agent KEY val # store a secret
sudo envpod destroy my-agent          # destroy the pod
```

---

## Next steps

- [Tutorials](TUTORIALS.md) — Browser pod, GPU ML, multi-agent fleet, and more
- [CLI Reference](CLI-BLACKBOOK.md) — every command and flag
- [Features](FEATURES.md) — full feature list
- [Action Catalog](ACTION-CATALOG.md) — governed action types
