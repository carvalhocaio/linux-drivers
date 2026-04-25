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

### Recomendado: via `git clone`

```bash
git clone https://github.com/carvalhocaio/ubuntu-drivers.git
cd ubuntu-drivers
sudo ./update-drivers.sh
```

Usando `git clone`, a permissão de execução do script é preservada automaticamente.

### Via download ZIP

Se você baixou o repositório como `.zip` pelo GitHub, o bit de execução **não é preservado**.
É necessário concedê-lo manualmente antes de rodar:

```bash
chmod +x update-drivers.sh
sudo ./update-drivers.sh
```

O script requer privilégios de root e perguntará sobre reboot ao final, caso necessário.

## Requirements
- `curl` (instalado automaticamente pelo script caso ausente)
- `fwupd` e `ubuntu-drivers` (pré-instalados no Ubuntu Desktop)
