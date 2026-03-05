[![Release](https://img.shields.io/badge/release-v0.1.0-brightgreen)](https://github.com/markamo/envpod-ce/releases/tag/v0.1.0)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64%20%7C%20ARM64-lightgrey)](docs/EMBEDDED.md)
[![Built with Rust](https://img.shields.io/badge/built%20with-Rust-orange)](https://www.rust-lang.org/)

# envpod — Zero-trust governance environments for AI agents

> "Docker isolates. Envpod governs."

## What is envpod?

envpod is a governance layer for AI agents running on Linux. It gives every agent a **pod** — an isolated environment with four hard walls (memory, filesystem, network, processor) and a governance ceiling that records, reviews, and controls everything the agent does.

> **Why not just Docker?** Docker isolates processes but provides zero governance. No file change review, no action queue, no credential vault, no undo. Envpod adds the governance layer on top of the same Linux primitives. See [Docker vs Envpod](docs/FOR-DOCKER-USERS.md) for a full comparison.

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
curl -fsSL https://envpod.dev/install.sh | sh

# Or install from a release tarball
curl -fsSL https://github.com/markamo/envpod-ce/releases/latest/download/envpod-linux-x86_64.tar.gz \
  | tar xz && sudo ./envpod-linux-x86_64/install.sh

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

## Benchmarks

Ubuntu 24.04, Docker 29.2.1, Podman 4.9.3, NVIDIA TITAN RTX x2, 10 iterations averaged.

**Startup latency:**

| Test | Docker | Podman | Envpod | vs Docker | vs Podman |
|------|--------|--------|--------|-----------|-----------|
| fresh: run /bin/true | 552ms | 560ms | **401ms** | **151ms faster** | **159ms faster** |
| warm: run /bin/true | 95ms | 270ms | **32ms** | **63ms faster** | **238ms faster** |
| fresh: GPU nvidia-smi | 755ms | 745ms | **447ms** | **308ms faster** | **298ms faster** |

**Scale-out (50 instances):**

| Phase | Docker | Podman | Envpod | vs Docker | vs Podman |
|-------|--------|--------|--------|-----------|-----------|
| Create 50 | 6.3s | 6.9s | **407ms** | **15x faster** | **17x faster** |
| Run all 50 | 11.4s | 26.8s | **7.5s** | **1.5x faster** | **3.6x faster** |
| Full lifecycle | 19.0s | 36.2s | **9.5s** | **2x faster** | **3.8x faster** |

**Resource overhead:**

| Runtime | Base image (Ubuntu 24.04) | GPU image (CUDA 12.0) | Per-instance |
|---------|--------------------------|----------------------|-------------|
| Docker | 119 MB | 338 MB | 4 KB |
| Podman | 77 MB | 229 MB | 11 KB |
| Envpod | **105 MB** | **105 MB** | **1 KB** |

Envpod GPU base is **69% smaller** than Docker's — CUDA libraries are bind-mounted from the host, not copied. Clone is ~10x faster than init (rootfs symlinked).

**Real-world DNS + API (what agents actually do):**

| Test | Docker | Podman | Envpod | vs Docker | vs Podman |
|------|--------|--------|--------|-----------|-----------|
| fresh: nslookup google.com | 673ms | 784ms | **257ms** | **416ms faster** | **527ms faster** |
| warm: nslookup google.com | 129ms | 319ms | **62ms** | **67ms faster** | **257ms faster** |
| fresh: curl GET google.com | 825ms | 874ms | **382ms** | **443ms faster** | **492ms faster** |
| warm: curl GET google.com | 254ms | 422ms | **191ms** | **63ms faster** | **231ms faster** |
| fresh: curl POST httpbin.org | 1.07s | 974ms | **508ms** | **559ms faster** | **466ms faster** |

Envpod resolves DNS through a whitelist filter, logs every query, and still finishes before Docker returns. Docker/Podman pass DNS through unfiltered — no governance.

Raw results from our test machine are in [`results/`](results/) for independent verification.

<details>
<summary><strong>Reproduce these benchmarks</strong></summary>

```bash
# Create results directory
mkdir -p results

# Head-to-head: Docker vs Podman vs envpod (startup latency)
sudo ./tests/benchmark-podman.sh 10 2>&1 | tee results/benchmark-podman.txt

# Scale-out: create + run + destroy 50 instances
sudo ./tests/benchmark-scale.sh 50 2>&1 | tee results/benchmark-scale.txt

# Disk footprint comparison
sudo ./tests/benchmark-size.sh 2>&1 | tee results/benchmark-size.txt

# GPU passthrough overhead (requires NVIDIA GPU)
sudo ./tests/benchmark-gpu.sh 10 2>&1 | tee results/benchmark-gpu.txt

# Core envpod benchmarks (init, run, diff, rollback, lifecycle)
sudo ./tests/benchmark.sh 50 2>&1 | tee results/benchmark-core.txt

# Clone vs init
sudo ./tests/benchmark-clone.sh 10 2>&1 | tee results/benchmark-clone.txt

# Real-world DNS + HTTPS + API POST
sudo ./tests/benchmark-dns.sh 10 2>&1 | tee results/benchmark-dns.txt
```

Requires: Docker, Podman, envpod installed. NVIDIA GPU for GPU benchmarks. All scripts auto-clean up after themselves.
</details>

## Tested Distros

Tested via automated suite — install, run, governance (diff/commit/rollback) all pass on every distro:

| Distro | Version | Package Manager | Status |
|--------|---------|-----------------|--------|
| Ubuntu | 24.04 LTS | apt | **Pass** |
| Ubuntu | 22.04 LTS | apt | **Pass** |
| Debian | 12 | apt | **Pass** |
| Fedora | 41 | dnf | **Pass** |
| Arch Linux | latest | pacman | **Pass** |
| Rocky Linux | 9 | dnf | **Pass** |
| AlmaLinux | 9 | dnf | **Pass** |
| openSUSE Leap | 15.6 | zypper | **Pass** |
| Amazon Linux | 2023 | dnf | **Pass** |

The installer auto-detects your distro and package manager. Prerequisites (iptables, iproute2) are installed automatically if missing.

<details>
<summary><strong>Reproduce distro tests</strong></summary>

```bash
# Test with host-mounted binary (fast — binary already built)
sudo bash tests/test-distros.sh 2>&1 | tee results/test-distros.txt

# Test full in-container install + governance (comprehensive)
sudo bash tests/test-distros-v2.sh 2>&1 | tee results/test-distros-v2.txt
```

</details>

## Try in Docker

Don't want to install on bare metal? Test envpod inside Docker:

```bash
docker build -t envpod-demo -f docker/Dockerfile docker/
docker run -it --privileged --cgroupns=host \
  -v /tmp/envpod-test:/var/lib/envpod \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  envpod-demo

# Inside the container:
envpod init test -c /opt/envpod/examples/basic-internet.yaml
envpod run test -- bash
```

See [docs/DOCKER-TESTING.md](docs/DOCKER-TESTING.md) for the full guide.

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

- `docs/INSTALL.md` — installation guide (9 distros, bare metal + container)
- `docs/DOCKER-TESTING.md` — Docker evaluation guide
- `docs/FEATURES.md` — full feature list (CE vs Premium)
- `docs/CLI-BLACKBOOK.md` — complete CLI reference
- `docs/TUTORIALS.md` — step-by-step tutorials
- `docs/ACTION-CATALOG.md` — action type reference
- `docs/FOR-DOCKER-USERS.md` — envpod for Docker users
- `docs/EMBEDDED.md` — ARM64 / embedded deployment
- `docs/LICENSING.md` — AGPL rationale and commercial licensing
- `CHANGELOG.md` — release history
- `CONTRIBUTING.md` — how to contribute
- `SECURITY.md` — vulnerability reporting

## Building from Source

Requires Rust toolchain (rustup).

```bash
git clone https://github.com/markamo/envpod-ce
cd envpod-ce
cargo build --release
```

The binary is at `target/release/envpod`.

## License

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

Copyright 2026 Xtellix Inc. Licensed under [AGPL-3.0-only](LICENSE) — free to use, modify, and distribute. Cloud providers offering envpod as a service must open-source their stack under AGPL-3.0.

See [docs/LICENSING.md](docs/LICENSING.md) for full details. For commercial licensing, contact mark@envpod.dev.

---

Premium features (AI monitoring agent, prompt screening, TLS inspection, messaging/database actions) available at [envpod.dev](https://envpod.dev)
