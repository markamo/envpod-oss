# envpod Examples

68 ready-to-use pod configurations. Copy, customize, deploy.

## Usage

```bash
# Use any example directly
sudo envpod init my-pod -c examples/<example>.yaml
sudo envpod start my-pod

# Or copy and customize
cp examples/coding-agent.yaml my-agent.yaml
# edit my-agent.yaml
sudo envpod init my-agent -c my-agent.yaml
```

## Web Servers

| Example | What it does |
|---|---|
| [webserver-dev.yaml](webserver-dev.yaml) | Python http.server — quick dev, share with client |
| [webserver-node-dev.yaml](webserver-node-dev.yaml) | React/Vue/Svelte/Next.js with live reload |
| [webserver-production.yaml](webserver-production.yaml) | Caddy — compression, caching, security headers, health check |

## AI Coding Agents

| Example | What it does |
|---|---|
| [claude-code.yaml](claude-code.yaml) | Anthropic Claude Code in a governed pod |
| [cursor.yaml](cursor.yaml) | Cursor AI editor |
| [codex.yaml](codex.yaml) | OpenAI Codex CLI |
| [aider.yaml](aider.yaml) | Aider AI pair programming |
| [coding-agent.yaml](coding-agent.yaml) | Generic coding agent template |
| [swe-agent.yaml](swe-agent.yaml) | SWE-agent for automated software engineering |
| [opencode.yaml](opencode.yaml) | OpenCode terminal IDE |
| [iflow-cli.yaml](iflow-cli.yaml) | iFlow CLI agent |
| [kimi-cli.yaml](kimi-cli.yaml) | Kimi CLI agent |

## AI Frameworks

| Example | What it does |
|---|---|
| [langgraph.yaml](langgraph.yaml) | LangGraph / LangChain agent |
| [google-adk.yaml](google-adk.yaml) | Google Agent Development Kit |
| [openclaw.yaml](openclaw.yaml) | OpenClaw messaging assistant |
| [nanoclaw.yaml](nanoclaw.yaml) | NanoClaw lightweight agent |
| [mcp-client.yaml](mcp-client.yaml) | MCP client pod |
| [mcp-server.yaml](mcp-server.yaml) | MCP server pod |

## Ollama / Local AI

| Example | What it does |
|---|---|
| [ollama.yaml](ollama.yaml) | Ollama LLM server |
| [ollama-host.yaml](ollama-host.yaml) | Ollama using host GPU |
| [ollama-desktop.yaml](ollama-desktop.yaml) | Ollama with web display |

## Desktop Environments

| Example | What it does |
|---|---|
| [desktop.yaml](desktop.yaml) | XFCE desktop via noVNC |
| [desktop-openbox.yaml](desktop-openbox.yaml) | Openbox lightweight desktop |
| [desktop-sway.yaml](desktop-sway.yaml) | Sway Wayland desktop |
| [desktop-web.yaml](desktop-web.yaml) | Web display desktop |
| [desktop-user.yaml](desktop-user.yaml) | Desktop with host user cloned |
| [workstation.yaml](workstation.yaml) | Full workstation |
| [workstation-gpu.yaml](workstation-gpu.yaml) | GPU workstation (Chrome, VS Code, GIMP) |
| [workstation-full.yaml](workstation-full.yaml) | Full workstation with all apps |
| [gimp.yaml](gimp.yaml) | GIMP image editor |
| [web-display-novnc.yaml](web-display-novnc.yaml) | noVNC web display template |

## Development Environments

| Example | What it does |
|---|---|
| [ide-ssh.yaml](ide-ssh.yaml) | SSH into pod from any IDE |
| [vscode.yaml](vscode.yaml) | VS Code Server in pod |
| [jupyter.yaml](jupyter.yaml) | Jupyter notebook with GPU |
| [python-env.yaml](python-env.yaml) | Python development environment |
| [nodejs.yaml](nodejs.yaml) | Node.js development environment |
| [devbox.yaml](devbox.yaml) | General development sandbox |
| [code-interpreter.yaml](code-interpreter.yaml) | Code execution sandbox |

## Browser Automation

| Example | What it does |
|---|---|
| [browser.yaml](browser.yaml) | Chrome in a governed pod |
| [browser-use.yaml](browser-use.yaml) | Browser-use web automation |
| [browser-wayland.yaml](browser-wayland.yaml) | Browser with Wayland display |
| [playwright.yaml](playwright.yaml) | Playwright test automation |

## ML / Data Science

| Example | What it does |
|---|---|
| [ml-training.yaml](ml-training.yaml) | ML training with GPU |
| [rl-training.yaml](rl-training.yaml) | Reinforcement learning training |
| [data-pipeline.yaml](data-pipeline.yaml) | Data processing pipeline |

## Multi-Pod / Swarm

| Example | What it does |
|---|---|
| [github-swarm.yaml](github-swarm.yaml) | Multi-agent GitHub workflow |
| [experiment-swarm.yaml](experiment-swarm.yaml) | Parallel experiment runner |
| [discovery-service.yaml](discovery-service.yaml) | Pod discovery server |
| [discovery-client.yaml](discovery-client.yaml) | Pod discovery client |

## Git / GitHub

| Example | What it does |
|---|---|
| [github-repo.yaml](github-repo.yaml) | GitHub repo management |
| [multi-repo.yaml](multi-repo.yaml) | Multi-repo workspace |

## Security

| Example | What it does |
|---|---|
| [hardened-sandbox.yaml](hardened-sandbox.yaml) | Maximum isolation sandbox |
| [sealed-workspace.yaml](sealed-workspace.yaml) | Zero network, sealed mode |
| [pen-test.yaml](pen-test.yaml) | Penetration testing lab |

## Monitoring

| Example | What it does |
|---|---|
| [monitoring-policy.yaml](monitoring-policy.yaml) | Monitoring with policy rules |

## Infrastructure

| Example | What it does |
|---|---|
| [api-server.yaml](api-server.yaml) | API server template |
| [cron-agent.yaml](cron-agent.yaml) | Scheduled task runner |
| [docker-in-pod.yaml](docker-in-pod.yaml) | Docker inside an envpod pod |
| [fuse-agent.yaml](fuse-agent.yaml) | FUSE filesystem agent |
| [host-apps.yaml](host-apps.yaml) | Mount host apps into pod |
| [clone-user.yaml](clone-user.yaml) | Clone host user into pod |

## Basics

| Example | What it does |
|---|---|
| [basic-cli.yaml](basic-cli.yaml) | Minimal CLI pod |
| [basic-internet.yaml](basic-internet.yaml) | Pod with internet access |
| [demo-pod.yaml](demo-pod.yaml) | Demo/tutorial pod |
| [tutoring.yaml](tutoring.yaml) | AI tutoring agent |

## Embedded / ARM

| Example | What it does |
|---|---|
| [raspberry-pi.yaml](raspberry-pi.yaml) | Raspberry Pi 4/5 |
| [jetson-orin.yaml](jetson-orin.yaml) | NVIDIA Jetson Orin |

## Gemini

| Example | What it does |
|---|---|
| [gemini-cli.yaml](gemini-cli.yaml) | Google Gemini CLI |

## Quick Start

```bash
# Simplest — isolated shell with internet
sudo envpod init demo -c examples/basic-internet.yaml
sudo envpod run demo -- bash

# AI coding agent
sudo envpod init claude -c examples/claude-code.yaml
sudo envpod run claude -- claude

# Web server (dev)
cd my-project
sudo envpod init dev -c examples/webserver-dev.yaml
sudo envpod start dev
# → http://<pod-ip>:8080

# GPU workstation with desktop
sudo envpod init ws -c examples/workstation-gpu.yaml
sudo envpod start ws
# → http://<pod-ip>:6080/vnc.html

# See what changed
sudo envpod diff demo

# Accept or rollback
sudo envpod commit demo        # apply changes to host
sudo envpod rollback demo      # discard everything
```
