# Ubuntu Setup

Drivers, tuning and dev tooling for a **Lenovo ThinkPad E14 Gen 2** on **Ubuntu 26.04 LTS** (Resolute Raccoon).

Mirrors my NixOS [`configuration.nix`](https://gist.github.com/carvalhocaio/9d2138b94776737e3951bd0cb4a0b81e): every NixOS option becomes a drop-in file under `/etc`, so the script is idempotent and each change is easy to find and revert.

## Steps

| Step | What it does | NixOS equivalent |
|------|--------------|------------------|
| `base` | `apt full-upgrade`, universe/multiverse, base CLI (`ripgrep`, `fd`, `bat`, `eza`, `btop`, `lazygit`…) | `environment.systemPackages` |
| `boot` | `mem_sleep_default=deep`, blacklist `tiny_power_button`, rtw88 ASPM/LPS off | `boot.kernelParams`, `boot.blacklistedKernelModules`, `boot.extraModprobeConfig` |
| `memory` | zram (zstd, 50%), earlyoom (replaces `systemd-oomd`), `vm.*` sysctl, journald 500M, optional ananicy-cpp | `zramSwap`, `services.earlyoom`, `boot.kernel.sysctl`, `services.ananicy` |
| `network` | TCP BBR + CAKE, Wi-Fi powersave off | `boot.kernel.sysctl`, `networking.networkmanager.wifi.powersave` |
| `locale` | `en_US` + `pt_BR` LC_*, `America/Cuiaba`, `br` (ThinkPad) layout | `i18n`, `time.timeZone`, `services.xserver.xkb` |
| `desktop` | Purge GNOME apps with background SearchProviders, CUPS | `environment.gnome.excludePackages`, `services.printing` |
| `audio` | PipeWire quantum 1024 @ 48 kHz, pulse stability, USB headset autosuspend off | `services.pipewire.extraConfig`, `wireplumber.extraConfig` |
| `hardware` | Battery 75–80%, PL1/PL2 20 W / 28 W, power key → suspend, `thermald` masked, fwupd, fstrim | `systemd.tmpfiles.rules`, `services.logind`, `services.fwupd` |
| `graphics` | `intel-media-va-driver-non-free` (iHD), oneVPL, OpenCL, `LIBVA_DRIVER_NAME=iHD` | `hardware.graphics.extraPackages`, `environment.sessionVariables` |
| `docker` | Docker CE (rootful), Compose/Buildx plugins, weekly `docker system prune` | `virtualisation.docker` |
| `apps` | Chrome (VA-API flags), Claude Desktop, Warp, `gh`, `gcloud`, OBS, Spotify (snap) | overlays + `environment.systemPackages` |
| `dev_tools` | uv, ruff, Claude Code, OpenCode, Zed, lazydocker, rtk (pinned + sha256), gh-dash | `environment.systemPackages` |
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
| `ENABLE_ANANICY` | `0` | `1` installs [ananicy-debian](https://github.com/nilocnt/ananicy-debian) (ananicy-cpp + CachyOS rules). Unofficial package — nothing equivalent in the Ubuntu archive. |

```bash
sudo ENABLE_ANANICY=1 ./setup.sh memory
```

## Where things land

| Path | Step |
|------|------|
| `/etc/default/grub.d/90-thinkpad.cfg` | `boot` |
| `/etc/modprobe.d/90-*.conf` | `boot` |
| `/etc/sysctl.d/90-{memory,network}.conf` | `memory`, `network` |
| `/etc/systemd/zram-generator.conf` | `memory` |
| `/etc/NetworkManager/conf.d/99-wifi-powersave-off.conf` | `network` |
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
- **thermald** is masked on purpose: `thinkpad_acpi` exposes DYTC (`dytc_lapmode`) and thermald refuses to run alongside it.
- `locale`, `fonts` and `wallpaper` call `gsettings`, so run them from a logged-in GNOME session; otherwise they warn and skip that part.
- `gh-dash` needs `gh auth login` first.
- Coming from the previous Homebrew/asdf version? Fish now comes from apt (`/usr/bin/fish`), Python is managed by `uv` and Node by apt. Remove Homebrew with its uninstall script once you've checked nothing depends on it.

## Hardware

- **CPU/GPU:** Intel Core (Tiger Lake) · Iris Xe Graphics (TigerLake-LP GT2)
- **Audio:** Intel Tiger Lake-LP Smart Sound Technology (SOF)
- **Network:** Realtek RTL8822BE (Wi-Fi/Bluetooth) + RTL8111 (Ethernet)
- **Firmware:** [fwupd](https://fwupd.org/) (Lenovo LVFS)
