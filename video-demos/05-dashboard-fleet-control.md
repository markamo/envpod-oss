# Demo 5: "Dashboard — Fleet Control"

**Platform:** YouTube / LinkedIn — web UI showcase
**Length:** ~90s
**Audience:** Team leads, security engineers
**Setup:** Multiple pods already running (e.g. claude-code, openclaw, browser)

---

## Script

**[0:00]** Spin up a fleet using presets:
```bash
sudo envpod init claude-code --preset claude-code
sudo envpod init openclaw --preset openclaw
sudo envpod init browser --preset browser
sudo envpod init aider --preset aider
```
*Narration: "Four agents, four presets, four commands. Each one fully isolated and governed."*

**[0:15]** Start the dashboard:
```bash
sudo envpod dashboard
```
*Browser opens to localhost:9090.*

**[0:22]** Fleet overview — show pod cards with status, CPU/memory, diff counts.

*Narration: "Every pod at a glance. Status, resource consumption, how many files changed."*

**[0:35]** Click into a pod (e.g. claude-code). Show tabs:
- **Overview**: config summary, vault key names (not values)
- **Audit**: scrollable timeline of every action
- **Diff**: file list, colored by change type
- **Resources**: live CPU, memory, PID counts
- **Snapshots**: checkpoint history with create/restore/delete

**[0:55]** Click "Diff" tab. Review changes. Click "Commit" from the browser.

*Narration: "Review and commit from the browser. No CLI needed."*

**[1:05]** Show snapshots — create one from the dashboard:
```
Click "Create Snapshot" → name it "checkpoint-1" → shows in timeline
```
*Narration: "Snapshot the overlay state. Restore any time if something goes wrong."*

**[1:15]** Go back to fleet view. Click "Freeze" on a pod. Show it freeze instantly.

*Narration: "One click. Every process in the pod suspended."*

**[1:25]** End card. *Narration: "18 presets. One dashboard. Full governance."*

---

## Setup Commands

```bash
# Create pods using presets
sudo envpod init claude-code --preset claude-code
sudo envpod init openclaw --preset openclaw
sudo envpod init browser --preset browser
sudo envpod init aider --preset aider

# Start dashboard
sudo envpod dashboard
# Opens http://localhost:9090
```
