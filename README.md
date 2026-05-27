# Arch Linux Setup

Setup script for drivers and dev tooling.

## What it updates

| Step | Category | Packages / Method |
|------|----------|-------------------|
| 1 | **System** | Full system update via `pacman -Syu` |
| 2 | **Video** | `mesa`, `vulkan-intel`, `intel-media-driver`, `libva-mesa-driver`, `libva-utils`, `intel-gpu-tools` |
| 3 | **Audio** | `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber`, `alsa-utils`, `sof-firmware`; enables PipeWire user services |
| 4 | **Network** | `dkms`, `bluez`, `bluez-utils`; enables `bluetooth.service` |
| 5 | **Security & Firmware** | `intel-ucode`, `tpm2-tools`, `fwupd`; `thermald` from AUR; Lenovo firmware via `fwupd` |
| 6 | **Build + Brew** | `base-devel` and Homebrew bootstrap (manual clone method) |
| 7 | **Docker** | `docker`, `docker-buildx`, `docker-compose` via pacman; enables `docker.service`; adds user to `docker` group |
| 8 | **Userland (Brew)** | `git`, `curl`, `wget`, `vim`, `fish`, `starship`, `asdf` |
| 9 | **Shell + asdf** | Fish config, Starship config, Python 3.12.10, Node.js 24.14.0 |
| 10 | **Fonts** | JetBrains Mono latest stable (download at runtime) |
| 11 | **Tools** | Zed (via official install script) |
| 12 | **Cleanup** | Remove orphaned packages (`pacman -Rns`) and clean cache (`pacman -Sc`) |
| 13 | **AI Tooling** | Claude Code installer (current user) |
| 14 | **AI Tooling** | OpenCode installer (current user) |
| 15 | **CLI** | `github-cli` via pacman |
| 16 | **Terminal** | `warp-terminal` from AUR |
| 17 | **IDE** | JetBrains Toolbox (latest via API, fallback to local tarball) |
| 18 | **Desktop** | Set GNOME wallpaper to `assets/wallpapers/red_distortion_3.jpg` (`zoom`) |

> **Note:** AUR packages (`thermald`, `warp-terminal`) are built using a standalone `build_and_install_aur()` helper — no external AUR helper (yay, paru) required. The PKGBUILD is compiled as the real user and installed via `pacman -U` as root.

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
git checkout arch
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

The script requires root privileges and will prompt for a reboot at the end if the running kernel differs from the installed one.

**Note — step 7 (Docker):** after the script adds your user to the `docker` group, run `newgrp docker` in the current terminal or open a new session before using Docker without `sudo`.

**Note — step 8 (Fish shell):** the script sets fish as the default shell via `usermod -s`. If for any reason it doesn't take effect, run manually:
```bash
sudo chsh -s /home/linuxbrew/.linuxbrew/bin/fish $USER
```
Then open a new terminal session for the change to apply.

**Note — step 18 (Wallpaper):** requires an active graphical login session. If no desktop session bus is found, the step is skipped with a warning showing the manual `gsettings` command.

## Requirements

- `curl` and `git` (installed automatically by the script via `base-devel` step if missing)
- `fwupd` (installed in step 5)
- `fontconfig` and `unzip` are installed automatically when needed (JetBrains Mono step)
