# Pop!_OS Setup

Setup script for drivers and dev tooling.

## What it updates

| Step | Category | Packages |
|------|----------|----------|
| 1 | **System** | All system packages via `apt upgrade` |
| 2 | **Video** | Mesa, Vulkan, Intel VA-API, `ubuntu-drivers` recommendations |
| 3 | **Audio** | PipeWire, ALSA, Intel SOF firmware |
| 4 | **Network** | Realtek Wi-Fi/Ethernet firmware, Bluetooth (BlueZ) |
| 5 | **Security & Firmware** | `intel-microcode`, `thermald`, TPM tools, Lenovo firmware via `fwupd` |
| 6 | **Build + Brew** | `build-essential`, `libssl-dev`, and Homebrew bootstrap (manual clone method) |
| 7 | **Docker** | Docker Engine, CLI, containerd, Buildx, Compose plugin (idempotent; adds user to `docker` group) |
| 8 | **Userland (Brew)** | `git`, `curl`, `wget`, `vim`, `fish`, `starship`, `asdf` |
| 9 | **Shell + asdf** | Fish config, Starship config, Python 3.12.10, Node.js 24.14.0 |
| 10 | **Fonts** | JetBrains Mono latest stable (download at runtime) |
| 11 | **Tools** | Zed (via official install script) |
| 12 | **Cleanup** | Remove orphaned packages and stale caches |
| 13 | **AI Tooling** | Claude Code installer (current user) |
| 14 | **AI Tooling** | OpenCode installer (current user) |
| 15 | **CLI** | gh CLI via official apt repo (`cli.github.com`) |
| 16 | **Terminal** | Warp latest `.deb` (download via `app.warp.dev/download?package=deb`) |
| 17 | **IDE** | JetBrains Toolbox (latest via API, fallback to local tarball) |
| 18 | **Desktop** | Set GNOME wallpaper to `assets/wallpapers/red_distortion_3.jpg` (`zoom`) |

> **Note:** Pop!_OS does not ship Snap. All tools are installed via `.deb`, Homebrew, or official install scripts — no Snap dependency anywhere in this script.

## Hardware

- **GPU:** Intel Iris Xe Graphics (TigerLake-LP GT2)
- **Audio:** Intel Tiger Lake-LP Smart Sound Technology
- **Network:** Realtek RTL8822BE (Wi-Fi/Bluetooth) + RTL8111 (Ethernet)
- **Firmware:** Managed via [fwupd](https://fwupd.org/) (Lenovo LVFS support)

## Usage

### Recommended: via `git clone`

```bash
git clone https://github.com/carvalhocaio/linux-drivers.git
cd linux-drivers
git checkout popos
sudo bash setup.sh
```

The script opens an interactive selector in the terminal (steps `1-5` are pre-selected by default):

- Arrow keys: move
- Space: check/uncheck a step
- Enter: run selected steps
- `a`: toggle all
- `q`: quit

### Via ZIP download

If you downloaded the repository as a `.zip` from GitHub, the execute bit **is not preserved**.
You need to grant it manually before running:

```bash
chmod +x setup.sh
sudo bash setup.sh
```

The script requires root privileges and will prompt for a reboot at the end if one is needed.

**Note — step 7 (Docker):** after the script adds your user to the `docker` group, run `newgrp docker` in the current terminal or open a new session before using Docker without `sudo`.

**Note — step 8 (Fish shell):** the script sets fish as the default shell via `usermod -s`. If for any reason it doesn't take effect, run manually:
```bash
sudo chsh -s /home/linuxbrew/.linuxbrew/bin/fish $USER
```
Then open a new terminal session for the change to apply.

**Note — step 18 (Wallpaper):** requires an active graphical login session. If no desktop session bus is found, the step is skipped with a warning showing the manual `gsettings` command.

## Requirements

- `curl` (installed automatically by the script if missing)
- `fwupd` (pre-installed on Pop!_OS)
- `fontconfig` and `unzip` are installed automatically when needed (JetBrains Mono step)
