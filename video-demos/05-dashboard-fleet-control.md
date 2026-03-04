# Demo 5: "Dashboard — Fleet Control"

**Platform:** YouTube / LinkedIn — web UI showcase
**Length:** ~90s
**Audience:** Team leads, security engineers
**Setup:** Multiple pods already running (e.g. claude-code, openclaw, browser)

---

## Script

**[0:00]** Start the dashboard:
```bash
sudo envpod dashboard
```
*Browser opens to localhost:9090.*

**[0:10]** Fleet overview — show pod cards with status, CPU/memory, diff counts.

*Narration: "Every pod at a glance. Status, resource consumption, how many files changed."*

**[0:25]** Click into a pod (e.g. claude-code). Show tabs:
- **Overview**: config summary, vault key names (not values)
- **Audit**: scrollable timeline of every action
- **Diff**: file list, colored by change type
- **Resources**: live CPU, memory, PID counts
- **Snapshots**: checkpoint history

**[0:50]** Click "Diff" tab. Review changes. Click "Commit" from the browser.

*Narration: "Review and commit from the browser. No CLI needed."*

**[1:05]** Go back to fleet view. Click "Freeze" on a pod. Show it freeze instantly.

*Narration: "One click. Every process in the pod suspended."*

**[1:20]** End card.

---

## Setup Commands

```bash
# Create a few pods first
sudo envpod init claude-code -c examples/claude-code.yaml
sudo envpod init openclaw -c examples/openclaw.yaml
sudo envpod init browser -c examples/browser-wayland.yaml

# Start dashboard
sudo envpod dashboard
# Opens http://localhost:9090
```
