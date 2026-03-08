# Roadmap

> **EnvPod v0.1.0** — Zero-trust governance environments for AI agents
> Author: Mark Amoboateng · mark@envpod.dev
> Copyright 2026 Xtellix Inc. · Licensed under AGPL-3.0

---

What's shipped, what's next, and where we're headed. Target: public launch August 2026.

## v0.1.0 — Shipped (March 2026)

Core isolation + governance MVP. Single binary, native Linux backend.

### Isolation (Four Walls)
- [x] PID, mount, network, UTS, user namespaces
- [x] cgroups v2 (CPU, memory, PID limits, CPU affinity)
- [x] seccomp-BPF syscall filtering (default + browser profiles)
- [x] OverlayFS copy-on-write filesystem
- [x] Per-pod network namespace with veth pairs
- [x] Per-pod embedded DNS resolver (whitelist/blacklist/monitor)
- [x] System access levels (safe/advanced/dangerous)

### Governance (Ceiling)
- [x] Diff / commit / rollback with selective commit
- [x] Credential vault (ChaCha20-Poly1305 encrypted, env var injection)
- [x] Action staging queue (approve / cancel)
- [x] Undo registry (reverse any reversible action)
- [x] Append-only audit trail (JSONL)
- [x] Static security analysis (`envpod audit --security`)
- [x] Live DNS mutation (add/remove domains without restart)
- [x] Remote control (freeze / resume / kill / restrict)
- [x] Monitoring agent (policy-driven auto-freeze/restrict)

### Devices & Media
- [x] NVIDIA GPU passthrough (zero-copy bind-mount)
- [x] Display forwarding (Wayland / X11 / auto-detect)
- [x] Audio forwarding (PipeWire / PulseAudio / auto-detect)
- [x] Custom device passthrough (/dev/fuse, /dev/kvm, etc.)

### Operations
- [x] Pod cloning (~130ms vs ~1.3s init)
- [x] Base pod management (create / ls / destroy)
- [x] Garbage collection (`envpod gc` — iptables, netns, cgroups, pod dirs)
- [x] Fast destroy + full destroy (`--full`)
- [x] Shell completions (bash, zsh, fish)
- [x] 20 example pod configs for popular AI agents
- [x] Jailbreak test suite (49 tests)

### Performance
- [x] 15x faster than Docker at pod creation
- [x] 2x faster full lifecycle (create + run + destroy)
- [x] 23ms warm run, 130ms clone
- [x] Zero-overhead GPU passthrough

---

## v0.2 — In Progress (Q2-Q3 2026)

Vault proxy injection, web dashboard, pod discovery, embedded systems, Docker backend, portable base pods.

### Vault Proxy Injection (Zero-Knowledge Credentials) — Shipped
- [x] Per-pod transparent HTTPS proxy on host-side veth IP:443
- [x] DNS remap API endpoints to local proxy (uses existing remap mechanism)
- [x] Per-pod ephemeral CA (rcgen) with SNI-based leaf cert minting
- [x] Proxy injects `Authorization` headers from vault at transport layer
- [x] Agent never sees raw API keys — not in env, config, or memory
- [x] Audit trail logs credential usage without exposing values
- [x] Vault binding rules: `vault.proxy` + `vault.bindings` in pod.yaml
- [x] CLI: `envpod vault <pod> bind/unbind/bindings`
- [x] Security audit findings: V-01, V-02, V-03

**How it works:** Envpod already runs a per-pod DNS resolver. For vault-bound domains (e.g., `api.anthropic.com`), DNS resolves to the host-side veth IP where a transparent proxy runs. The proxy terminates TLS with a per-pod ephemeral CA cert (installed into the pod's trust store during `envpod init`), injects the real auth header from the encrypted vault, and forwards to the real API via hyper-rustls. The agent makes normal HTTPS requests — they work, but the key never enters the agent's address space.

**Security upgrade:** Current env var injection (v0.1) means a compromised agent can read `$ANTHROPIC_API_KEY` and exfiltrate it. Proxy injection eliminates this — there's nothing to exfiltrate.

### Web Dashboard — Shipped
- [x] `envpod dashboard [--port 9090] [--no-open]` CLI subcommand
- [x] Embedded axum server with static assets compiled into binary (rust-embed)
- [x] Fleet overview with 2s htmx polling (pod cards: status, memory, PIDs, diff count)
- [x] Pod detail with tabs: Overview, Audit, Diff, Resources
- [x] Live cgroup resource monitoring (CPU, memory, PIDs) with 2s auto-refresh
- [x] Action buttons: Commit, Rollback, Freeze, Resume (with confirm for destructive ops)
- [x] REST API: GET pods, pods/:id, audit, resources, diff. POST commit, rollback, freeze, resume.

### Pod-to-Pod Discovery — Shipped
- [x] Central `envpod-dns` daemon — single host-wide discovery registry
- [x] Pods register as `<name>.pods.local` (bilateral policy: both sides must opt in)
- [x] Auto-registration of already-running pods on daemon startup
- [x] `envpod discover` — live discovery mutations (enable/disable, add/remove pods)
- [x] Security findings: D-01 (unsafe discoverable), D-02 (wildcard allow_pods)
- [x] Discovery state persisted through daemon restarts
- [x] `systemd` service example for production deployments

### Live Port Mutations — Shipped
- [x] `envpod ports -p <host:container/proto>` — add port forward live
- [x] `envpod ports -P <host:container/proto>` — add public port live
- [x] `envpod ports -i <container/proto>` — add internal port live
- [x] `--remove` / `--remove-internal` — remove rules without restart
- [x] Idempotent: duplicate detection prevents iptables rule accumulation
- [x] State persisted to `port_forwards_active.json` / `internal_ports_active.json`

### Embedded Systems (ARM64) — Shipped
- [x] Static `aarch64-unknown-linux-musl` binary — no runtime dependencies
- [x] Raspberry Pi 4 / Pi 5 support (Raspberry Pi OS 64-bit, Ubuntu 24.04)
- [x] NVIDIA Jetson Orin support (JetPack 6, GPU + DLA passthrough)
- [x] `build-release.sh --arch arm64` / `--all` for multi-arch builds
- [x] `docs/EMBEDDED.md` — cgroups v2 setup, GPU passthrough, resource limits, llama.cpp
- [x] `examples/jetson-orin.yaml` + `examples/raspberry-pi.yaml`
- [x] Cross-compilation via `cross` (Docker), `cargo-zigbuild`, or native toolchain

### Docker Backend
- [ ] `backend: docker` in pod.yaml
- [ ] Run pods inside Docker containers instead of native namespaces
- [ ] Same governance layer (diff/commit/rollback, vault, audit)
- [ ] For environments where Docker is already deployed

### Portable Base Pods (Premium)
- [ ] `envpod base export <name> -o base.tar.gz`
- [ ] `envpod base import base.tar.gz`
- [ ] Package and transfer base pods between machines
- [ ] Enables shipping pre-configured agent environments

### Custom Rootfs Sources
- [ ] `envpod base create --from debootstrap:bookworm`
- [ ] `envpod base create --from alpine:3.19`
- [ ] `envpod base create --from oci:ubuntu:24.04`
- [ ] Run different Linux distros on the same host kernel

### Pod Encryption
- [ ] Encrypt pod data at rest (overlay, vault, audit logs)
- [ ] Key management integration

### Phased Init UX
- [ ] Restructure `envpod init` into phases with progress reporting
- [ ] Clean rollback on setup failure (no half-built pods)

### Improved Vault CLI
- [ ] `envpod vault <pod> ls` — list keys without values
- [ ] `envpod vault <pod> import .env` — bulk import from .env files
- [ ] `envpod vault <pod> export --encrypted` — export encrypted vault

---

## v0.3 — Future (Q4 2026+)

VM backend, cloud relay, multi-machine fleet management.

### VM Backend
- [ ] `backend: vm` in pod.yaml
- [ ] Firecracker microVMs for hardware-level isolation
- [ ] QEMU fallback for broader compatibility
- [ ] Same governance layer across all backends

### Cloud Relay
- [ ] Remote control plane for managing pods across machines
- [ ] `envpod relay connect <server>` — connect to relay
- [ ] Dashboard for fleet-wide visibility
- [ ] Centralized policy distribution

### Web Dashboard (Enhancements)
- [ ] Multi-machine fleet view (via cloud relay)
- [ ] Visual diff viewer (side-by-side, syntax highlighting, inline +/- per file)
- [ ] Dashboard authentication
- [ ] WebSocket live updates (replace polling)

### Advanced Diff / Commit (Premium)
- [ ] Inline git-style diff view per file (unified diff, syntax highlighted)
- [ ] Side-by-side file comparison in dashboard
- [ ] Per-hunk staging (accept/reject individual file sections)
- [ ] Diff history (compare any two pod states)
- [ ] Commit with message + author metadata
- [ ] Branch-like saved states (named snapshots)

### Advanced Governance
- [ ] FEBO policy engine (full policy language)
- [ ] Tool security layer (pre/during/post execution validation)
- [ ] Prompt & instruction screening
- [ ] Inter-pod communication (common rooms, data rooms)
- [ ] Building-level management (fleet-wide lockdown, policy cascade)

### Nested Compositor
- [ ] Weston/Cage inside pod for isolated display
- [ ] XWayland support
- [ ] PipeWire portal permissions

---

## Release Timeline

| Version | Target | Theme |
|---------|--------|-------|
| v0.1.0 | March 2026 | Core isolation + governance MVP |
| v0.1.x | April-May 2026 | Bug fixes, testing, hardening |
| v0.2.0 | June-July 2026 | Vault proxy, Docker backend, portable bases |
| **HN Launch** | **August 2026** | **Public release** |
| v0.3.0 | Q4 2026 | VM backend, cloud relay, advanced dashboard |

---

Copyright 2026 Xtellix Inc. All rights reserved. Licensed under the Apache License, Version 2.0.
