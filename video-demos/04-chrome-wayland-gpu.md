# Demo 4: "Chrome in a Pod — Wayland + GPU"

**Platform:** YouTube / X — most visually impressive demo
**Length:** ~90s
**Audience:** Anyone — visual wow factor
**Setup:** Ubuntu 24.04 with Wayland session (GNOME), PipeWire, Chrome installed on host

---

## Script

**[0:00]** *Narration: "A browser agent needs GPU, display, and audio. Here's how envpod does it without Docker."*

**[0:08]** Show the config:
```bash
cat examples/browser-wayland.yaml
```
*Highlight: `gpu: true`, `display: true`, `audio: true`, `display_protocol: wayland`, `audio_protocol: pipewire`, browser seccomp, 4GB RAM.*

**[0:22]** Init:
```bash
sudo envpod init browser -c examples/browser-wayland.yaml
```

**[0:30]** Launch Chrome inside the pod with display and audio forwarding:
```bash
sudo envpod run browser -d -a -- google-chrome --no-sandbox --ozone-platform=wayland https://youtube.com
```
*Chrome window appears on the desktop. Navigate YouTube. Play a video — audio works.*

*Narration: "Full Wayland display forwarding. GPU-accelerated rendering. PipeWire audio. All inside a governed pod."*

**[0:55]** Show what's different from Docker:
```bash
sudo envpod diff browser
sudo envpod audit browser
```
*Narration: "Every file Chrome wrote — cookies, cache, preferences — captured in the overlay. Audit log shows every network domain it contacted."*

**[1:10]** Rollback everything:
```bash
sudo envpod rollback browser
```
*Narration: "One command. All traces gone. No base image. No container OS. Just your host, governed."*

**[1:25]** End card.

---

## Commands (copy-paste)

```bash
sudo envpod init browser -c examples/browser-wayland.yaml
sudo envpod run browser -d -a -- google-chrome --no-sandbox --ozone-platform=wayland https://youtube.com
sudo envpod diff browser
sudo envpod audit browser
sudo envpod rollback browser
```
