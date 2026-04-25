# Ubuntu Drivers — Lenovo ThinkPad E14

Shell script to update all drivers on a Lenovo ThinkPad E14 running Ubuntu.

## What it updates

| Step | Category | Packages |
|------|----------|----------|
| 1 | **System** | All system packages via `apt upgrade` |
| 2 | **Video** | Mesa, Vulkan, Intel VA-API, `ubuntu-drivers` recommendations |
| 3 | **Audio** | PipeWire, ALSA, Intel SOF firmware |
| 4 | **Network** | Realtek Wi-Fi/Ethernet firmware, Bluetooth (BlueZ) |
| 5 | **Security & Firmware** | Kernel, `intel-microcode`, `thermald`, TPM tools, Lenovo firmware via `fwupd` |
| 6 | **Dev Tools** | `build-essential`, `libssl-dev`, `libreadline-dev`, `libsqlite3-dev`, `llvm`, `git`, `vim`, and more |
| 7 | **Docker** | Docker Engine, CLI, containerd, Buildx, Compose plugin |
| 8 | **Shell Setup** | Fish shell (set as default), Starship prompt, `config.fish`, `starship.toml` |
| 9 | **Homebrew + asdf** | Homebrew, asdf, Python 3.10.14, Node.js 24.14.0, aicommits |
| 10 | **Tools** | `gh` CLI (GitHub apt repo), Zed editor |
| 11 | **Cleanup** | Removes orphaned packages |

## Hardware

- **GPU:** Intel Iris Xe Graphics (TigerLake-LP GT2)
- **Audio:** Intel Tiger Lake-LP Smart Sound Technology
- **Network:** Realtek RTL8822BE (Wi-Fi/Bluetooth) + RTL8111 (Ethernet)
- **Firmware:** Managed via [fwupd](https://fwupd.org/) (Lenovo LVFS support)

## Usage

```bash
sudo ./update-drivers.sh
```

The script requires root privileges. It will prompt for a reboot at the end if one is needed.

## Requirements
- `fwupd` and `ubuntu-drivers` (pre-installed on Ubuntu Desktop)
