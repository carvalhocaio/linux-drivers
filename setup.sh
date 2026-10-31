#!/usr/bin/env bash
# Ubuntu 26.04 LTS (Resolute Raccoon) — Lenovo ThinkPad E14 Gen 2 (Tiger Lake / Iris Xe)
# Mirrors the NixOS configuration: gist.github.com/carvalhocaio/9d2138b94776737e3951bd0cb4a0b81e
#
#   sudo ./setup.sh                  # interactive step selector
#   sudo ./setup.sh audio shell      # run the given steps only
#   ./setup.sh --list                # list steps
#
# Idempotent: each step (re)writes its own drop-in files. Rollback = delete the drop-in and reboot.

set -Eeuo pipefail

readonly STEPS=(
    "base|System upgrade + base CLI"
    "boot|Kernel params & modules (S3 sleep, power button, rtw88 + watchdog)"
    "memory|Memory (zram, earlyoom, sysctl, journald, ananicy)"
    "network|Network (Wi-Fi powersave off, TCP BBR + CAKE)"
    "locale|Locale, timezone, keyboard (br-thinkpad)"
    "desktop|GNOME cleanup + printing"
    "audio|PipeWire low-latency + USB headset autosuspend"
    "hardware|Microcode, battery thresholds, CPU power limits, logind"
    "firmware|BIOS/EC/device firmware via fwupd (LVFS), interactive"
    "graphics|Intel VA-API / QuickSync / OpenCL"
    "docker|Docker Engine (rootful) + weekly prune"
    "apps|Chrome, Claude Desktop, Warp, gh, gcloud, OBS, Spotify"
    "dev_tools|uv, ruff, Claude Code, OpenCode, Zed, lazydocker, rtk, gh-dash"
    "languages|asdf + Python, Node.js (pnpm via corepack)"
    "git|Git config"
    "shell|Fish + Starship + direnv"
    "fonts|JetBrains Mono, Nerd Fonts, Noto"
    "wallpaper|GNOME wallpaper"
    "cleanup|Remove orphaned packages and caches"
)
readonly DEFAULT_STEPS=(base boot memory network audio hardware graphics)

# PL1 = sustained, PL2 = short turbo bursts. Validate thermals with s-tui under load (target < 90°C).
readonly PL1_WATTS="${PL1_WATTS:-20}"
readonly PL2_WATTS="${PL2_WATTS:-38}"

readonly TIMEZONE="America/Cuiaba"
readonly GIT_NAME="Caio Carvalho"
readonly GIT_EMAIL="caiocarvalho.py@gmail.com"
readonly GIT_USERNAME="carvalhocaio"

readonly ASDF_VERSION="0.19.0"
readonly ASDF_SHA256="f6aa14de1348c9a85f3095f79792a5cd04305c466e6458c69a36a1621cd729ef"
readonly PYTHON_VERSION="3.11.16"
readonly NODE_VERSION="24.14.0"

readonly RTK_VERSION="1.0.1"
readonly RTK_SHA256="5b919c3bccb799b67a61866d0e617410a4fcdf173e2614440e59de2fa2003436"

# Unofficial .deb (ananicy-cpp + CachyOS rules) — not in the Ubuntu archive.
readonly ENABLE_ANANICY="${ENABLE_ANANICY:-1}"
readonly ANANICY_DEB_URL="https://github.com/nilocnt/ananicy-debian/releases/download/v1.2.48-2/ananicy-debian_1.2.48-2_amd64.deb"

readonly CHROME_FLAGS="--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks --ignore-gpu-blocklist --enable-zero-copy"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly WALLPAPER_PATH="${SCRIPT_DIR}/assets/wallpapers/red_distortion_3.jpg"

# ─── output ─────────────────────────────────────────────────────────────────

readonly GREEN='\033[0;32m' YELLOW='\033[1;33m' RED='\033[0;31m' NC='\033[0m'

info() { echo -e "${GREEN}[✔]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
die() { echo -e "${RED}[✘]${NC} $*" >&2; exit 1; }
header() {
    local rule="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "\n${GREEN}${rule}\n $*\n${rule}${NC}\n"
}

trap 'die "line ${LINENO}: ${BASH_COMMAND}"' ERR

# ─── helpers ────────────────────────────────────────────────────────────────

write_file() { install -Dm"${2:-0644}" /dev/stdin "$1"; }
# Stdin is a root-owned pipe the user can't reopen via /dev/stdin; cat reads the inherited fd instead.
user_write() { sudo -u "$TARGET_USER" sh -c 'cat | install -Dm"$1" /dev/stdin "$2"' sh "${2:-0644}" "$1"; }

as_user() {
    sudo -u "$TARGET_USER" -H env \
        PATH="${TARGET_HOME}/.asdf/shims:${TARGET_HOME}/.local/bin:${TARGET_HOME}/.opencode/bin:/usr/local/bin:/usr/bin:/bin" \
        XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
        "$@"
}

has_session_bus() { [[ -S /run/user/${TARGET_UID}/bus ]]; }
user_has() { as_user bash -c "command -v $1" &>/dev/null; }
has_unit() { systemctl cat "$1" &>/dev/null; }
is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

download() { curl -fsSL --retry 3 -o "$2" "$1"; }

apt_install() { DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }

apt_install_available() {
    local available=() pkg
    for pkg in "$@"; do
        if apt-cache show "$pkg" &>/dev/null; then
            available+=("$pkg")
        else
            warn "Not in the archive, skipped: ${pkg}"
        fi
    done
    if ((${#available[@]})); then
        apt_install "${available[@]}"
    fi
}

apt_purge_installed() {
    local installed=() pkg
    for pkg in "$@"; do
        is_installed "$pkg" && installed+=("$pkg")
    done
    if ((${#installed[@]})); then
        DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove "${installed[@]}"
    fi
}

add_apt_repo() {
    local name=$1 key_url=$2 entry=$3
    local keyring="/etc/apt/keyrings/${name}.gpg"
    local key="${WORKDIR}/${name}.key"

    install -d -m 0755 /etc/apt/keyrings
    download "$key_url" "$key"
    if grep -q 'BEGIN PGP' "$key"; then
        gpg --dearmor --yes -o "$keyring" "$key"
    else
        install -m 0644 "$key" "$keyring"
    fi
    chmod 0644 "$keyring"

    write_file "/etc/apt/sources.list.d/${name}.list" <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] ${entry}
EOF
}

mask_unit() {
    has_unit "$1" || return 0
    systemctl disable --now "$@" 2>/dev/null || true
    systemctl mask "$@"
}

regenerate_initramfs() {
    if command -v update-initramfs &>/dev/null; then
        update-initramfs -u -k all
    elif command -v dracut &>/dev/null; then
        dracut --regenerate-all --force
    fi
}

gnome_set() {
    if has_session_bus; then
        as_user gsettings set "$@"
    else
        warn "No GNOME session for ${TARGET_USER}; log in graphically and re-run: gsettings set $*"
    fi
}

# ─── steps ──────────────────────────────────────────────────────────────────

step_base() {
    apt-get update
    apt_install ca-certificates curl gpg software-properties-common
    add-apt-repository -y universe
    add-apt-repository -y multiverse
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y

    apt_install \
        vim wget unzip make build-essential usbutils pciutils lm-sensors powertop btop \
        jq ripgrep fd-find bat direnv fish neovim git
    apt_install_available eza starship lazygit
    info "Base system ready"
}

step_boot() {
    # Real S3 (deep) instead of s2idle: no spurious wakes or ACPI lid bugs.
    # pcie_aspm=off only stops the kernel from *managing* ASPM: whatever the BIOS
    # enabled stays on. rtw88-aspm-off (below) clears it on the Wi-Fi link, and
    # with the kernel hands-off nothing re-enables it afterwards.
    write_file /etc/default/grub.d/90-thinkpad.cfg <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} mem_sleep_default=deep pcie_aspm=off"
EOF

    # tiny_power_button sends SIGRTMIN+4 (instant poweroff) to PID 1;
    # the regular 'button' driver lets logind/GNOME suspend instead.
    write_file /etc/modprobe.d/90-thinkpad-power-button.conf <<'EOF'
blacklist tiny_power_button
EOF

    # Realtek rtw88_8822be: aggressive PCIe ASPM/LPS causes IRQ spikes and call drops.
    # disable_msi: with MSI the firmware intermittently stops acking H2C commands
    # ("failed to send h2c command" + beacon loss) after ~20 min; legacy INTx avoids it.
    write_file /etc/modprobe.d/90-rtw88-stability.conf <<'EOF'
options rtw88_pci disable_aspm=Y disable_msi=Y
options rtw88_core disable_lps_deep=Y
EOF

    # The root cause of the firmware hangs: the BIOS enables ASPM L0s/L1 and the
    # L1.1/L1.2 substates on the card and its root port, and neither pcie_aspm=off
    # nor rtw88_pci.disable_aspm turns them off (check: lspci -vvv -s 04:00.0,
    # LnkCtl / L1SubCtl1). Clear them by hand: ASPM L0s/L1 first (card, then
    # port), then the L1 substates. Re-run after S3, where the BIOS may re-arm them.
    write_file /usr/local/sbin/rtw88-aspm-off 0755 <<'EOF'
#!/bin/sh
# Disable PCIe ASPM (L0s, L1, L1.1, L1.2) on the RTL8822BE and its root port.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
for d in /sys/bus/pci/devices/*; do
    [ "$(cat "$d/vendor"):$(cat "$d/device")" = "0x10ec:0xb822" ] || continue
    dev=$(basename "$d")
    port=$(basename "$(readlink -f "$d/..")")
    for s in "$dev" "$port"; do setpci -s "$s" CAP_EXP+10.w=0:3; done
    for s in "$dev" "$port"; do setpci -s "$s" ECAP_L1PM+8.l=0:f 2>/dev/null || true; done
    logger -t rtw88-aspm-off "ASPM disabled on ${dev} and ${port}"
done
EOF
    write_file /usr/lib/systemd/system-sleep/rtw88-aspm-off 0755 <<'EOF'
#!/bin/sh
[ "$1" = post ] && exec /usr/local/sbin/rtw88-aspm-off
exit 0
EOF

    # Never let the card (or its root port) drop to D3cold: once it does, the
    # RTL8822BE can't return to D0 ("Unable to change power state from D3cold
    # to D0") and only a reboot brings Wi-Fi back.
    write_file /etc/udev/rules.d/90-rtw88-pm.rules <<'EOF'
ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10ec", ATTR{device}=="0xb822", ATTR{power/control}="on", ATTR{d3cold_allowed}="0", RUN+="/bin/sh -c 'echo on > /sys%p/../power/control; echo 0 > /sys%p/../d3cold_allowed'", RUN+="/usr/local/sbin/rtw88-aspm-off"
EOF
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=pci --attr-match=vendor=0x10ec --attr-match=device=0xb822 2>/dev/null || true

    # Even with the options above the firmware can hang ("failed to send h2c
    # command", "failed to leave ips state"), silencing the card and hiding every
    # network until reboot. This watchdog resets the card automatically instead.
    write_file /usr/local/sbin/rtw88-watchdog 0755 <<'EOF'
#!/usr/bin/env bash
# Auto-recover the RTL8822BE when its firmware hangs.
# Symptoms: a burst of "failed to send h2c command", then "mac power on failed" /
# "failed to leave ips state", then "no networks found" until reboot.
set -uo pipefail

readonly DRIVER=rtw88_8822be
readonly PCI_ID=10ec:b822
readonly HANG_RE='failed to leave ips state|mac power on failed|failed to power on mac|failed to setup chip'
readonly H2C_RE='failed to send h2c command'
readonly H2C_BURST=6     # h2c failures within H2C_WINDOW seconds = hung firmware
readonly H2C_WINDOW=30
readonly COOLDOWN=60

log() { printf 'rtw88-watchdog: %s\n' "$*"; }

find_dev() {
    local d
    for d in /sys/bus/pci/devices/*; do
        [[ $(<"$d/vendor"):$(<"$d/device") == 0x${PCI_ID%%:*}:0x${PCI_ID##*:} ]] && { basename "$d"; return 0; }
    done
    return 1
}

# Keep the card and its root port out of runtime suspend / D3cold.
pin_power() {
    local dev=$1 path
    for path in "/sys/bus/pci/devices/${dev}" "$(readlink -f "/sys/bus/pci/devices/${dev}/..")"; do
        [[ -w ${path}/power/control ]] && echo on > "${path}/power/control"
        [[ -w ${path}/d3cold_allowed ]] && echo 0 > "${path}/d3cold_allowed"
    done
}

# modprobe exits 0 even when probe fails, so check the device really came up.
card_up() {
    local dev=$1 i
    for i in {1..10}; do
        [[ -e /sys/bus/pci/devices/${dev}/driver ]] &&
            compgen -G "/sys/bus/pci/devices/${dev}/net/*" >/dev/null && return 0
        sleep 1
    done
    return 1
}

# modprobe -r also drops rtw88_8822b/rtw88_pci/rtw88_core once unused.
unload() { timeout 20 modprobe -r "$DRIVER" >/dev/null 2>&1 || true; }

recover() {
    local dev iface
    dev=$(find_dev) || { log "RTL8822BE not on the PCI bus; rescanning"; echo 1 > /sys/bus/pci/rescan; sleep 3; dev=$(find_dev) || return; }
    iface=$(basename "$(compgen -G "/sys/bus/pci/devices/${dev}/net/*" | head -1)" 2>/dev/null)

    log "firmware hang detected on ${dev}; resetting card"
    # A wedged card can make NetworkManager/modprobe block in D-state: cap them.
    [[ -n ${iface:-} ]] && timeout 10 nmcli device disconnect "$iface" >/dev/null 2>&1
    pin_power "$dev"
    unload

    # Step 1: function-level reset (secondary bus reset) with no driver bound.
    pin_power "$dev"
    [[ -w /sys/bus/pci/devices/${dev}/reset ]] && timeout 10 sh -c "echo 1 > /sys/bus/pci/devices/${dev}/reset" 2>/dev/null
    sleep 1
    timeout 20 modprobe "$DRIVER" >/dev/null 2>&1
    if card_up "$dev"; then log "recovered after PCI reset"; return; fi

    # Step 2: drop the device from the bus and rediscover it.
    log "reset not enough; removing and rescanning PCI device"
    unload
    local bridge
    bridge=$(readlink -f "/sys/bus/pci/devices/${dev}/..")
    echo 1 > "/sys/bus/pci/devices/${dev}/remove"
    sleep 2
    if [[ -w ${bridge}/rescan ]]; then echo 1 > "${bridge}/rescan"; else echo 1 > /sys/bus/pci/rescan; fi
    sleep 2
    dev=$(find_dev) && pin_power "$dev"
    timeout 20 modprobe "$DRIVER" >/dev/null 2>&1
    if [[ -n ${dev:-} ]] && card_up "$dev"; then log "recovered after PCI rescan"; return; fi

    log "recovery failed; reboot to bring the card back"
}

if dev=$(find_dev); then pin_power "$dev"; fi

last=0
h2c=()
journalctl -k -f -n 0 -o cat |
while IFS= read -r line; do
    now=$(date +%s)
    if [[ $line =~ $H2C_RE ]]; then
        h2c+=("$now")
        while (( ${#h2c[@]} && now - h2c[0] > H2C_WINDOW )); do h2c=("${h2c[@]:1}"); done
        (( ${#h2c[@]} >= H2C_BURST )) || continue
    elif ! [[ $line =~ $HANG_RE ]]; then
        continue
    fi
    (( now - last < COOLDOWN )) && continue
    last=$now
    h2c=()
    recover
done
EOF

    write_file /etc/systemd/system/rtw88-watchdog.service <<'EOF'
[Unit]
Description=Auto-recover hung Realtek rtw88 Wi-Fi firmware
After=NetworkManager.service
StartLimitIntervalSec=0

[Service]
Type=simple
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SyslogIdentifier=rtw88-watchdog
ExecStart=/usr/local/sbin/rtw88-watchdog
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now rtw88-watchdog.service

    regenerate_initramfs
    if command -v update-grub &>/dev/null; then
        update-grub
    else
        warn "update-grub not found; add mem_sleep_default=deep pcie_aspm=off to your bootloader manually"
    fi
    info "Kernel params, module options and rtw88 watchdog set (reboot required)"
}

step_memory() {
    write_file /etc/sysctl.d/90-memory.conf <<'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
    sysctl --system >/dev/null

    # zram even with 32GB: avoids freezes under load.
    apt_purge_installed zram-tools
    apt_install systemd-zram-generator
    write_file /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
    systemctl daemon-reload
    systemctl restart systemd-zram-setup@zram0.service || warn "zram will be active after reboot"

    # A single OOM killer: earlyoom replaces systemd-oomd.
    mask_unit systemd-oomd.service systemd-oomd.socket
    apt_install earlyoom
    write_file /etc/default/earlyoom <<'EOF'
EARLYOOM_ARGS="-m 5 -s 10 -r 3600"
EOF
    systemctl enable earlyoom
    systemctl restart earlyoom

    write_file /etc/systemd/journald.conf.d/90-size.conf <<'EOF'
[Journal]
SystemMaxUse=500M
EOF
    systemctl restart systemd-journald

    if [[ $ENABLE_ANANICY == 1 ]]; then
        local deb="${WORKDIR}/ananicy.deb"
        download "$ANANICY_DEB_URL" "$deb"
        apt_install "$deb"
        systemctl enable --now ananicy-cpp.service
    else
        warn "ananicy-cpp skipped (ENABLE_ANANICY=0)"
    fi
    info "zram, earlyoom and journald configured"
}

step_network() {
    write_file /etc/sysctl.d/90-network.conf <<'EOF'
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr
EOF
    write_file /etc/modules-load.d/90-network.conf <<'EOF'
tcp_bbr
sch_cake
EOF
    modprobe tcp_bbr
    modprobe sch_cake
    sysctl --system >/dev/null

    # Ubuntu ships wifi.powersave=3 (default-wifi-powersave-on.conf); zz- sorts after it, digits would not.
    rm -f /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf
    write_file /etc/NetworkManager/conf.d/zz-wifi-powersave-off.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF
    systemctl reload NetworkManager
    apt_install bluez
    info "BBR + CAKE active, Wi-Fi powersave off"
}

step_locale() {
    locale-gen en_US.UTF-8 pt_BR.UTF-8
    update-locale \
        LANG=en_US.UTF-8 \
        LC_ADDRESS=pt_BR.UTF-8 \
        LC_IDENTIFICATION=pt_BR.UTF-8 \
        LC_MEASUREMENT=pt_BR.UTF-8 \
        LC_MONETARY=pt_BR.UTF-8 \
        LC_NAME=pt_BR.UTF-8 \
        LC_NUMERIC=pt_BR.UTF-8 \
        LC_PAPER=pt_BR.UTF-8 \
        LC_TELEPHONE=pt_BR.UTF-8 \
        LC_TIME=en_US.UTF-8
    timedatectl set-timezone "$TIMEZONE"

    write_file /etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="br"
XKBVARIANT="thinkpad"
XKBOPTIONS=""
BACKSPACE="guess"
EOF
    gnome_set org.gnome.desktop.input-sources sources "[('xkb', 'br+thinkpad')]"
    info "Locale, timezone and keyboard set"
}

step_desktop() {
    # Apps that run GNOME SearchProviders in the background for nothing.
    apt_purge_installed epiphany-browser geary gnome-tour gnome-music gnome-contacts
    apt_install cups
    systemctl enable --now cups.service
    info "GNOME trimmed, printing enabled"
}

step_audio() {
    apt_install pipewire-audio wireplumber rtkit alsa-utils linux-firmware
    apt_install_available firmware-sof-signed

    # Keeps Meet/Teams audio from crackling when the CPU is under load.
    write_file /etc/pipewire/pipewire.conf.d/92-low-latency-stability.conf <<'EOF'
context.properties = {
    default.clock.rate        = 48000
    default.clock.quantum     = 1024
    default.clock.min-quantum = 512
    default.clock.max-quantum = 2048
}
EOF
    write_file /etc/pipewire/pipewire-pulse.conf.d/92-pulse-stability.conf <<'EOF'
pulse.properties = {
    pulse.min.req     = 512/48000
    pulse.default.req = 1024/48000
    pulse.min.quantum = 512/48000
}
EOF
    # USB headsets (e.g. Logitech) must never be suspended mid-call.
    write_file /etc/wireplumber/wireplumber.conf.d/51-disable-usb-autosuspend.conf <<'EOF'
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "~alsa_input.usb-*" }
      { node.name = "~alsa_output.usb-*" }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
EOF
    if has_session_bus; then
        as_user systemctl --user restart wireplumber pipewire pipewire-pulse \
            || warn "Audio stack picks up the changes after re-login"
    fi
    info "PipeWire tuned"
}

step_hardware() {
    apt_install linux-firmware intel-microcode tpm2-tools
    systemctl enable --now fstrim.timer

    # thinkpad_acpi exposes DYTC (dytc_lapmode); thermald refuses to run alongside it.
    mask_unit thermald.service

    # Battery 75–80%; PL1 capped to avoid 100°C throttling in calls, PL2 kept for snappy bursts.
    local pl1_uw=$((PL1_WATTS * 1000000)) pl2_uw=$((PL2_WATTS * 1000000))
    write_file /etc/tmpfiles.d/90-thinkpad-power.conf <<EOF
w- /sys/class/power_supply/BAT0/charge_control_start_threshold - - - - 75
w- /sys/class/power_supply/BAT0/charge_control_end_threshold - - - - 80
w- /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw - - - - ${pl1_uw}
w- /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw - - - - ${pl2_uw}
w- /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw - - - - ${pl1_uw}
w- /sys/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw - - - - ${pl2_uw}
EOF
    systemd-tmpfiles --create /etc/tmpfiles.d/90-thinkpad-power.conf \
        || warn "Some power knobs are missing on this kernel"

    write_file /etc/systemd/logind.conf.d/90-power-key.conf <<'EOF'
[Login]
HandlePowerKey=suspend
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
EOF

    # "Performance" raises PL1 to 35W/64W and hits 92°C; stay on Balanced.
    if command -v powerprofilesctl &>/dev/null; then
        powerprofilesctl set balanced || true
    fi

    info "Microcode, battery and power limits configured (PL1 ${PL1_WATTS}W / PL2 ${PL2_WATTS}W)"
}

on_ac_power() {
    local supply
    for supply in /sys/class/power_supply/*; do
        [[ $(cat "${supply}/type" 2>/dev/null) == Mains && $(cat "${supply}/online" 2>/dev/null) == 1 ]] && return 0
    done
    return 1
}

step_firmware() {
    apt_install fwupd
    systemctl enable --now fwupd-refresh.timer 2>/dev/null || true
    info "Current BIOS: $(cat /sys/class/dmi/id/bios_version) ($(cat /sys/class/dmi/id/bios_date))"

    if ! fwupdmgr refresh --force; then
        warn "LVFS refresh failed; check 'fwupdmgr get-remotes' or use Lenovo's BIOS bootable ISO"
        return
    fi

    local status=0
    fwupdmgr get-updates || status=$?
    case $status in
        0) ;;
        2) info "Firmware is up to date"; return ;;
        *) warn "fwupdmgr get-updates failed (exit ${status}); try 'fwupdmgr get-updates --verbose'"; return ;;
    esac

    if ! on_ac_power; then
        warn "Plug in the charger before flashing firmware; skipping update"
        return
    fi
    if [[ ! -t 0 ]]; then
        warn "No TTY: run 'sudo fwupdmgr update' yourself to review and apply"
        return
    fi

    # Interactive on purpose: fwupd shows each update and asks before flashing and rebooting.
    fwupdmgr update || warn "Firmware update did not complete"
}

step_graphics() {
    apt_install_available \
        intel-media-va-driver-non-free libvpl2 libmfx-gen1.2 libmfx-gen1 \
        intel-opencl-icd intel-gpu-tools mesa-utils vainfo ffmpeg

    write_file /etc/environment.d/90-vaapi.conf <<'EOF'
LIBVA_DRIVER_NAME=iHD
EOF
    usermod -aG render,video "$TARGET_USER"
    info "Hardware video acceleration ready (relogin required)"
}

step_docker() {
    apt_purge_installed docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc
    rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc

    add_apt_repo docker https://download.docker.com/linux/ubuntu/gpg \
        "https://download.docker.com/linux/ubuntu ${CODENAME} stable"
    apt-get update
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker.service

    # Rootful: the "docker" group keeps testcontainers, devcontainers and bind mounts frictionless.
    usermod -aG docker "$TARGET_USER"

    write_file /etc/systemd/system/docker-prune.service <<'EOF'
[Unit]
Description=Prune unused Docker data
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker system prune -f
EOF
    write_file /etc/systemd/system/docker-prune.timer <<'EOF'
[Unit]
Description=Weekly Docker prune

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now docker-prune.timer
    info "Docker installed (relogin required for the docker group)"
}

install_chrome() {
    if ! is_installed google-chrome-stable; then
        local deb="${WORKDIR}/google-chrome.deb"
        download https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb "$deb"
        apt_install "$deb"
    fi

    # VA-API/QuickSync for WebRTC (Meet/Teams) via a user-level launcher, so Chrome updates don't revert it.
    sed "s|^Exec=/usr/bin/google-chrome-stable|Exec=/usr/bin/google-chrome-stable ${CHROME_FLAGS}|" \
        /usr/share/applications/google-chrome.desktop \
        | user_write "${TARGET_HOME}/.local/share/applications/google-chrome.desktop"
}

add_claude_desktop_repo() {
    local keyring=/usr/share/keyrings/claude-desktop-archive-keyring.asc
    download https://downloads.claude.ai/claude-desktop/key.asc "$keyring"
    chmod 0644 "$keyring"
    write_file /etc/apt/sources.list.d/claude-desktop.list <<EOF
deb [signed-by=${keyring}] https://downloads.claude.ai/claude-desktop/apt/stable stable main
EOF
}

step_apps() {
    add_claude_desktop_repo
    add_apt_repo warpdotdev https://releases.warp.dev/linux/keys/warp.asc \
        "https://releases.warp.dev/linux/deb stable main"
    rm -f /etc/apt/keyrings/githubcli-archive-keyring.gpg
    add_apt_repo github-cli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        "https://cli.github.com/packages stable main"
    add_apt_repo google-cloud-sdk https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        "https://packages.cloud.google.com/apt cloud-sdk main"
    apt-get update

    apt_install claude-desktop warp-terminal gh google-cloud-cli obs-studio
    install_chrome

    if command -v snap &>/dev/null; then
        snap list spotify &>/dev/null || snap install spotify
    else
        warn "snapd not found; install Spotify manually"
    fi
    info "Desktop apps installed"
}

install_rtk() {
    if [[ $(rtk --version 2>/dev/null || true) != *"$RTK_VERSION"* ]]; then
        local tarball="${WORKDIR}/rtk.tar.gz" dest="${WORKDIR}/rtk"
        download "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/rtk-x86_64-unknown-linux-musl.tar.gz" "$tarball"
        echo "${RTK_SHA256}  ${tarball}" | sha256sum -c --quiet
        mkdir -p "$dest"
        tar -xzf "$tarball" -C "$dest"
        install -m 0755 "${dest}/rtk" /usr/local/bin/rtk
    fi
    as_user rtk init -g || warn "rtk init -g failed"
}

step_dev_tools() {
    user_has uv || as_user env UV_NO_MODIFY_PATH=1 sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    as_user uv tool install ruff

    user_has claude || as_user bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
    user_has opencode || as_user bash -c 'curl -fsSL https://opencode.ai/install | bash'
    user_has zed || as_user sh -c 'curl -fsSL https://zed.dev/install.sh | sh'
    user_has lazydocker || as_user bash -c \
        'curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash'

    install_rtk

    if as_user gh auth status &>/dev/null; then
        as_user gh extension install dlvhdr/gh-dash 2>/dev/null || true
    else
        warn "gh not authenticated: run 'gh auth login' and 'gh extension install dlvhdr/gh-dash'"
    fi
    info "Dev tooling installed"
}

install_asdf() {
    if [[ $(asdf --version 2>/dev/null || true) == *"$ASDF_VERSION"* ]]; then
        return
    fi
    local tarball="${WORKDIR}/asdf.tar.gz" dest="${WORKDIR}/asdf"
    download "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-amd64.tar.gz" "$tarball"
    echo "${ASDF_SHA256}  ${tarball}" | sha256sum -c --quiet
    mkdir -p "$dest"
    tar -xzf "$tarball" -C "$dest"
    install -m 0755 "${dest}/asdf" /usr/local/bin/asdf
}

asdf_install() {
    local plugin=$1 version=$2
    as_user asdf plugin add "$plugin" 2>/dev/null || true
    as_user asdf install "$plugin" "$version"
    as_user asdf set --home "$plugin" "$version"
}

step_languages() {
    # python-build compiles CPython from source.
    apt_install \
        build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
        libncurses-dev xz-utils tk-dev libffi-dev liblzma-dev
    apt_purge_installed nodejs npm

    install_asdf
    asdf completion fish | user_write "${TARGET_HOME}/.config/fish/completions/asdf.fish"

    asdf_install python "$PYTHON_VERSION"
    asdf_install nodejs "$NODE_VERSION"
    as_user corepack enable pnpm
    as_user asdf reshim nodejs
    info "asdf ready: Python ${PYTHON_VERSION}, Node.js ${NODE_VERSION}, pnpm"
}

step_git() {
    local key value
    while IFS='=' read -r key value; do
        as_user git config --global "$key" "$value"
    done <<EOF
user.name=${GIT_NAME}
user.email=${GIT_EMAIL}
user.username=${GIT_USERNAME}
init.defaultBranch=main
pull.rebase=true
push.autoSetupRemote=true
core.editor=vim
EOF
    info "Git configured"
}

step_shell() {
    local fish_conf="${TARGET_HOME}/.config/fish/conf.d"

    user_write "${fish_conf}/10-env.fish" <<'EOF'
set -gx EDITOR vim
set -g fish_greeting
set -q ASDF_DATA_DIR; or set -gx ASDF_DATA_DIR ~/.asdf
fish_add_path -g ~/.local/bin ~/.opencode/bin
fish_add_path -gm $ASDF_DATA_DIR/shims
EOF
    user_write "${fish_conf}/20-aliases.fish" <<'EOF'
if status is-interactive
    alias ll 'eza -la --git'
    alias gs 'git status'
    alias bat batcat
    alias fd fdfind
    alias up 'sudo apt update && sudo apt full-upgrade'
    alias clean 'sudo apt autoremove --purge'
end
EOF
    user_write "${fish_conf}/90-tools.fish" <<'EOF'
if status is-interactive
    command -q starship; and starship init fish | source
    command -q direnv; and direnv hook fish | source
end
EOF
    user_write "${TARGET_HOME}/.config/starship.toml" <<'EOF'
"$schema" = 'https://starship.rs/config-schema.json'

add_newline = true

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"

[package]
disabled = true

[nodejs]
symbol = "⬢ "

[gcloud]
disabled = true
EOF

    local fish_bin
    fish_bin=$(command -v fish)
    if [[ $(getent passwd "$TARGET_USER" | cut -d: -f7) != "$fish_bin" ]]; then
        chsh -s "$fish_bin" "$TARGET_USER"
    fi
    info "Fish is the default shell"
}

install_nerd_font() {
    local name=$1 dest="/usr/local/share/fonts/nerd-fonts/$1"
    [[ -d $dest ]] && return
    local archive="${WORKDIR}/${name}.tar.xz"
    download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${name}.tar.xz" "$archive"
    mkdir -p "$dest"
    tar -xJf "$archive" -C "$dest"
}

step_fonts() {
    apt_install fontconfig fonts-jetbrains-mono fonts-noto-core fonts-noto-color-emoji
    install_nerd_font JetBrainsMono
    install_nerd_font Terminus

    write_file /etc/fonts/local.conf <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer><family>JetBrainsMono Nerd Font Mono</family></prefer>
  </alias>
</fontconfig>
EOF
    fc-cache -f >/dev/null
    gnome_set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font Mono 11'
    info "Fonts installed"
}

step_wallpaper() {
    [[ -f $WALLPAPER_PATH ]] || { warn "Wallpaper not found: ${WALLPAPER_PATH}"; return; }

    local uri="file://${WALLPAPER_PATH}"
    gnome_set org.gnome.desktop.background picture-uri "$uri"
    gnome_set org.gnome.desktop.background picture-uri-dark "$uri"
    gnome_set org.gnome.desktop.background picture-options zoom
    info "Wallpaper set"
}

step_cleanup() {
    apt-get autoremove -y --purge
    apt-get autoclean -y
    info "Cleanup complete"
}

# ─── selection ──────────────────────────────────────────────────────────────

step_name() { echo "${STEPS[$1]%%|*}"; }
step_title() { echo "${STEPS[$1]#*|}"; }

choose_steps() {
    local -a selected=()
    local i current=0 key all
    local -ri total=${#STEPS[@]}

    for ((i = 0; i < total; i++)); do
        selected[i]=0
        [[ " ${DEFAULT_STEPS[*]} " == *" $(step_name "$i") "* ]] && selected[i]=1
    done

    tput civis
    while true; do
        tput clear
        printf "ThinkPad E14 Gen 2 — Ubuntu 26.04 setup\n\n"
        printf "Up/Down: move | Space: toggle | Enter: run | a: toggle all | q: quit\n\n"
        for ((i = 0; i < total; i++)); do
            printf "%s %s %-10s %s\n" \
                "$( ((i == current)) && echo '>' || echo ' ')" \
                "$( ((selected[i])) && echo '[x]' || echo '[ ]')" \
                "$(step_name "$i")" "$(step_title "$i")"
        done

        IFS= read -rsn1 key || true
        case "$key" in
            "")
                SELECTED_STEPS=()
                for ((i = 0; i < total; i++)); do
                    ((selected[i])) && SELECTED_STEPS+=("$(step_name "$i")")
                done
                if ((${#SELECTED_STEPS[@]})); then
                    tput cnorm
                    return
                fi
                ;;
            q | Q)
                tput cnorm
                warn "Cancelled."
                exit 0
                ;;
            a | A)
                all=1
                for ((i = 0; i < total; i++)); do ((selected[i])) || all=0; done
                for ((i = 0; i < total; i++)); do selected[i]=$((1 - all)); done
                ;;
            " ")
                selected[current]=$((1 - selected[current]))
                ;;
            $'\x1b')
                IFS= read -rsn2 key || true
                case "$key" in
                    "[A") current=$(((current - 1 + total) % total)) ;;
                    "[B") current=$(((current + 1) % total)) ;;
                esac
                ;;
        esac
    done
}

print_summary() {
    header "Summary"
    local label cmd
    while IFS='|' read -r label cmd; do
        printf "  %-11s %s\n" "${label}:" "$(as_user bash -c "$cmd" 2>/dev/null | head -1 || echo 'N/A')"
    done <<'EOF'
Kernel|uname -r
BIOS|cat /sys/class/dmi/id/bios_version
Swap|swapon --show=NAME,SIZE --noheadings | tr '\n' ' '
OOM|systemctl is-active earlyoom
Wi-Fi wd|systemctl is-active rtw88-watchdog.service
TCP|sysctl -n net.ipv4.tcp_congestion_control
PipeWire|pipewire --version | tail -1
Docker|docker --version
Fish|fish --version
uv|uv --version
asdf|asdf --version
Python|python --version
Node.js|node --version
pnpm|pnpm --version
gh|gh --version
Claude|claude --version
OpenCode|opencode --version
Warp|warp-terminal --version
rtk|rtk --version
Zed|zed --version
EOF
}

# ─── entrypoint ─────────────────────────────────────────────────────────────

require_environment() {
    ((EUID == 0)) || die "Run with sudo: sudo $0"
    [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]] || die "Run via sudo from your regular user"

    # shellcheck source=/dev/null
    . /etc/os-release
    [[ ${ID:-} == ubuntu ]] || die "This script targets Ubuntu"
    [[ ${VERSION_ID:-} == 26.04 ]] || warn "Written for 26.04, detected ${VERSION_ID:-unknown}"

    TARGET_USER=$SUDO_USER
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    TARGET_UID=$(id -u "$TARGET_USER")
    CODENAME=${UBUNTU_CODENAME:-$VERSION_CODENAME}
    WORKDIR=$(mktemp -d)
    chmod 0755 "$WORKDIR"
    readonly TARGET_USER TARGET_HOME TARGET_UID CODENAME WORKDIR
    trap 'tput cnorm 2>/dev/null || true; rm -rf "$WORKDIR"' EXIT
}

main() {
    if [[ ${1:-} == --list ]]; then
        local i
        for i in "${!STEPS[@]}"; do printf "%-10s %s\n" "$(step_name "$i")" "$(step_title "$i")"; done
        return
    fi

    require_environment

    SELECTED_STEPS=("$@")
    if ((${#SELECTED_STEPS[@]} == 0)); then
        [[ -t 0 ]] || die "No TTY: pass step names (see --list)"
        choose_steps
    fi

    local step index=1
    for step in "${SELECTED_STEPS[@]}"; do
        declare -F "step_${step}" >/dev/null || die "Unknown step: ${step} (see --list)"
    done
    for step in "${SELECTED_STEPS[@]}"; do
        header "${index}/${#SELECTED_STEPS[@]} — ${step}"
        "step_${step}"
        index=$((index + 1))
    done

    print_summary

    warn "Reboot to apply kernel params, logind, zram, groups and environment.d."
    local answer
    read -rp "Reboot now? [y/N]: " answer || true
    [[ ${answer,,} == y ]] && reboot
    info "Done!"
}

main "$@"
