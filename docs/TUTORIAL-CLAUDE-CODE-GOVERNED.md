# Tutorial: Run Claude Code in a Governed Pod

Let Claude Code work autonomously — but review every change before it touches your machine. Takes 5 minutes.

## Why

Claude Code is powerful. It reads your codebase, writes code, runs tests, installs packages. But:

- What if it modifies files you didn't expect?
- What if it installs something sketchy?
- What if it runs for 12 hours burning API credits?
- What if it reaches domains it shouldn't?

envpod wraps Claude Code in a governance layer. Claude works freely inside the pod, but nothing reaches your real filesystem until you review and commit.

## What you get

```
Without envpod:
  Claude Code → reads/writes your real filesystem → hope for the best

With envpod:
  Claude Code → reads/writes a COW overlay → you review (envpod diff) → commit or rollback
```

Every file change tracked. Every command logged. DNS filtered. Budget limited. All automatic.

## Step 1: Install envpod

```bash
curl -fsSL https://envpod.dev/install.sh | sudo sh
```

## Step 2: Set your API key

```bash
sudo envpod vault claude-agent set ANTHROPIC_API_KEY
# Paste your key, press Ctrl+D
```

The key is encrypted and stored in the vault — never in plain text, never in the agent's environment directly.

## Step 3: Create the pod

```bash
sudo envpod init claude-agent -c examples/remote-claude-code.yaml
```

This creates an isolated environment with:
- COW filesystem (all writes go to an overlay)
- DNS allowlist (only Anthropic API, GitHub, package managers)
- 8-hour budget (auto-stops to prevent runaway costs)
- Full audit trail

## Step 4: Run Claude Code

```bash
sudo envpod run claude-agent -- claude
```

Claude Code starts inside the pod. It sees your mounted code, has internet access to whitelisted domains, and can install packages. But everything it does is:

- **Isolated** — writes go to the overlay, not your real filesystem
- **Logged** — every command in the audit trail
- **Filtered** — can only reach domains you whitelisted
- **Limited** — stops after 8 hours

Let it work. Go have coffee. Come back.

## Step 5: Review what Claude did

```bash
# See every file Claude changed
sudo envpod diff claude-agent
```

Output:
```
  Modified  src/auth.py
  Modified  src/tests/test_auth.py
  Added     src/utils/validator.py
  Modified  requirements.txt

  4 files changed
```

Want more detail?
```bash
# Full diff (like git diff)
sudo envpod diff claude-agent --all
```

## Step 6: Check the audit trail

```bash
sudo envpod audit claude-agent
```

Output:
```
  2026-04-01 10:23:53  Start       cmd=claude
  2026-04-01 10:24:01  DnsQuery    api.anthropic.com → allowed
  2026-04-01 10:24:15  DnsQuery    pypi.org → allowed
  2026-04-01 10:25:30  DnsQuery    sketchy-site.com → BLOCKED
  2026-04-01 10:45:00  DnsQuery    github.com → allowed
  ...
  68 entries
```

Every DNS query, every significant action — timestamped and permanent.

## Step 7: Commit or rollback

**Happy with the changes?** Commit them to your real filesystem:

```bash
# Commit everything
sudo envpod commit claude-agent

# Or commit only specific paths
sudo envpod commit claude-agent src/auth.py src/tests/

# Or commit to a separate directory (safe export)
sudo envpod commit claude-agent --output /tmp/claude-output/
```

**Not happy?** Discard everything:

```bash
sudo envpod rollback claude-agent
```

Your real filesystem is untouched. Claude's changes vanish.

## Step 8: Selective commit + rollback

The most powerful pattern — keep the good, discard the rest:

```bash
# Commit the code changes
sudo envpod commit claude-agent src/ --rollback-rest
```

This commits `src/` to your filesystem and rolls back everything else (temp files, package caches, etc.).

## Budget in action

If Claude runs for 8 hours, envpod warns at 7 hours:

```
  ! Budget warning: 1h remaining (max_duration=8h)
```

At 8 hours, it gracefully shuts down:
```
  ! Budget exceeded: max_duration=8h — stopping pod
  Sending SIGTERM (grace period: 60s)...
  Process exited gracefully
```

Check budget status anytime:
```bash
sudo envpod budget claude-agent
```
```
  Budget claude-agent

  duration    ━━━━━━━━━━━━━━━━━━━━━ 62%  (4h58m / 8h)

  grace       1m
  warning     1h before limit
```

## DNS filtering in action

Claude can only reach whitelisted domains:

```bash
# Inside the pod, these work:
curl https://api.anthropic.com    # ✓ allowed
pip install flask                  # ✓ pypi.org allowed
git clone github.com/...          # ✓ github.com allowed

# These are blocked:
curl https://evil-site.com        # ✗ NXDOMAIN
curl https://pastebin.com         # ✗ NXDOMAIN
```

Every blocked query appears in the audit trail.

## Run non-interactively (background)

Let Claude work while you do other things:

```bash
# Start in background with a task
sudo envpod run claude-agent -b -- claude -p "add comprehensive unit tests for the auth module"

# Check progress anytime
sudo envpod diff claude-agent     # what has it changed?
sudo envpod audit claude-agent    # what has it done?
sudo envpod budget claude-agent   # how much time left?

# When done, review and commit
sudo envpod diff claude-agent --all
sudo envpod commit claude-agent src/tests/
```

## Multiple agents, parallel work

Run multiple Claude instances on different tasks:

```bash
# Agent 1: write tests
sudo envpod clone claude-agent claude-tests
sudo envpod run claude-tests -b -- claude -p "write unit tests for auth"

# Agent 2: fix bugs
sudo envpod clone claude-agent claude-bugfix
sudo envpod run claude-bugfix -b -- claude -p "fix the login timeout bug"

# Agent 3: docs
sudo envpod clone claude-agent claude-docs
sudo envpod run claude-docs -b -- claude -p "update API documentation"

# Each runs in isolation. Review each independently.
sudo envpod diff claude-tests
sudo envpod diff claude-bugfix
sudo envpod diff claude-docs

# Commit what you like from each
sudo envpod commit claude-tests src/tests/
sudo envpod commit claude-bugfix src/auth.py
sudo envpod commit claude-docs docs/
```

Clone is ~8ms. Three governed agents running in parallel, each isolated, each auditable.

## Remote monitoring (Premium)

With envpod Premium, monitor Claude from anywhere:

```bash
# Uncomment in pod.yaml:
# remote:
#   enabled: true
#   relay: "wss://relay.envpod.dev/ws"

# Then from your phone / office / anywhere:
curl -H "Authorization: Bearer <TOKEN>" \
  https://relay.envpod.dev/pod/<ID>/api/diff

# Freeze a runaway agent from your phone:
curl -X POST -H "Authorization: Bearer <TOKEN>" \
  https://relay.envpod.dev/pod/<ID>/api/freeze
```

## Clean up

```bash
# Destroy the pod (all overlay data gone)
sudo envpod destroy claude-agent

# Or keep it for next time
sudo envpod stop claude-agent     # stop, keep state
sudo envpod start claude-agent    # resume later
```

## Summary

| Without envpod | With envpod |
|---|---|
| Claude writes to your real filesystem | Claude writes to a COW overlay |
| No visibility into what changed | `envpod diff` shows every change |
| No audit trail | Every command logged |
| No way to undo | `envpod rollback` discards everything |
| Unlimited runtime + API spend | Budget auto-stops after 8h |
| Can reach any URL | DNS allowlist blocks unauthorized domains |
| Hope for the best | Review, then commit |

Docker isolates. envpod governs.
