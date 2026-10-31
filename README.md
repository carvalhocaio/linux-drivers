# Ubuntu Setup

Drivers, tuning and dev tooling for a **Lenovo ThinkPad E14 Gen 2** on **Ubuntu 26.04 LTS** (Resolute Raccoon).

Mirrors my NixOS [`configuration.nix`](https://gist.github.com/carvalhocaio/9d2138b94776737e3951bd0cb4a0b81e): every NixOS option becomes a drop-in file under `/etc`, so the script is idempotent and each change is easy to find and revert.

## Steps

| Step | What it does | NixOS equivalent |
|------|--------------|------------------|
| `base` | `apt full-upgrade`, universe/multiverse, base CLI (`ripgrep`, `fd`, `bat`, `eza`, `btop`, `lazygit`…) | `environment.systemPackages` |
| `boot` | `mem_sleep_default=deep`, `pcie_aspm=off`, blacklist `tiny_power_button`, rtw88 ASPM (incl. BIOS-enabled L1 substates)/LPS/MSI off, no D3cold + auto-recovery watchdog | `boot.kernelParams`, `boot.blacklistedKernelModules`, `boot.extraModprobeConfig` |
| `memory` | zram (zstd, 50%), earlyoom (replaces `systemd-oomd`), `vm.*` sysctl, journald 500M, ananicy-cpp + CachyOS rules | `zramSwap`, `services.earlyoom`, `boot.kernel.sysctl`, `services.ananicy` |
| `network` | TCP BBR + CAKE, Wi-Fi powersave off | `boot.kernel.sysctl`, `networking.networkmanager.wifi.powersave` |
| `locale` | `en_US` + `pt_BR` LC_*, `America/Cuiaba`, `br` (ThinkPad) layout | `i18n`, `time.timeZone`, `services.xserver.xkb` |
| `desktop` | Purge GNOME apps with background SearchProviders, CUPS | `environment.gnome.excludePackages`, `services.printing` |
| `audio` | PipeWire quantum 1024 @ 48 kHz, pulse stability, USB headset autosuspend off | `services.pipewire.extraConfig`, `wireplumber.extraConfig` |
| `hardware` | Microcode, battery 75–80%, PL1/PL2 20 W / 38 W, power key → suspend, `thermald` masked, fstrim | `systemd.tmpfiles.rules`, `services.logind` |
| `firmware` | Shows current BIOS, refreshes LVFS, lists updates and flashes interactively (AC power required) | `services.fwupd` |
| `graphics` | `intel-media-va-driver-non-free` (iHD), oneVPL, OpenCL, `LIBVA_DRIVER_NAME=iHD` | `hardware.graphics.extraPackages`, `environment.sessionVariables` |
| `docker` | Docker CE (rootful), Compose/Buildx plugins, weekly `docker system prune` | `virtualisation.docker` |
| `apps` | Chrome (VA-API flags), Claude Desktop, Warp, `gh`, `gcloud`, OBS, Spotify (snap) | overlays + `environment.systemPackages` |
| `dev_tools` | uv, ruff, Claude Code, OpenCode, Zed, lazydocker, rtk (pinned + sha256), gh-dash | `environment.systemPackages` |
| `languages` | [asdf](https://asdf-vm.com) 0.19.0 (Go binary, pinned + sha256), Python 3.11.16, Node.js 24.14.0, pnpm via corepack | — (devshells/direnv on NixOS) |
| `git` | `--global` identity, `pull.rebase`, `push.autoSetupRemote` | `programs.git` |
| `shell` | fish as login shell, aliases, Starship, direnv hook | `programs.fish`, `programs.starship`, `programs.direnv` |
| `fonts` | JetBrains Mono, JetBrainsMono + Terminess Nerd Fonts, Noto + emoji | `fonts.packages`, `fontconfig.defaultFonts` |
| `wallpaper` | `assets/wallpapers/red_distortion_3.jpg` (`zoom`) | — |
| `cleanup` | `apt autoremove --purge` + `autoclean` | `nix.gc` |

Pre-selected in the interactive menu: `base boot memory network audio hardware graphics`.

## Usage

```bash
git clone https://github.com/carvalhocaio/linux-drivers.git
cd linux-drivers
sudo ./setup.sh                 # interactive selector
sudo ./setup.sh audio shell     # specific steps, no menu
./setup.sh --list
```

Selector keys: `↑/↓` move · `Space` toggle · `Enter` run · `a` toggle all · `q` quit.

Downloaded as `.zip`? The execute bit is lost — run `chmod +x setup.sh` first.

### Options

| Variable | Default | Effect |
|----------|---------|--------|
| `ENABLE_ANANICY` | `1` | Installs [ananicy-debian](https://github.com/nilocnt/ananicy-debian) (ananicy-cpp + CachyOS rules): background builds, Node, Docker and indexers get lower priority than audio, video and the browser. Unofficial package — nothing equivalent in the Ubuntu archive. `0` skips it. |
| `PL1_WATTS` | `20` | Sustained CPU power limit. |
| `PL2_WATTS` | `38` | Short-burst (turbo) power limit. |

```bash
sudo PL2_WATTS=35 ./setup.sh hardware      # tune limits
sudo ENABLE_ANANICY=0 ./setup.sh memory    # skip ananicy
```

## Where things land

| Path | Step |
|------|------|
| `/etc/default/grub.d/90-thinkpad.cfg` | `boot` |
| `/etc/modprobe.d/90-*.conf` | `boot` |
| `/usr/local/sbin/rtw88-watchdog`, `/etc/systemd/system/rtw88-watchdog.service`, `/usr/local/sbin/rtw88-aspm-off`, `/usr/lib/systemd/system-sleep/rtw88-aspm-off`, `/etc/udev/rules.d/90-rtw88-pm.rules` | `boot` |
| `/etc/sysctl.d/90-{memory,network}.conf` | `memory`, `network` |
| `/etc/systemd/zram-generator.conf` | `memory` |
| `/etc/NetworkManager/conf.d/zz-wifi-powersave-off.conf` | `network` |
| `/etc/pipewire/**/92-*.conf`, `/etc/wireplumber/wireplumber.conf.d/51-*.conf` | `audio` |
| `/etc/tmpfiles.d/90-thinkpad-power.conf` | `hardware` |
| `/etc/systemd/logind.conf.d/90-power-key.conf` | `hardware` |
| `/etc/environment.d/90-vaapi.conf` | `graphics` |
| `/etc/systemd/system/docker-prune.{service,timer}` | `docker` |
| `~/.config/fish/conf.d/{10-env,20-aliases,90-tools}.fish` | `shell` |
| `~/.local/share/applications/google-chrome.desktop` | `apps` |

To revert a change: delete its file and reboot.

## Notes

- **Reboot** after `boot`, `memory`, `hardware`, `graphics` and `docker` (kernel params, logind, zram, groups, `environment.d`).
- **Power profile:** stay on *Balanced*. *Performance* raises PL1 to 35 W / 64 W and hits 92 °C.
- **Wi-Fi (RTL8822BE):** the rtw88 firmware can hang (`failed to send h2c command`, then `failed to leave ips state`), leaving the adapter unresponsive and hiding all networks until reboot. Root cause: the BIOS enables PCIe ASPM L0s/L1 plus the L1.1/L1.2 substates on the card and its root port, and neither `pcie_aspm=off` (which only keeps the kernel from managing ASPM) nor `rtw88_pci disable_aspm=Y` clears them. `rtw88-aspm-off` clears them with `setpci`, run from the udev rule and after resume; verify with `sudo lspci -vvv -s 04:00.0 | grep -E 'LnkCtl:|L1SubCtl1'` (expect `ASPM Disabled` and all `-`). Other mitigations: `pcie_aspm=off`, `rtw88_pci disable_aspm=Y disable_msi=Y`, `rtw88_core disable_lps_deep=Y`, and a udev rule that keeps the card and its root port out of D3cold (from which it never returns to D0). `rtw88-watchdog.service` resets the card when it sees a burst of h2c failures or `mac power on failed`: unload → PCI function reset → reload, escalating to remove + rescan; it verifies the interface actually came back. Check it with `systemctl status rtw88-watchdog` and `journalctl -t rtw88-watchdog`. If it logs `recovery failed`, reboot. Revert by disabling the unit, removing the udev rule and `pcie_aspm=off` from the boot step.
- **Validate PL2:** run a heavy build or `stress-ng --cpu 8 --timeout 120` while watching `s-tui`. Below ~90 °C, keep it; otherwise lower `PL2_WATTS`.
- **Firmware:** `firmware` is not pre-selected because flashing should be a deliberate choice. It refuses to flash on battery and lets fwupd ask before each update. If LVFS has nothing for the device, use Lenovo's *BIOS Update Utility (Bootable CD)* for E14/E15 Gen 2.
- **thermald** is masked on purpose: `thinkpad_acpi` exposes DYTC (`dytc_lapmode`) and thermald refuses to run alongside it.
- `locale`, `fonts` and `wallpaper` call `gsettings`, so run them from a logged-in GNOME session; otherwise they warn and skip that part.
- `gh-dash` needs `gh auth login` first.
- **asdf without Homebrew:** since 0.16 asdf is a single Go binary, so it goes straight to `/usr/local/bin`. Existing `.tool-versions` files and `~/.asdf` installs keep working. Versions are pinned at the top of `setup.sh` (`PYTHON_VERSION`, `NODE_VERSION`).
- **uv and asdf coexist:** asdf owns the interpreters, uv handles project venvs and tools (`ruff`).
- Coming from the previous Homebrew version? Fish now comes from apt (`/usr/bin/fish`). Remove Homebrew with its uninstall script once you've checked nothing depends on it.

## Hardware

- **Model:** 20TB000LBO · BIOS R1EET (1.62 as of 2024-07)
- **CPU:** Intel Core i7-1165G7 (4C/8T, up to 4.7 GHz)
- **Memory:** 32 GB DDR4-3200, single SO-DIMM (single channel)
- **GPU:** Intel Iris Xe (TigerLake-LP GT2) — runs as UHD-class in single channel
- **Storage:** Samsung 980 NVMe 250 GB
- **Audio:** Intel Tiger Lake-LP Smart Sound Technology (SOF)
- **Network:** Realtek RTL8822BE (Wi-Fi/Bluetooth) + RTL8111 (Ethernet)
- **Firmware:** [fwupd](https://fwupd.org/) (Lenovo LVFS)
