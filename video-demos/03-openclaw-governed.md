# Demo 3: "OpenClaw — Messaging Agent, Finally Governed"

**Platform:** YouTube / LinkedIn feature deep-dive
**Length:** ~2.5 min
**Audience:** Developers running autonomous agents (not just coding agents)
**Setup:** Ubuntu 24.04, terminal

---

## Script

**[0:00]** *Narration: "OpenClaw connects to WhatsApp, Telegram, Discord — and talks to LLMs on your behalf. That's a lot of power. Let's govern it."*

**[0:12]** Show the config:
```bash
cat examples/openclaw.yaml
```
*Highlight: DNS whitelist locks it to LLM providers + messaging platforms + npm. No other internet. 2 cores, 1GB RAM, 24h budget.*

**[0:30]** Init, setup, vault:
```bash
sudo envpod init openclaw -c examples/openclaw.yaml
sudo envpod setup openclaw
```
*Narration: "Setup installs Node.js 22 and OpenClaw — all inside the overlay. Takes a minute."*

**[0:50]** Store credentials:
```bash
sudo envpod vault openclaw set ANTHROPIC_API_KEY
sudo envpod vault openclaw set OPENAI_API_KEY
```
*Narration: "Each key encrypted separately. The agent gets them at runtime — never sees them in config files or env dumps."*

**[1:05]** Launch:
```bash
sudo envpod run openclaw -- openclaw
```
*Show OpenClaw starting, connecting to messaging platforms.*

**[1:25]** Second terminal — live audit:
```bash
sudo envpod audit openclaw
```
*Narration: "Every API call, every message sent, every LLM invocation — logged."*

**[1:40]** Show the diff (files OpenClaw created/modified):
```bash
sudo envpod diff openclaw
```

**[1:55]** Show pod resource usage:
```bash
sudo envpod ls
```
*Narration: "Live resource consumption. CPU, memory, PIDs. If it goes rogue — freeze it."*

**[2:10]** Freeze and resume:
```bash
sudo envpod freeze openclaw
# ... inspect ...
sudo envpod resume openclaw
```
*Narration: "Instant freeze. Every process in the pod suspended. Inspect, then resume or kill."*

**[2:30]** End card.

---

## Commands (copy-paste)

```bash
sudo envpod init openclaw -c examples/openclaw.yaml
sudo envpod setup openclaw
sudo envpod vault openclaw set ANTHROPIC_API_KEY
sudo envpod vault openclaw set OPENAI_API_KEY
sudo envpod run openclaw -- openclaw
sudo envpod audit openclaw
sudo envpod diff openclaw
sudo envpod ls
sudo envpod freeze openclaw
sudo envpod resume openclaw
```
