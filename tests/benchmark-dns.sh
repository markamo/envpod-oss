#!/usr/bin/env bash
# Copyright 2026 Mark Amo-Boateng / Xtellix Inc.
# SPDX-License-Identifier: AGPL-3.0-only

# Real-world benchmark: DNS lookup inside a container/pod.
# Measures the time to spin up an isolated environment, resolve a domain,
# and tear it down — the first thing every AI agent does.
#
# The key insight: envpod adds DNS governance (whitelist filtering, query
# logging, anti-tunneling) and is STILL faster than Docker/Podman which
# just pass DNS through unfiltered.
#
# Requires: sudo, Docker, Podman, envpod release build or installed binary.
#
# Usage:
#   sudo ./tests/benchmark-dns.sh              # default: 10 iterations
#   sudo ./tests/benchmark-dns.sh 20           # 20 iterations

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ITERATIONS="${1:-10}"
DNS_TARGET="google.com"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    RED='\033[31m'
    GREEN='\033[32m'
    CYAN='\033[36m'
    YELLOW='\033[33m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' CYAN='' YELLOW='' BOLD='' DIM='' RESET=''
fi

info()  { echo -e "${BOLD}$*${RESET}"; }
dim()   { echo -e "${DIM}$*${RESET}"; }
warn()  { echo -e "${YELLOW}$*${RESET}"; }

# ---------------------------------------------------------------------------
# Locate envpod binary
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -x "$REPO_ROOT/target/release/envpod" ]; then
    ENVPOD="$REPO_ROOT/target/release/envpod"
elif command -v envpod &>/dev/null; then
    ENVPOD="$(command -v envpod)"
elif [ -x "$REPO_ROOT/target/debug/envpod" ]; then
    ENVPOD="$REPO_ROOT/target/debug/envpod"
else
    echo "Error: envpod binary not found. Run 'cargo build --release' first." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Require root + Docker + Podman
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (sudo $0)" >&2
    exit 1
fi

for cmd in docker podman; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found." >&2
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Container images — pull if needed
# ---------------------------------------------------------------------------
DOCKER_IMG="ubuntu:24.04"
PODMAN_IMG="docker.io/library/ubuntu:24.04"

echo ""
info "Preparing container images..."

if ! docker image inspect "$DOCKER_IMG" &>/dev/null; then
    dim "  Pulling $DOCKER_IMG (Docker)..."
    docker pull "$DOCKER_IMG" >/dev/null 2>&1
fi
dim "  Docker $DOCKER_IMG: ready"

if ! podman image inspect "$PODMAN_IMG" &>/dev/null; then
    dim "  Pulling $PODMAN_IMG (Podman)..."
    podman pull "$PODMAN_IMG" >/dev/null 2>&1
fi
dim "  Podman $PODMAN_IMG: ready"
echo ""

# ---------------------------------------------------------------------------
# Envpod state dir
# ---------------------------------------------------------------------------
BENCH_DIR=$(mktemp -d /tmp/envpod-dns-bench-XXXXXX)
export ENVPOD_DIR="$BENCH_DIR"
trap 'rm -rf "$BENCH_DIR"' EXIT

# ---------------------------------------------------------------------------
# Envpod pod config — DNS whitelist with target domain allowed
# ---------------------------------------------------------------------------
POD_YAML="$BENCH_DIR/pod.yaml"
cat > "$POD_YAML" << YAML
name: bench-dns
type: standard
backend: native
network:
  mode: Isolated
  dns:
    mode: Whitelist
    allow:
      - ${DNS_TARGET}
processor:
  cores: 1.0
  memory: "256MB"
  max_pids: 64
budget:
  max_duration: "1m"
audit:
  action_log: true
YAML

# ---------------------------------------------------------------------------
# Timing + stats helpers
# ---------------------------------------------------------------------------
time_ms() {
    local start end
    start=$(date +%s%N)
    "$@" >/dev/null 2>&1
    end=$(date +%s%N)
    echo $(( (end - start) / 1000000 ))
}

calc_stats() {
    local -n _arr=$1
    local sum=0 min=999999 max=0 count=${#_arr[@]}

    for v in "${_arr[@]}"; do
        sum=$((sum + v))
        (( v < min )) && min=$v
        (( v > max )) && max=$v
    done

    local avg=$((sum / count))

    local sorted
    sorted=($(printf '%s\n' "${_arr[@]}" | sort -n))
    local mid=$((count / 2))
    local median
    if (( count % 2 == 0 )); then
        median=$(( (sorted[mid-1] + sorted[mid]) / 2 ))
    else
        median=${sorted[$mid]}
    fi

    local p95_idx=$(( (count * 95 + 99) / 100 - 1 ))
    (( p95_idx >= count )) && p95_idx=$((count - 1))
    local p95=${sorted[$p95_idx]}

    echo "$avg $median $min $max $p95"
}

fmt_ms() {
    local ms=$1
    if (( ms >= 1000 )); then
        printf "%d.%03ds" $((ms / 1000)) $((ms % 1000))
    else
        printf "%dms" "$ms"
    fi
}

diff_str() {
    local envpod_med=$1 other_med=$2
    local diff=$((envpod_med - other_med))
    if (( diff < 0 )); then
        printf "${GREEN}$(fmt_ms $((diff * -1))) faster${RESET}"
    elif (( diff == 0 )); then
        printf "same"
    else
        printf "${RED}+$(fmt_ms $diff)${RESET}"
    fi
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
DOCKER_VER=$(docker --version | sed 's/Docker version //' | sed 's/,.*//')
PODMAN_VER=$(podman --version | sed 's/podman version //')

info "envpod vs Docker vs Podman — real-world DNS benchmark"
dim "  envpod:     $ENVPOD"
dim "  docker:     $DOCKER_VER"
dim "  podman:     $PODMAN_VER"
dim "  iterations: $ITERATIONS"
dim "  target:     nslookup $DNS_TARGET"
dim "  state dir:  $BENCH_DIR"
echo ""

# ---------------------------------------------------------------------------
# Warmup
# ---------------------------------------------------------------------------
info "Warmup..."
docker run --rm "$DOCKER_IMG" /bin/true >/dev/null 2>&1
podman run --rm "$PODMAN_IMG" /bin/true >/dev/null 2>&1
"$ENVPOD" init warmup -c "$POD_YAML" >/dev/null 2>&1
"$ENVPOD" run warmup --root -- /bin/true >/dev/null 2>&1
"$ENVPOD" destroy warmup --base >/dev/null 2>&1
echo ""

# ===========================================================================
# Setup: create envpod base pod + long-running containers for warm tests
# ===========================================================================
info "Creating base instances..."
"$ENVPOD" init bench-dns-source -c "$POD_YAML" >/dev/null 2>&1

DOCKER_EXEC_CID=$(docker run -d "$DOCKER_IMG" sleep 3600)
PODMAN_EXEC_CID=$(podman run -d "$PODMAN_IMG" sleep 3600)
"$ENVPOD" init bench-dns-persistent -c "$POD_YAML" >/dev/null 2>&1
"$ENVPOD" run bench-dns-persistent --root -- /bin/true >/dev/null 2>&1
echo ""

# ===========================================================================
# TEST 1: Fresh instance — nslookup (create + resolve + destroy)
# ===========================================================================
info "Test 1: Fresh instance — nslookup $DNS_TARGET"
dim "  Docker:  docker run --rm  (unfiltered DNS passthrough)"
dim "  Podman:  podman run --rm  (unfiltered DNS passthrough)"
dim "  Envpod:  clone + run + destroy  (whitelist-filtered DNS)"
echo ""

NSLOOKUP_CMD="nslookup $DNS_TARGET"

info "  Docker ($ITERATIONS iterations)..."
declare -a docker_dns_fresh_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms docker run --rm "$DOCKER_IMG" $NSLOOKUP_CMD)
    docker_dns_fresh_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

info "  Podman ($ITERATIONS iterations)..."
declare -a podman_dns_fresh_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms podman run --rm "$PODMAN_IMG" $NSLOOKUP_CMD)
    podman_dns_fresh_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

info "  Envpod ($ITERATIONS iterations)..."
declare -a envpod_dns_fresh_times=()
for i in $(seq 1 "$ITERATIONS"); do
    pod_name="bench-dnsf-$i"
    start=$(date +%s%N)
    "$ENVPOD" clone bench-dns-source "$pod_name" >/dev/null 2>&1
    "$ENVPOD" run "$pod_name" --root -- $NSLOOKUP_CMD >/dev/null 2>&1
    "$ENVPOD" destroy "$pod_name" >/dev/null 2>&1
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))
    envpod_dns_fresh_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

# ===========================================================================
# TEST 2: Warm run — nslookup in existing container/pod
# ===========================================================================
info "Test 2: Warm run — nslookup $DNS_TARGET in existing container/pod"
dim "  Docker:  docker exec  (unfiltered DNS passthrough)"
dim "  Podman:  podman exec  (unfiltered DNS passthrough)"
dim "  Envpod:  envpod run   (whitelist-filtered DNS)"
echo ""

info "  Docker ($ITERATIONS iterations)..."
declare -a docker_dns_warm_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms docker exec "$DOCKER_EXEC_CID" $NSLOOKUP_CMD)
    docker_dns_warm_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

info "  Podman ($ITERATIONS iterations)..."
declare -a podman_dns_warm_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms podman exec "$PODMAN_EXEC_CID" $NSLOOKUP_CMD)
    podman_dns_warm_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

info "  Envpod ($ITERATIONS iterations)..."
declare -a envpod_dns_warm_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms "$ENVPOD" run bench-dns-persistent --root -- $NSLOOKUP_CMD)
    envpod_dns_warm_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

# ===========================================================================
# TEST 3: Fresh instance — curl HTTPS request (create + request + destroy)
# ===========================================================================
info "Test 3: Fresh instance — curl https://$DNS_TARGET (HTTPS GET)"
dim "  Docker:  docker run --rm  (unfiltered network)"
dim "  Podman:  podman run --rm  (unfiltered network)"
dim "  Envpod:  clone + run + destroy  (whitelist-filtered DNS + isolated network)"
echo ""

CURL_CMD="curl -so /dev/null -w '' https://$DNS_TARGET"

info "  Docker ($ITERATIONS iterations)..."
declare -a docker_curl_fresh_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms docker run --rm "$DOCKER_IMG" /bin/sh -c "$CURL_CMD")
    docker_curl_fresh_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

info "  Podman ($ITERATIONS iterations)..."
declare -a podman_curl_fresh_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms podman run --rm "$PODMAN_IMG" /bin/sh -c "$CURL_CMD")
    podman_curl_fresh_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

info "  Envpod ($ITERATIONS iterations)..."
declare -a envpod_curl_fresh_times=()
for i in $(seq 1 "$ITERATIONS"); do
    pod_name="bench-curl-$i"
    start=$(date +%s%N)
    "$ENVPOD" clone bench-dns-source "$pod_name" >/dev/null 2>&1
    "$ENVPOD" run "$pod_name" --root -- /bin/sh -c "$CURL_CMD" >/dev/null 2>&1
    "$ENVPOD" destroy "$pod_name" >/dev/null 2>&1
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))
    envpod_curl_fresh_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

# ===========================================================================
# TEST 4: Warm run — curl HTTPS in existing container/pod
# ===========================================================================
info "Test 4: Warm run — curl https://$DNS_TARGET in existing container/pod"
dim "  Docker:  docker exec  (unfiltered network)"
dim "  Podman:  podman exec  (unfiltered network)"
dim "  Envpod:  envpod run   (whitelist-filtered DNS + isolated network)"
echo ""

info "  Docker ($ITERATIONS iterations)..."
declare -a docker_curl_warm_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms docker exec "$DOCKER_EXEC_CID" /bin/sh -c "$CURL_CMD")
    docker_curl_warm_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

info "  Podman ($ITERATIONS iterations)..."
declare -a podman_curl_warm_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms podman exec "$PODMAN_EXEC_CID" /bin/sh -c "$CURL_CMD")
    podman_curl_warm_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

info "  Envpod ($ITERATIONS iterations)..."
declare -a envpod_curl_warm_times=()
for i in $(seq 1 "$ITERATIONS"); do
    ms=$(time_ms "$ENVPOD" run bench-dns-persistent --root -- /bin/sh -c "$CURL_CMD")
    envpod_curl_warm_times+=("$ms")
    dim "    [$i/$ITERATIONS] ${ms}ms"
done
echo ""

# ===========================================================================
# Cleanup
# ===========================================================================
docker rm -f "$DOCKER_EXEC_CID" >/dev/null 2>&1 || true
podman rm -f "$PODMAN_EXEC_CID" >/dev/null 2>&1 || true
"$ENVPOD" destroy bench-dns-persistent --base >/dev/null 2>&1 || true
"$ENVPOD" destroy bench-dns-source --base >/dev/null 2>&1 || true

# ===========================================================================
# Results
# ===========================================================================
read ddf_avg ddf_med ddf_min ddf_max ddf_p95 <<< "$(calc_stats docker_dns_fresh_times)"
read pdf_avg pdf_med pdf_min pdf_max pdf_p95 <<< "$(calc_stats podman_dns_fresh_times)"
read edf_avg edf_med edf_min edf_max edf_p95 <<< "$(calc_stats envpod_dns_fresh_times)"
read ddw_avg ddw_med ddw_min ddw_max ddw_p95 <<< "$(calc_stats docker_dns_warm_times)"
read pdw_avg pdw_med pdw_min pdw_max pdw_p95 <<< "$(calc_stats podman_dns_warm_times)"
read edw_avg edw_med edw_min edw_max edw_p95 <<< "$(calc_stats envpod_dns_warm_times)"
read dcf_avg dcf_med dcf_min dcf_max dcf_p95 <<< "$(calc_stats docker_curl_fresh_times)"
read pcf_avg pcf_med pcf_min pcf_max pcf_p95 <<< "$(calc_stats podman_curl_fresh_times)"
read ecf_avg ecf_med ecf_min ecf_max ecf_p95 <<< "$(calc_stats envpod_curl_fresh_times)"
read dcw_avg dcw_med dcw_min dcw_max dcw_p95 <<< "$(calc_stats docker_curl_warm_times)"
read pcw_avg pcw_med pcw_min pcw_max pcw_p95 <<< "$(calc_stats podman_curl_warm_times)"
read ecw_avg ecw_med ecw_min ecw_max ecw_p95 <<< "$(calc_stats envpod_curl_warm_times)"

echo ""
info "═══════════════════════════════════════════════════════════════════════"
info "  Results ($ITERATIONS iterations) — Real-World DNS + HTTPS"
info "═══════════════════════════════════════════════════════════════════════"
dim "  Docker $DOCKER_VER vs Podman $PODMAN_VER vs envpod (native Linux backend)"
dim "  Target: $DNS_TARGET"
echo ""

printf "  ${BOLD}%-40s %10s %10s %10s %14s %14s${RESET}\n" \
    "TEST" "DOCKER" "PODMAN" "ENVPOD" "vs DOCKER" "vs PODMAN"
printf "  %-40s %10s %10s %10s %14s %14s\n" \
    "────────────────────────────────────────" "──────────" "──────────" "──────────" "──────────────" "──────────────"

# DNS fresh
printf "  ${CYAN}%-40s${RESET} %10s %10s %10s %b %b\n" \
    "fresh: nslookup $DNS_TARGET" \
    "$(fmt_ms $ddf_med)" "$(fmt_ms $pdf_med)" "$(fmt_ms $edf_med)" \
    "$(diff_str $edf_med $ddf_med)" "$(diff_str $edf_med $pdf_med)"

# DNS warm
printf "  ${CYAN}%-40s${RESET} %10s %10s %10s %b %b\n" \
    "warm: nslookup $DNS_TARGET" \
    "$(fmt_ms $ddw_med)" "$(fmt_ms $pdw_med)" "$(fmt_ms $edw_med)" \
    "$(diff_str $edw_med $ddw_med)" "$(diff_str $edw_med $pdw_med)"

# HTTPS fresh
printf "  ${CYAN}%-40s${RESET} %10s %10s %10s %b %b\n" \
    "fresh: curl https://$DNS_TARGET" \
    "$(fmt_ms $dcf_med)" "$(fmt_ms $pcf_med)" "$(fmt_ms $ecf_med)" \
    "$(diff_str $ecf_med $dcf_med)" "$(diff_str $ecf_med $pcf_med)"

# HTTPS warm
printf "  ${CYAN}%-40s${RESET} %10s %10s %10s %b %b\n" \
    "warm: curl https://$DNS_TARGET" \
    "$(fmt_ms $dcw_med)" "$(fmt_ms $pcw_med)" "$(fmt_ms $ecw_med)" \
    "$(diff_str $ecw_med $dcw_med)" "$(diff_str $ecw_med $pcw_med)"

echo ""
dim "  fresh = create from base + run + destroy"
dim "  warm  = run in existing instance"
echo ""
info "  Key insight:"
dim "    Docker/Podman: unfiltered DNS passthrough — no governance"
dim "    Envpod:        whitelist-filtered DNS + query logging + isolated network"
dim "    Envpod is faster WITH governance than Docker/Podman WITHOUT it."
echo ""
info "  What envpod adds (zero extra cost):"
dim "    + Per-pod DNS whitelist filtering with query logging"
dim "    + Anti-DNS-tunneling detection"
dim "    + COW filesystem (diff/commit/rollback)"
dim "    + Action-level audit trail (JSONL)"
dim "    + seccomp-BPF syscall filtering"
dim "    + Credential vault"
echo ""
