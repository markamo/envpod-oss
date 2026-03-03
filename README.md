# envpod — Zero-trust governance environments for AI agents

> "Docker isolates. Envpod governs."

## What is envpod?

envpod is a governance layer for AI agents running on Linux. It gives every agent a **pod** — an isolated environment with four hard walls (memory, filesystem, network, processor) and a governance ceiling that records, reviews, and controls everything the agent does.

The core insight: container runtimes give you isolation, but isolation alone is not enough for autonomous agents. You need to know what the agent changed, review it before it lands, roll it back if wrong, and keep secrets out of the agent's context. envpod builds this governance layer on top of Linux namespaces, OverlayFS, and cgroups — as a single static binary with no runtime dependencies.

Every agent session runs inside a pod. Filesystem writes go to a copy-on-write overlay — the host is never touched until a human runs `envpod commit`. DNS is filtered so the agent can only reach approved domains. Credentials are stored in an encrypted vault and injected as environment variables at runtime — the agent never sees them in its context. All actions are logged to an append-only audit trail. The human reviews with `envpod diff`, commits good changes, rolls back bad ones.

## The Pod Model

**Four walls:**
- **Filesystem wall** — OverlayFS copy-on-write. Agent writes go to an overlay; the host filesystem is unchanged until `envpod commit`.
- **Network wall** — Network namespace + embedded per-pod DNS resolver. Domain-level allow/deny, rate limiting, DNS remapping.
- **Memory wall** — Namespace separation, /proc blocking, coredump prevention. Cognitive isolation via per-pod context.
- **Processor wall** — CPU affinity, cgroup v2 enforcement. CPU, memory, and PID limits.

**Governance ceiling:**
- Action staging queue (immediate / delayed / staged / blocked tiers)
- Encrypted credential vault (ChaCha20-Poly1305)
- Remote lockdown (freeze / kill / restrict)
- Multi-layer audit log (action + system)
- Web dashboard for fleet oversight

## Quick Start

```bash
# Install (Linux x86_64 or ARM64 — auto-detects arch)
curl -fsSL https://envpod.dev/install.sh -o /tmp/envpod-install.sh
sudo bash /tmp/envpod-install.sh

# Create a pod from a config file
sudo envpod init my-agent --config pod.yaml

# Run a command inside the pod
sudo envpod run my-agent -- bash

# Review what the agent changed
sudo envpod diff my-agent

# Commit approved changes to the host filesystem
sudo envpod commit my-agent

# Roll back all changes
sudo envpod rollback my-agent
```

Minimal `pod.yaml`:

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

## Feature Highlights

**Filesystem governance**
- OverlayFS copy-on-write: all agent writes go to overlay, host untouched
- `envpod diff` — review changes before they land
- `envpod commit` — apply selected changes (or `--output <dir>` to export)
- `envpod rollback` — discard all changes instantly
- Pod snapshots — checkpoint and restore overlay state

**Network governance**
- Per-pod DNS resolver (whitelist / blacklist / monitor / remap modes)
- Anti-tunneling protection
- Port forwarding: localhost-only (`-p`), public (`-P`), pod-to-pod (`-i`)
- Pod discovery via `<name>.pods.local` (requires `envpod dns-daemon`)

**Credential vault**
- ChaCha20-Poly1305 encrypted, per-pod vault
- `envpod vault set/get/list/rm/import` — manage secrets
- Secrets injected as environment variables at runtime
- Never stored in agent context or pod.yaml

**Action queue (20 built-in types)**
- HTTP: `http_get`, `http_post`, `http_put`, `http_patch`, `http_delete`, `webhook`
- Filesystem: `file_create`, `file_write`, `file_delete`, `file_copy`, `file_move`, `dir_create`, `dir_delete`
- Git: `git_commit`, `git_push`, `git_pull`, `git_checkout`, `git_branch`, `git_tag`
- Custom: `custom` (define your own schema)
- Reversibility tiers: ImmediateProtected / Delayed (30s grace) / Staged (human approval) / Blocked

**Web dashboard**
- `envpod dashboard` — starts on localhost:9090
- Fleet overview with live polling
- Pod detail: audit log, diff, resource usage
- Action buttons: commit, rollback, freeze, resume

**Base pods and cloning**
- Base pods: reusable rootfs snapshots for fast cloning
- `envpod clone source new-name` — clone in ~130ms vs ~1.3s for full init
- `envpod base create/ls/destroy` — manage base pods

**Display and audio passthrough**
- Wayland / X11 display forwarding
- PipeWire / PulseAudio audio forwarding
- GPU passthrough (NVIDIA + DRI)

**ARM64 support**
- Static musl binary for Raspberry Pi 4/5 and Jetson Orin
- See `docs/EMBEDDED.md` for setup instructions

## Documentation

- `docs/FEATURES.md` — full feature list (OSS vs Premium)
- `docs/CLI-BLACKBOOK.md` — complete CLI reference
- `docs/TUTORIALS.md` — step-by-step tutorials
- `docs/ACTION-CATALOG.md` — action type reference
- `docs/FOR-DOCKER-USERS.md` — envpod for Docker users
- `docs/EMBEDDED.md` — ARM64 / embedded deployment

## Building from Source

Requires Rust toolchain (rustup).

```bash
git clone https://github.com/markamo/envpod-oss
cd envpod-oss
cargo build --release
```

The binary is at `target/release/envpod`.

## License

[Business Source License 1.1](LICENSE) — free to use (including production),
source-available. Cannot be resold as a competing product.
Converts to Apache-2.0 on 2030-01-01.

Copyright 2026 Xtellix Inc.

---

Premium features (vault proxy injection, AI monitoring agent, messaging/database actions) available at [envpod.com](https://envpod.com)
