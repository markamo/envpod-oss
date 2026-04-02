#!/bin/bash
# Setup Claude Code dev pod with host git/gh/claude profiles
#
# Usage:
#   cd /path/to/your/project
#   bash examples/claude-code-dev-setup.sh
#
# This creates a governed Claude Code session that uses your existing
# git config, GitHub CLI auth, and Claude Code login from the host.

set -e

POD_NAME="claude-dev"
CONFIG="examples/claude-code-dev.yaml"

echo "=== Creating Claude Code dev pod ==="
sudo envpod destroy "$POD_NAME" 2>/dev/null || true
sudo envpod init "$POD_NAME" -c "$CONFIG"

echo ""
echo "=== Mounting host profiles ==="

# Get the pod's overlay upper dir to inject host configs
POD_DIR=$(sudo find /var/lib/envpod/pods -name "pod.yaml" -exec grep -l "claude-dev" {} \; | head -1 | xargs dirname)

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
    echo "  ✓ Git config copied"
fi

# 2. GitHub CLI auth
if [ -d "$HOME/.config/gh" ]; then
    sudo mkdir -p "$UPPER/home/agent/.config/gh"
    sudo cp -r "$HOME/.config/gh/"* "$UPPER/home/agent/.config/gh/"
    sudo chown -R 60000:60000 "$UPPER/home/agent/.config"
    echo "  ✓ GitHub CLI auth copied"
fi

# 3. Claude Code credentials
if [ -d "$HOME/.claude" ]; then
    sudo mkdir -p "$UPPER/home/agent/.claude"
    sudo cp -r "$HOME/.claude/"* "$UPPER/home/agent/.claude/" 2>/dev/null || true
    sudo chown -R 60000:60000 "$UPPER/home/agent/.claude"
    echo "  ✓ Claude Code credentials copied"
fi

# 4. SSH keys (for git push)
if [ -d "$HOME/.ssh" ]; then
    sudo mkdir -p "$UPPER/home/agent/.ssh"
    sudo cp "$HOME/.ssh/id_"* "$UPPER/home/agent/.ssh/" 2>/dev/null || true
    sudo cp "$HOME/.ssh/known_hosts" "$UPPER/home/agent/.ssh/" 2>/dev/null || true
    sudo cp "$HOME/.ssh/config" "$UPPER/home/agent/.ssh/" 2>/dev/null || true
    sudo chown -R 60000:60000 "$UPPER/home/agent/.ssh"
    sudo chmod 700 "$UPPER/home/agent/.ssh"
    sudo chmod 600 "$UPPER/home/agent/.ssh/"* 2>/dev/null || true
    echo "  ✓ SSH keys copied"
fi

# 5. Copy project into workspace (writable in overlay)
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
sudo mkdir -p "$UPPER/workspace"
sudo cp -a "$PROJECT_DIR" "$UPPER/workspace/$PROJECT_NAME"
sudo chown -R 60000:60000 "$UPPER/workspace/$PROJECT_NAME"
echo "  ✓ Project copied to /workspace/$PROJECT_NAME"

echo ""
echo "=== Ready ==="
echo ""
echo "  Run Claude Code:"
echo "    sudo envpod run $POD_NAME -- bash -c 'cd /workspace/$PROJECT_NAME && claude'"
echo ""
echo "  After work:"
echo "    sudo envpod diff $POD_NAME"
echo "    sudo envpod commit $POD_NAME /workspace/$PROJECT_NAME/ --output ."
echo "    sudo envpod rollback $POD_NAME"
echo ""
echo "  Project at /workspace/$PROJECT_NAME (writable, COW-isolated)."
echo "  Host profiles (git, gh, claude, ssh) available inside the pod."
echo "  Use 'envpod commit --output .' to export changes back to host."
