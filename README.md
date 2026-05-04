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
| 10 | **Fonts** | JetBrains Mono (all `.ttf` variants, including NL) |
| 11 | **Tools** | `gh` CLI (GitHub apt repo), Zed editor |
| 12 | **Cleanup** | Removes orphaned packages |

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
sudo ./update-drivers.sh
```

Using `git clone` preserves the execution permission of the script automatically.

### Via ZIP download

If you downloaded the repository as a `.zip` from GitHub, the execute bit **is not preserved**.
You need to grant it manually before running:

```bash
chmod +x update-drivers.sh
sudo ./update-drivers.sh
```

The script requires root privileges and will prompt for a reboot at the end if one is needed.

## Requirements

- `curl` (installed automatically by the script if missing)
- `fwupd` and `ubuntu-drivers` (pre-installed on Ubuntu Desktop)
