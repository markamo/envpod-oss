# OWASP Agentic Security Coverage

envpod covers all 10 OWASP Agentic Security Initiative (ASI) risks at the **kernel level** — not application middleware, not in-process hooks, but Linux namespace, cgroup, and seccomp enforcement that agents cannot bypass.

## Coverage Summary

| OWASP ASI Risk | Status | envpod Enforcement |
|---|---|---|
| ASI-01 Goal Hijacking | Covered | Prompt screening + action queue approval |
| ASI-02 Excessive Capabilities | Covered | Action catalog + tier system + capability model |
| ASI-03 Identity Abuse | Covered | Pod isolation (own namespace) + agent identity |
| ASI-04 Code Execution | Covered | seccomp-BPF + PID namespace + NO_NEW_PRIVS |
| ASI-05 Output Handling | Covered | COW filesystem + diff/commit human review |
| ASI-06 Memory Poisoning | Covered | Memory namespace + /proc masking + coredump prevention |
| ASI-07 Inter-Agent Comms | Covered | Bilateral pod discovery + DNS filtering |
| ASI-08 Cascading Failures | Covered | cgroups v2 limits + budget enforcement + pod isolation |
| ASI-09 Trust Deficit | Covered | Append-only audit trail + human approval gates |
| ASI-10 Rogue Agents | Covered | Kill switch + freeze + monitoring agent + sealed mode |

## Why Kernel-Level Matters

Application-level governance (Python middleware, in-process hooks) runs in the same process as the agent. A sufficiently capable agent could:
- Modify the governance code in memory
- Bypass policy checks via reflection or monkey-patching
- Kill the governance thread
- Access raw system calls directly

Kernel-level governance runs outside the agent's process, enforced by Linux itself:
- **Namespaces** — agent cannot see or reach host processes, network, or filesystem
- **cgroups** — agent cannot consume more CPU/memory/PIDs than allocated
- **seccomp-BPF** — agent cannot make unauthorized system calls
- **OverlayFS** — agent cannot write to the real filesystem

The agent cannot bypass these because they are enforced by the kernel, not by code running alongside the agent.

## Detailed Coverage

### ASI-01: Goal Hijacking

**Risk:** Agent's goals are manipulated through prompt injection, instruction override, or context poisoning.

**envpod enforcement:**
- **Prompt screening** — scans prompts for injection patterns, credential exposure, PII, and exfiltration attempts before they reach the agent. Supports Anthropic, OpenAI, Gemini, and Ollama API formats.
- **Action queue** — every agent action is classified by reversibility. Dangerous actions require human approval before execution. The agent cannot skip the approval gate.
- **COW filesystem** — even if the agent's goal is hijacked, all file changes go to an overlay. Nothing reaches the host until a human reviews and commits.

```bash
envpod screen my-agent           # scan prompts for injection
envpod queue my-agent ls         # view pending actions
envpod approve my-agent <id>     # human approves
```

### ASI-02: Excessive Capabilities

**Risk:** Agent has access to tools, APIs, or system resources beyond what its task requires.

**envpod enforcement:**
- **Action catalog** — 20 built-in action types (HTTP, filesystem, git). The host defines exactly which actions are available. The agent cannot call tools not in the catalog.
- **Four approval tiers** — Immediate (safe), Delayed (grace period), Staged (human approval), Blocked (denied). Each action type has a default tier.
- **Capability model** — agents inherit named capabilities. Policy checks capabilities before allowing actions.
- **DNS allowlist** — agent can only reach approved domains. Everything else returns NXDOMAIN.

```yaml
# pod.yaml — agent can only reach these domains
network:
  dns:
    mode: Allowlist
    allow:
      - api.anthropic.com
      - github.com
```

### ASI-03: Identity Abuse

**Risk:** Agent impersonates another agent or escalates its identity to gain unauthorized access.

**envpod enforcement:**
- **Pod isolation** — each agent runs in its own Linux namespace. Separate PID space, network stack, filesystem view. One agent cannot see or interact with another's processes.
- **Agent identity** (Premium) — Ed25519 keypairs per pod, JWT tokens per agent. Cryptographically verified identity on every action.
- **OIDC integration** (Premium) — human identity from external SSO providers, fed into policy decisions.

```bash
# Each pod is fully isolated — cannot impersonate another
envpod run agent-a -- bash    # PID namespace A, network A, filesystem A
envpod run agent-b -- bash    # PID namespace B, network B, filesystem B
# agent-a cannot see agent-b's processes, network, or files
```

### ASI-04: Code Execution

**Risk:** Agent executes arbitrary code that escapes the sandbox or accesses unauthorized system resources.

**envpod enforcement:**
- **seccomp-BPF** — syscall filtering. Only approved system calls are allowed. Dangerous calls (ptrace, mount, reboot, etc.) are blocked at the kernel level.
- **PID namespace** — agent sees only its own processes. Cannot signal, trace, or inspect host processes.
- **NO_NEW_PRIVS** — kernel flag prevents the agent from gaining additional privileges through setuid binaries or capability escalation.
- **User namespace** — UID/GID mapping. Agent may appear to run as root inside the pod but has no real root privileges on the host.
- **/proc masking** — sensitive /proc entries are hidden. Agent cannot fingerprint host hardware, read kernel parameters, or discover other processes.

```bash
# Agent tries to escape — blocked at every level
$ mount /dev/sda1 /mnt        # seccomp blocks mount syscall
$ kill -9 1                    # PID namespace — PID 1 is the pod's init, not the host's
$ sudo su                      # NO_NEW_PRIVS — sudo cannot escalate
$ cat /proc/cpuinfo            # masked — agent sees limited info
```

### ASI-05: Output Handling

**Risk:** Agent writes malicious files, exfiltrates data through filesystem, or produces outputs that compromise the host.

**envpod enforcement:**
- **OverlayFS COW** — every file the agent writes goes to a private overlay. The host filesystem is never modified directly. A human must explicitly review and approve changes.
- **diff/commit/rollback** — review every file change before accepting. One command to undo everything.
- **Filesystem tracking** — configurable watch/ignore lists. Know exactly which directories are being modified.

```bash
envpod diff my-agent              # see every file the agent changed
envpod commit my-agent            # approve and apply to host
envpod rollback my-agent          # discard everything
envpod commit my-agent /safe/dir  # commit only specific paths
```

### ASI-06: Memory Poisoning

**Risk:** Agent accesses or modifies another agent's memory, context, or stored state.

**envpod enforcement:**
- **Memory namespace** — each pod has its own memory space enforced by Linux namespaces. One pod cannot read or write another pod's memory.
- **cgroups v2 memory limits** — memory.max enforced at kernel level. Agent cannot consume all host memory.
- **/proc masking** — agent cannot read /proc/*/maps, /proc/kcore, or other memory-revealing files.
- **Coredump prevention** — agent cannot dump its own or other processes' memory to disk.
- **/dev/shm isolation** — pod-private shared memory tmpfs. No shared memory leakage between pods.

### ASI-07: Inter-Agent Communication

**Risk:** Agents communicate through unauthorized channels, share data they shouldn't, or one agent controls another.

**envpod enforcement:**
- **Network namespace** — each pod has its own network stack. Pods cannot reach each other unless explicitly configured.
- **Bilateral pod discovery** — both sides must opt in. Pod A must list Pod B in `allow_pods` AND Pod B must list Pod A. Either side missing = no communication.
- **DNS filtering** — per-pod DNS resolver. Only approved domains resolve. Covert DNS tunneling detected and blocked.
- **L7 pod-to-pod governance** (Premium) — OPA/Rego policies on HTTP method, path, port, and agent capabilities for every inter-pod request.

```yaml
# Pod A can discover Pod B only if BOTH sides agree
# Pod A config:
network:
  allow_pods: [pod-b]

# Pod B config:
network:
  allow_discovery: true
  allow_pods: [pod-a]
```

### ASI-08: Cascading Failures

**Risk:** One agent's failure causes a chain reaction that brings down other agents or the host system.

**envpod enforcement:**
- **cgroups v2** — CPU, memory, and PID limits per pod. One agent consuming all resources cannot starve others. Enforced at kernel level.
- **Budget enforcement** — `max_duration` auto-kills pods after a time limit. Runaway agents are terminated.
- **Pod isolation** — complete namespace separation. A crashing pod cannot affect any other pod or the host.
- **Monitoring agent** — runtime behavior monitoring with configurable thresholds. Auto-freeze on anomaly.

```yaml
processor:
  cores: 2.0           # max 2 CPU cores
  memory: "4GB"        # max 4GB RAM
  max_pids: 256        # max 256 processes

budget:
  max_duration: "1h"   # auto-kill after 1 hour
```

### ASI-09: Trust Deficit

**Risk:** No way to verify what an agent did, whether it followed instructions, or whether its outputs are trustworthy.

**envpod enforcement:**
- **Append-only audit log** — every action timestamped in JSONL format. Create, start, stop, diff, commit, DNS queries, vault access, policy evaluations — all logged.
- **Human approval gates** — staged actions require explicit human approval. Every approval and denial is logged.
- **Security scan** — `envpod audit --security` performs static analysis of pod configuration.
- **OpenTelemetry export** (Premium) — audit data exported to Grafana, Datadog, Splunk, or any OTLP backend.

```bash
envpod audit my-agent              # view full action history
envpod audit my-agent --security   # static security analysis
envpod audit my-agent --json       # machine-readable for integration
```

### ASI-10: Rogue Agents

**Risk:** Agent behaves contrary to its intended purpose — data exfiltration, resource abuse, unauthorized actions.

**envpod enforcement:**
- **Kill switch** — `envpod kill` terminates the agent immediately. OS-level SIGKILL — cannot be caught or ignored.
- **Freeze** — `envpod freeze` halts the agent via cgroup freezer. Process state preserved for forensic analysis. Resume with `envpod resume`.
- **Monitoring agent** — background policy engine monitors behavior. Auto-freeze on threshold violations.
- **Remote control** — freeze, resume, kill, restrict resources on running pods. No restart required.
- **Sealed mode** (Premium) — zero host visibility. Agent cannot see the host filesystem, network, or any information outside its pod.
- **Network restriction** — `envpod remote restrict` cuts network access mid-flight.

```bash
envpod freeze my-agent            # halt immediately, preserve state
envpod kill my-agent              # terminate, rollback changes
envpod remote my-agent restrict   # cut network access
envpod resume my-agent            # continue after investigation
```

## Architecture: Defense in Depth

```
┌─────────────────────────────────────────────┐
│              Governance Ceiling              │
│  Audit · Queue · Screening · Monitoring     │
├─────────────────────────────────────────────┤
│   Wall 1      Wall 2      Wall 3    Wall 4  │
│  Processor   Network    Memory    Devices   │
│  PID ns      Net ns     Mem ns    /dev mask │
│  cgroups     DNS filt   /proc     GPU gate  │
│  seccomp     Allowlist  Coredump  Audio     │
│  NO_NEW_PRIV Rate limit /dev/shm  Display   │
├─────────────────────────────────────────────┤
│              Foundation                      │
│         OverlayFS Copy-on-Write             │
│     diff · commit · rollback · snapshots    │
└─────────────────────────────────────────────┘
```

Every OWASP risk is addressed by multiple layers. Compromising one layer does not defeat the others.

## Comparison: Application vs Kernel Governance

| | Application-level | Kernel-level (envpod) |
|---|---|---|
| Enforcement | In-process middleware | Linux kernel (namespaces, cgroups, seccomp) |
| Bypassable | Yes — agent runs in same process | No — enforced outside agent's control |
| Kill switch | Signal handler (catchable) | SIGKILL (uncatchable) + cgroup freeze |
| Network isolation | None — shares host network | Network namespace — separate stack |
| Filesystem isolation | None — shares host filesystem | OverlayFS — separate view |
| Memory isolation | None — shares address space | Namespace — separate memory |
| Performance overhead | In-process — minimal | Namespace — near-zero |
