# Demo 2: "Claude Code — Governed"

**Platform:** YouTube / LinkedIn full walkthrough
**Length:** ~3 min
**Audience:** Developers using AI coding agents
**Setup:** Ubuntu 24.04, a small project directory (e.g. a Node.js app), terminal

---

## Script

**[0:00]** *Narration: "I run Claude Code every day. Here's the problem: it has full access to my filesystem, my API keys, my git credentials. If something goes wrong — good luck."*

**[0:15]** Show the pod config:
```bash
cat examples/claude-code.yaml
```
*Highlight: DNS whitelist (only Anthropic, GitHub, npm, PyPI, Cargo), 2 cores, 4GB RAM, 30min budget, browser seccomp.*

**[0:35]** Init and setup:
```bash
sudo envpod init claude-code -c examples/claude-code.yaml
sudo envpod setup claude-code
```
*Narration: "Init creates the pod. Setup runs the install — curl the Claude installer, all inside the overlay."*

**[1:00]** Store the API key in the vault:
```bash
sudo envpod vault claude-code set ANTHROPIC_API_KEY
# (pastes key, not echoed)
```
*Narration: "The key goes into an encrypted vault — ChaCha20-Poly1305. The agent gets it as an env var at runtime but it never touches disk in plaintext."*

**[1:15]** Run Claude Code:
```bash
sudo envpod run claude-code -- claude
```
*Show Claude Code starting up inside the pod. Give it a task — e.g. "add input validation to server.js".*

**[1:45]** While Claude works, open a second terminal. Show live monitoring:
```bash
sudo envpod audit claude-code
```
*Narration: "Real-time audit log. Every file write, every network call, every tool invocation."*

**[2:00]** Claude finishes. Review the diff:
```bash
sudo envpod diff claude-code
```
*Narration: "Here's everything Claude changed. Green = added, red = deleted. Nothing reached my real codebase yet."*

**[2:20]** Commit the good changes:
```bash
sudo envpod commit claude-code
```
*Narration: "Now it's on the host. If I didn't like it — rollback. Zero risk."*

**[2:35]** Show the security audit:
```bash
sudo envpod audit claude-code --security
```
*Narration: "Static analysis of the pod config. Tells you exactly what attack surface you're exposing."*

**[2:50]** End card. *Narration: "Docker isolates. Envpod governs."*

---

## Commands (copy-paste)

```bash
sudo envpod init claude-code -c examples/claude-code.yaml
sudo envpod setup claude-code
sudo envpod vault claude-code set ANTHROPIC_API_KEY
sudo envpod run claude-code -- claude
sudo envpod diff claude-code
sudo envpod commit claude-code
sudo envpod audit claude-code
sudo envpod audit claude-code --security
```
