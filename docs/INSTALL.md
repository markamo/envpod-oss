# Installing envpod

> Copyright 2026 Mark Amo-Boateng / Xtellix Inc. · GNU Affero General Public License v3.0

---

## Requirements

| Requirement | Minimum | Notes |
|---|---|---|
| OS | Linux only | No macOS or Windows support |
| Kernel | 5.15+ | Recommended: 5.19+ or 6.x |
| cgroups | v2 | Run `stat -fc %T /sys/fs/cgroup/` — should print `cgroup2fs` |
| Filesystem | OverlayFS | Run `grep overlay /proc/filesystems` |
| Tools | `iptables`, `ip` (iproute2) | `sudo apt install iptables iproute2` |
| Privilege | root | Required for namespace setup |
| Disk | ~12 MB | Binary only. Pod rootfs requires ~200 MB per pod. |
| Arch | x86\_64 or arm64 | Static musl binary, no runtime dependencies |

---

## Install (one-liner)

```bash
curl -fsSL https://envpod.dev/install.sh | sh
```

The script:
1. Detects your architecture (x86\_64 or arm64)
2. Downloads the latest release tarball from GitHub
3. Prompts for sudo — installs binary, completions, and examples
4. Enables IP forwarding (required for pod networking)

After installation, `envpod` is available at `/usr/local/bin/envpod`.

---

## Verify cgroups v2

```bash
stat -fc %T /sys/fs/cgroup/
```

If the output is `tmpfs`, you have cgroups v1. Enable v2:

**Ubuntu/Debian (GRUB):**
```bash
sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"/' /etc/default/grub
sudo update-grub
sudo reboot
```

**Raspberry Pi** — add to `/boot/cmdline.txt` (one line):
```
cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 systemd.unified_cgroup_hierarchy=1
```

---

## Build from Source

Requires Rust toolchain — install via [rustup.rs](https://rustup.rs).

```bash
git clone https://github.com/markamo/envpod-oss
cd envpod-oss
cargo build --release
sudo cp target/release/envpod /usr/local/bin/
sudo chmod 755 /usr/local/bin/envpod
```

---

## Static musl binary (x86\_64)

Build a fully static binary with no shared library dependencies:

```bash
rustup target add x86_64-unknown-linux-musl
sudo apt install musl-tools
CC_x86_64_unknown_linux_musl=musl-gcc cargo build --release --target x86_64-unknown-linux-musl
```

Output: `target/x86_64-unknown-linux-musl/release/envpod`

---

## ARM64 (Raspberry Pi, Jetson Orin)

The one-liner auto-detects `aarch64` and downloads the arm64 binary. For building from source on ARM64, see [EMBEDDED.md](EMBEDDED.md).

---

## Uninstall

```bash
sudo rm /usr/local/bin/envpod
sudo rm -rf /var/lib/envpod          # removes all pod state, vaults, audit logs
sudo rm /etc/bash_completion.d/envpod
sudo rm /etc/sysctl.d/99-envpod.conf
```

---

## Next Steps

- [Quickstart](QUICKSTART.md) — create your first pod in 60 seconds
- [Tutorials](TUTORIALS.md) — step-by-step guides for common use cases
- [CLI Reference](CLI-BLACKBOOK.md) — complete command reference
