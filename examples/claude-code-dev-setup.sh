#!/bin/bash
# Setup Claude Code dev pod with host git/gh/claude profiles
#
# Usage:
#   cd /path/to/your/project
#   bash claude-code-dev-setup.sh              # pod name from folder
#   bash claude-code-dev-setup.sh my-pod       # custom pod name
#
# Each project gets its own pod. Running again reuses the existing pod.

set -e

# Pod name: argument > folder name > "claude-dev"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
POD_NAME="${1:-$PROJECT_NAME}"

# Sanitize pod name (lowercase, replace spaces/dots/underscores with dashes)
POD_NAME=$(echo "$POD_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ._' '---' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

# Find config (check common locations)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG=""
for path in \
    "$SCRIPT_DIR/claude-code-dev.yaml" \
    "$SCRIPT_DIR/../examples/claude-code-dev.yaml" \
    "/home/$USER/apps/envpod-source/examples/claude-code-dev.yaml" \
    "/usr/local/share/envpod/examples/claude-code-dev.yaml"; do
    if [ -f "$path" ]; then
        CONFIG="$path"
        break
    fi
done

if [ -z "$CONFIG" ]; then
    echo "Error: claude-code-dev.yaml not found"
    exit 1
fi

# Check if pod already exists
if sudo envpod ls 2>/dev/null | grep -q "^${POD_NAME} "; then
    echo "=== Pod '$POD_NAME' exists — starting ==="
    sudo envpod start "$POD_NAME" 2>/dev/null || true
    echo ""
    echo "  Run Claude Code:"
    echo "    sudo envpod run $POD_NAME -- bash -c 'cd /workspace/$PROJECT_NAME && claude'"
    echo ""
    exit 0
fi

echo "=== Creating pod: $POD_NAME (project: $PROJECT_NAME) ==="
sudo envpod init "$POD_NAME" -c "$CONFIG"

echo ""
echo "=== Mounting host profiles ==="

# Get the pod's overlay upper dir
POD_DIR=$(sudo find /var/lib/envpod/pods -name "pod.yaml" -exec grep -l "$POD_NAME" {} \; | head -1 | xargs dirname 2>/dev/null)

if [ -z "$POD_DIR" ]; then
    echo "Error: pod directory not found"
    exit 1
fi

UPPER="$POD_DIR/upper"

# 1. Git config
if [ -f "$HOME/.gitconfig" ]; then
    sudo mkdir -p "$UPPER/home/agent"
    sudo cp "$HOME/.gitconfig" "$UPPER/home/agent/.gitconfig"
    sudo chown 60000:60000 "$UPPER/home/agent/.gitconfig"
    echo "  ✓ Git config"
fi

# 2. GitHub CLI auth
if [ -d "$HOME/.config/gh" ]; then
    sudo mkdir -p "$UPPER/home/agent/.config/gh"
    sudo cp -r "$HOME/.config/gh/"* "$UPPER/home/agent/.config/gh/"
    sudo chown -R 60000:60000 "$UPPER/home/agent/.config"
    echo "  ✓ GitHub CLI"
fi

# 3. Claude Code credentials (auth only, not sessions/backups)
if [ -d "$HOME/.claude" ]; then
    sudo mkdir -p "$UPPER/home/agent/.claude"
    # Only copy auth files, not sessions or backups
    for f in credentials.json settings.json statsig.json; do
        [ -f "$HOME/.claude/$f" ] && sudo cp "$HOME/.claude/$f" "$UPPER/home/agent/.claude/" 2>/dev/null
    done
    [ -f "$HOME/.claude.json" ] && sudo cp "$HOME/.claude.json" "$UPPER/home/agent/.claude.json" 2>/dev/null
    # Copy project-specific memory (CLAUDE.md context, todos, session notes)
    MEMORY_DIR="$HOME/.claude/projects/-$(echo "$PROJECT_DIR" | tr '/' '-')/memory"
    if [ -d "$MEMORY_DIR" ]; then
        AGENT_MEMORY="$UPPER/home/agent/.claude/projects/-$(echo "/workspace/$PROJECT_NAME" | tr '/' '-')/memory"
        sudo mkdir -p "$AGENT_MEMORY"
        sudo cp -r "$MEMORY_DIR/"* "$AGENT_MEMORY/" 2>/dev/null
        echo "  ✓ Claude Code (auth + project memory)"
    else
        echo "  ✓ Claude Code (auth only)"
    fi
    sudo chown -R 60000:60000 "$UPPER/home/agent/.claude" "$UPPER/home/agent/.claude.json" 2>/dev/null
fi

# 4. SSH keys
if [ -d "$HOME/.ssh" ]; then
    sudo mkdir -p "$UPPER/home/agent/.ssh"
    sudo cp "$HOME/.ssh/id_"* "$UPPER/home/agent/.ssh/" 2>/dev/null || true
    sudo cp "$HOME/.ssh/known_hosts" "$UPPER/home/agent/.ssh/" 2>/dev/null || true
    sudo cp "$HOME/.ssh/config" "$UPPER/home/agent/.ssh/" 2>/dev/null || true
    sudo chown -R 60000:60000 "$UPPER/home/agent/.ssh"
    sudo chmod 700 "$UPPER/home/agent/.ssh"
    sudo chmod 600 "$UPPER/home/agent/.ssh/"* 2>/dev/null || true
    echo "  ✓ SSH keys"
fi

# 5. Copy project into workspace (writable in overlay)
sudo mkdir -p "$UPPER/workspace"
sudo cp -a "$PROJECT_DIR" "$UPPER/workspace/$PROJECT_NAME"
sudo chown -R 60000:60000 "$UPPER/workspace/$PROJECT_NAME"
echo "  ✓ Project → /workspace/$PROJECT_NAME"

echo ""
echo "=== Ready: $POD_NAME ==="
echo ""
echo "  Run Claude Code:"
echo "    sudo envpod run $POD_NAME -- bash -c 'cd /workspace/$PROJECT_NAME && claude'"
echo ""
echo "  Interactive shell:"
echo "    sudo envpod run $POD_NAME -- bash"
echo "    cd /workspace/$PROJECT_NAME"
echo ""
echo "  After work:"
echo "    sudo envpod diff $POD_NAME"
echo "    sudo envpod commit $POD_NAME /workspace/$PROJECT_NAME/ --output $PROJECT_DIR"
echo "    sudo envpod rollback $POD_NAME"
