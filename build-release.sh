#!/usr/bin/env bash
# Copyright 2026 Mark Amo-Boateng / Xtellix Inc.
# SPDX-License-Identifier: AGPL-3.0-only

#
# build-release.sh — Build envpod and assemble self-contained release folders.
#
# Output:
#   release/envpod-0.1.0-linux-x86_64/    (x86_64 release, default)
#   release/envpod-0.1.0-linux-arm64/     (ARM64: Raspberry Pi / Jetson Orin)
#   envpod-linux-x86_64.tar.gz            (GitHub release asset, no version in filename)
#   envpod-linux-arm64.tar.gz
#
# Usage:
#   ./build-release.sh              # x86_64 only (default)
#   ./build-release.sh --arch arm64 # ARM64 only
#   ./build-release.sh --all        # both architectures
#
# Prerequisites (x86_64):
#   rustup target add x86_64-unknown-linux-musl
#   apt install musl-tools
#
# Prerequisites (arm64) — choose one:
#   Option A (recommended): cargo install cross   [requires Docker]
#   Option B: cargo install cargo-zigbuild && snap install zig --classic --beta
#   Option C: install aarch64-linux-musl-gcc from musl.cc prebuilt toolchain
#
set -euo pipefail

VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
fail()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step()  { echo -e "\n${BOLD}→ $*${NC}"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

BUILD_X86=true
BUILD_ARM64=false

for arg in "$@"; do
    case "$arg" in
        --arch=x86_64|--arch=amd64) BUILD_X86=true;  BUILD_ARM64=false ;;
        --arch=arm64|--arch=aarch64) BUILD_X86=false; BUILD_ARM64=true  ;;
        --arch) : ;;  # handled in pair below
        arm64|aarch64) BUILD_X86=false; BUILD_ARM64=true  ;;
        x86_64|amd64)  BUILD_X86=true;  BUILD_ARM64=false ;;
        --all) BUILD_X86=true; BUILD_ARM64=true ;;
        --help|-h)
            echo "Usage: $0 [--arch x86_64|arm64] [--all]"
            exit 0
            ;;
        *) fail "Unknown argument: $arg" ;;
    esac
done

echo -e "${BOLD}"
echo "  ┌──────────────────────────────────────┐"
echo "  │      envpod release builder v${VERSION}     │"
echo "  └──────────────────────────────────────┘"
echo -e "${NC}"

ARCH_LIST=""
${BUILD_X86}   && ARCH_LIST="${ARCH_LIST} x86_64"
${BUILD_ARM64} && ARCH_LIST="${ARCH_LIST} arm64"
echo "  Architectures:${ARCH_LIST}"
echo ""

# ---------------------------------------------------------------------------
# build_arch <rust_target> <arch_label> <tarball_arch> <build_tool>
#
#   rust_target   e.g. x86_64-unknown-linux-musl
#   arch_label    e.g. x86_64 or arm64  (used in release dir name)
#   build_tool    cargo | cross | zigbuild
# ---------------------------------------------------------------------------

build_arch() {
    local RUST_TARGET="$1"
    local ARCH_LABEL="$2"
    local BUILD_TOOL="$3"

    local RELEASE_NAME="envpod-${VERSION}-linux-${ARCH_LABEL}"
    local RELEASE_DIR="${SCRIPT_DIR}/release/${RELEASE_NAME}"
    # Tarball name matches landing page install URL (no version = always "latest")
    local TARBALL_NAME="envpod-linux-${ARCH_LABEL}.tar.gz"

    # -----------------------------------------------------------------------
    # 1. Build static binary
    # -----------------------------------------------------------------------

    step "Building ${ARCH_LABEL} static binary (${RUST_TARGET})"

    if ! rustup target list --installed | grep -q "${RUST_TARGET}"; then
        echo "  Adding rustup target ${RUST_TARGET}..."
        rustup target add "${RUST_TARGET}"
    fi

    case "${BUILD_TOOL}" in
        cross)
            if ! command -v cross &>/dev/null; then
                fail "'cross' not found. Install with: cargo install cross  (requires Docker)"
            fi
            cross build --release --target "${RUST_TARGET}"
            ;;
        zigbuild)
            if ! command -v cargo-zigbuild &>/dev/null; then
                fail "'cargo-zigbuild' not found. Install with: cargo install cargo-zigbuild"
            fi
            cargo zigbuild --release --target "${RUST_TARGET}.2.17"
            ;;
        cargo)
            cargo build --release --target "${RUST_TARGET}"
            ;;
        *)
            fail "Unknown build tool: ${BUILD_TOOL}"
            ;;
    esac

    local BINARY="${SCRIPT_DIR}/target/${RUST_TARGET}/release/envpod"
    if [[ ! -f "${BINARY}" ]]; then
        fail "Build failed — binary not found at ${BINARY}"
    fi
    info "Binary built: ${BINARY} ($(du -h "${BINARY}" | cut -f1))"

    # -----------------------------------------------------------------------
    # 2. Create release directory
    # -----------------------------------------------------------------------

    step "Assembling release directory for ${ARCH_LABEL}"

    rm -rf "${RELEASE_DIR}"
    mkdir -p "${RELEASE_DIR}/docs" "${RELEASE_DIR}/examples"

    cp "${BINARY}" "${RELEASE_DIR}/envpod"
    chmod 755 "${RELEASE_DIR}/envpod"
    info "Binary copied"

    # -----------------------------------------------------------------------
    # 3. Copy install.sh (universal installer from repo root)
    # -----------------------------------------------------------------------

    cp "${SCRIPT_DIR}/install.sh" "${RELEASE_DIR}/install.sh"
    chmod 755 "${RELEASE_DIR}/install.sh"
    info "install.sh copied (universal installer)"

    # -----------------------------------------------------------------------
    # 4. Generate README.md
    # -----------------------------------------------------------------------

    cat > "${RELEASE_DIR}/README.md" << README_EOF
# envpod v${VERSION}

> **Zero-trust governance environments for AI agents**
> Copyright 2026 Xtellix Inc. · GNU Affero General Public License v3.0

**Docker isolates. Envpod governs.**

Every AI agent runs inside a **pod** — an isolated environment with four hard walls (memory, filesystem, network, processor) and a governance ceiling that records, reviews, and controls everything the agent does.

## What's in This Release

\`\`\`
${RELEASE_NAME}/
├── envpod          Static binary for ${ARCH_LABEL} Linux (no dependencies)
├── install.sh      Installer (copy binary, create dirs, completions, IP forwarding)
├── README.md       This file
├── LICENSE         GNU Affero General Public License v3.0
├── docs/           Documentation
│   ├── INSTALL.md          Installation guide (9 distros)
│   ├── DOCKER-TESTING.md   Docker evaluation guide
│   ├── FEATURES.md         Complete feature reference
│   ├── TUTORIALS.md        Step-by-step tutorials (12 scenarios)
│   ├── ACTION-CATALOG.md   Action type reference
│   ├── CLI-BLACKBOOK.md    Full CLI reference
│   ├── FOR-DOCKER-USERS.md Migration guide from Docker
│   └── EMBEDDED.md         Raspberry Pi / Jetson Orin guide
└── examples/       25 pod configs (YAML) + jailbreak-test.sh
\`\`\`

## Quick Start

\`\`\`bash
# Install
sudo bash install.sh

# Create a pod from an example config
sudo envpod init my-agent -c examples/coding-agent.yaml

# Run a command inside the pod (fully isolated)
sudo envpod run my-agent -- /bin/bash

# See what the agent changed
sudo envpod diff my-agent

# Accept changes (apply to host filesystem)
sudo envpod commit my-agent

# Reject changes (discard everything)
sudo envpod rollback my-agent

# View audit trail
sudo envpod audit my-agent

# Security analysis
sudo envpod audit my-agent --security
\`\`\`

## Core Features

**Filesystem Isolation** — OverlayFS copy-on-write. Agent writes go to an overlay; the host is unchanged until you run \`envpod commit\`. Review with \`envpod diff\`.

**Network Isolation** — Network namespace + embedded per-pod DNS resolver. Whitelist, blacklist, or monitor modes. Every DNS query is logged.

**Process Isolation** — PID namespace, cgroups v2 (CPU, memory, PID limits), seccomp-BPF syscall filtering.

**Credential Vault** — Secrets stored encrypted (ChaCha20-Poly1305). Injected as env vars at runtime; the agent never sees them in config files.

**Pod-to-Pod Discovery** — Pods discover each other by name (\`<name>.pods.local\`) via the central envpod-dns daemon. Bilateral policy control.

**Action Queue** — Actions classified by reversibility: immediate, delayed, staged (human approval), blocked.

**Audit Trail** — Append-only JSONL logs. Static security analysis via \`envpod audit --security\`.

**Monitoring Agent** — Background policy engine can autonomously freeze or restrict a pod.

**Remote Control** — Freeze, resume, kill, or restrict a running pod via \`envpod remote\`.

**Display + Audio** — GPU passthrough, Wayland/X11, PipeWire/PulseAudio forwarding for GUI agents.

**Web Dashboard** — \`envpod dashboard\` starts on localhost:9090 — fleet overview, live resource stats, audit timeline, diff and commit from the browser.

**Embedded Systems** — Runs on Raspberry Pi 4/5 and NVIDIA Jetson Orin (ARM64 static binary). See \`docs/EMBEDDED.md\`.

## CLI Reference

| Command | Description |
|---------|-------------|
| \`envpod init <name> [-c config.yaml]\` | Create a new pod |
| \`envpod setup <name>\` | Re-run setup commands |
| \`envpod run <name> [--root] [-d] [-a] -- <cmd>\` | Run a command inside a pod |
| \`envpod diff <name>\` | Show filesystem changes |
| \`envpod commit <name> [paths...]\` | Apply changes to host |
| \`envpod rollback <name>\` | Discard all overlay changes |
| \`envpod audit <name> [--security] [--json]\` | Audit log or security analysis |
| \`envpod status <name>\` | Pod status and resource usage |
| \`envpod lock <name>\` | Freeze pod state |
| \`envpod kill <name>\` | Stop and rollback |
| \`envpod destroy <names...>\` | Remove pod(s) |
| \`envpod clone <source> <name>\` | Clone a pod (fast) |
| \`envpod base create/ls/destroy\` | Manage base pods |
| \`envpod ls [--json]\` | List all pods |
| \`envpod vault <name> set/get/remove\` | Manage credentials |
| \`envpod ports <name> -p/-P/-i\` | Port forwarding |
| \`envpod discover <name>\` | Live discovery mutations |
| \`envpod dns-daemon\` | Start central DNS daemon |
| \`envpod queue/approve/cancel <name>\` | Action staging queue |
| \`envpod undo <name>\` | Undo last reversible action |
| \`envpod dns <name>\` | Update DNS policy live |
| \`envpod remote <name> <cmd>\` | Remote control |
| \`envpod monitor <name>\` | Monitoring policy |
| \`envpod dashboard [--port 9090]\` | Web dashboard |
| \`envpod gc\` | Clean up orphaned resources |

## System Requirements

- Linux ${ARCH_LABEL}, kernel 5.11+
- cgroups v2 (see \`docs/EMBEDDED.md\` for Pi-specific setup)
- OverlayFS (\`modprobe overlay\`)
- iptables, iproute2

## License

Copyright 2026 Xtellix Inc. Licensed under the GNU Affero General Public License v3.0.
See [LICENSE](LICENSE) for the full text. Converts to Apache-2.0 on 2030-01-01.

Source: https://github.com/markamo/envpod-ce
README_EOF
    info "README.md generated"

    # -----------------------------------------------------------------------
    # 5. Generate LICENSE
    # -----------------------------------------------------------------------

    cp "${SCRIPT_DIR}/LICENSE" "${RELEASE_DIR}/LICENSE"
    cp "${SCRIPT_DIR}/uninstall.sh" "${RELEASE_DIR}/uninstall.sh"
    chmod 755 "${RELEASE_DIR}/uninstall.sh"
    info "LICENSE + uninstall.sh copied"

    # -----------------------------------------------------------------------
    # 6. Copy docs and examples from repo
    # -----------------------------------------------------------------------

    for doc in INSTALL.md DOCKER-TESTING.md FEATURES.md TUTORIALS.md \
               ACTION-CATALOG.md CLI-BLACKBOOK.md FOR-DOCKER-USERS.md EMBEDDED.md; do
        if [[ -f "${SCRIPT_DIR}/docs/${doc}" ]]; then
            cp "${SCRIPT_DIR}/docs/${doc}" "${RELEASE_DIR}/docs/${doc}"
        else
            echo "  Warning: docs/${doc} not found — skipping"
        fi
    done
    info "Documentation copied"

    cp "${SCRIPT_DIR}/examples/"*.yaml "${RELEASE_DIR}/examples/"
    cp "${SCRIPT_DIR}/examples/"*.sh "${RELEASE_DIR}/examples/" 2>/dev/null || true
    local EXAMPLE_COUNT
    EXAMPLE_COUNT=$(ls -1 "${RELEASE_DIR}/examples/"*.yaml 2>/dev/null | wc -l)
    local SCRIPT_COUNT
    SCRIPT_COUNT=$(ls -1 "${RELEASE_DIR}/examples/"*.sh 2>/dev/null | wc -l)
    info "Examples copied (${EXAMPLE_COUNT} YAML configs, ${SCRIPT_COUNT} scripts)"

    # -----------------------------------------------------------------------
    # 7. Create tarball
    # -----------------------------------------------------------------------

    step "Creating tarball for ${ARCH_LABEL}"

    local TARBALL="${SCRIPT_DIR}/${TARBALL_NAME}"
    tar czf "${TARBALL}" -C "${SCRIPT_DIR}/release" "${RELEASE_NAME}"
    info "Created ${TARBALL}"

    # -----------------------------------------------------------------------
    # 8. Summary for this arch
    # -----------------------------------------------------------------------

    step "Release summary — ${ARCH_LABEL}"

    echo ""
    echo "  Release directory: ${RELEASE_DIR}/"
    echo ""
    ls -lh "${RELEASE_DIR}/"
    echo ""

    local TARBALL_SIZE
    TARBALL_SIZE=$(du -h "${TARBALL}" | cut -f1)
    local TARBALL_SHA
    TARBALL_SHA=$(sha256sum "${TARBALL}")

    echo -e "  ${BOLD}Tarball:${NC}  ${TARBALL_NAME} (${TARBALL_SIZE})"
    echo -e "  ${BOLD}SHA-256:${NC} ${TARBALL_SHA}"
    echo ""
    info "Done! Upload ${TARBALL_NAME} to GitHub releases."
    echo ""
    echo "  Install URL:"
    echo "    https://github.com/markamo/envpod-ce/releases/latest/download/${TARBALL_NAME}"
}

# ---------------------------------------------------------------------------
# Main: build requested architectures
# ---------------------------------------------------------------------------

# Detect ARM64 build tool preference
ARM64_TOOL="cross"
if command -v cargo-zigbuild &>/dev/null; then
    ARM64_TOOL="zigbuild"
fi
if command -v cross &>/dev/null; then
    ARM64_TOOL="cross"
fi
# Allow override via environment
ARM64_TOOL="${ARM64_TOOL_OVERRIDE:-${ARM64_TOOL}}"

if ${BUILD_X86}; then
    build_arch "x86_64-unknown-linux-musl" "x86_64" "cargo"
fi

if ${BUILD_ARM64}; then
    echo ""
    echo -e "${BOLD}ARM64 build tool: ${ARM64_TOOL}${NC}"
    echo "  (override: ARM64_TOOL_OVERRIDE=cargo|cross|zigbuild ./build-release.sh --arch arm64)"
    echo ""
    build_arch "aarch64-unknown-linux-musl" "arm64" "${ARM64_TOOL}"
fi

echo ""
echo -e "${GREEN}${BOLD}All builds complete!${NC}"
echo ""
echo "  Next step: create a GitHub release"
echo "    gh release create v${VERSION} envpod-linux-*.tar.gz \\"
echo "      --title \"envpod v${VERSION}\" \\"
echo "      --notes-file RELEASE_NOTES.md"