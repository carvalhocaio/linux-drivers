# Ubuntu Setup

Setup script for drivers and dev tooling.

## What it updates

| Step | Category | Packages |
|------|----------|----------|
| 1 | **System** | All system packages via `apt upgrade` |
| 2 | **Video** | Mesa, Vulkan, Intel VA-API, `ubuntu-drivers` recommendations |
| 3 | **Audio** | PipeWire, ALSA, Intel SOF firmware |
| 4 | **Network** | Realtek Wi-Fi/Ethernet firmware, Bluetooth (BlueZ) |
| 5 | **Security & Firmware** | Kernel, `intel-microcode`, `thermald`, TPM tools, Lenovo firmware via `fwupd` |
| 6 | **Build + Brew** | `build-essential`, `libssl-dev`, and Homebrew bootstrap/update |
| 7 | **Docker** | Docker Engine, CLI, containerd, Buildx, Compose plugin |
| 8 | **Userland (Brew)** | `git`, `curl`, `wget`, `vim`, `fish`, `starship`, `gh`, `asdf` |
| 9 | **Shell + asdf** | Fish config, Starship config, Python 3.10.14, Node.js 24.14.0 |
| 10 | **Fonts** | JetBrains Mono latest stable (download at runtime) |
| 11 | **Tools** | Zed (via official install script) |
| 12 | **Cleanup** | Remove orphaned packages and stale caches |
| 13 | **AI Tooling** | Claude Code installer (current user) |
| 14 | **Terminal** | Warp latest `.deb` (download via `app.warp.dev/download?package=deb`) |
| 15 | **Desktop** | Set GNOME wallpaper to `assets/wallpapers/red_distortion_3.jpg` (`zoom`) |

## Hardware

- **GPU:** Intel Iris Xe Graphics (TigerLake-LP GT2)
- **Audio:** Intel Tiger Lake-LP Smart Sound Technology
- **Network:** Realtek RTL8822BE (Wi-Fi/Bluetooth) + RTL8111 (Ethernet)
- **Firmware:** Managed via [fwupd](https://fwupd.org/) (Lenovo LVFS support)

## Usage

### Recommended: via `git clone`

```bash
git clone https://github.com/carvalhocaio/ubuntu-drivers.git
cd ubuntu-drivers
sudo ./setup.sh
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
sudo ./setup.sh
```

The script requires root privileges and will prompt for a reboot at the end if one is needed.

Note for step 15 (Wallpaper): this step needs an active graphical login session for the selected user.
If no desktop session bus is available yet, the script will skip wallpaper setup and show a warning.

## Requirements

- `curl` (installed automatically by the script if missing)
- `fwupd` and `ubuntu-drivers` (pre-installed on Ubuntu Desktop)
- `fontconfig` and `unzip` are installed automatically when needed (JetBrains Mono step)
