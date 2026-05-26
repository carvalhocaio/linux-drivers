#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[✔]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✘]${NC} $*"; }
header() {
  echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN} $*${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

if [[ $EUID -ne 0 ]]; then
  err "Please run with sudo: sudo $0"
  exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
BREW="/home/linuxbrew/.linuxbrew/bin/brew"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

JETBRAINS_MONO_API_URL="https://api.github.com/repos/JetBrains/JetBrainsMono/releases/latest"
WALLPAPER_REL_PATH="assets/wallpapers/red_distortion_3.jpg"
WALLPAPER_OPTIONS="zoom"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

as_user() { sudo -u "$REAL_USER" bash -c "$*"; }

brew_run() {
  as_user "eval \"\$($BREW shellenv)\" && export PATH=\"\${ASDF_DATA_DIR:-\$HOME/.asdf}/shims:\$PATH\" && $*"
}

brew_ensure_pkg() {
  local pkg="$1"
  if brew_run "brew list --formula '$pkg' >/dev/null 2>&1"; then
    brew_run "brew upgrade '$pkg' >/dev/null 2>&1 || true"
    info "$pkg verified via Homebrew"
  else
    brew_run "brew install '$pkg'"
    info "$pkg installed via Homebrew"
  fi
}

declare -A STEP_TITLE
declare -A STEP_DESC

STEP_TITLE[1]="Updating system packages (dnf)"
STEP_TITLE[2]="Video drivers (Intel Iris Xe / Mesa)"
STEP_TITLE[3]="Audio drivers (Intel Tiger Lake / PipeWire)"
STEP_TITLE[4]="Network drivers (Realtek Wi-Fi/Bluetooth/Ethernet)"
STEP_TITLE[5]="Firmware and security drivers"
STEP_TITLE[6]="Build dependencies + Homebrew bootstrap"
STEP_TITLE[7]="Docker Engine"
STEP_TITLE[8]="Userland tools (Homebrew)"
STEP_TITLE[9]="Shell config + Languages (asdf)"
STEP_TITLE[10]="JetBrains Mono font"
STEP_TITLE[11]="Zed"
STEP_TITLE[12]="Cleanup"
STEP_TITLE[13]="Claude Code"
STEP_TITLE[14]="Warp Terminal"
STEP_TITLE[15]="Wallpaper"

STEP_DESC[1]="dnf upgrade"
STEP_DESC[2]="mesa, intel media"
STEP_DESC[3]="pipewire, alsa, sof firmware"
STEP_DESC[4]="dkms, bluez"
STEP_DESC[5]="kernel, microcode, fwupd, thermald"
STEP_DESC[6]="build deps + install Homebrew"
STEP_DESC[7]="docker-ce + compose plugin"
STEP_DESC[8]="git curl wget vim fish starship gh asdf"
STEP_DESC[9]="fish config + python/node via asdf"
STEP_DESC[10]="download and install latest JetBrains Mono"
STEP_DESC[11]="install Zed for current user"
STEP_DESC[12]="dnf/brew cleanup"
STEP_DESC[13]="install Claude Code for current user"
STEP_DESC[14]="install Warp (.rpm)"
STEP_DESC[15]="set GNOME wallpaper"

run_step() {
  local n="$1"
  local idx="$2"
  local total="$3"
  header "$idx/$total — ${STEP_TITLE[$n]}"
  "step_$n"
}

step_1() {
  dnf upgrade -y
  info "System packages updated"
}

step_2() {
  dnf install -y \
    mesa-vulkan-drivers \
    mesa-dri-drivers \
    mesa-libGLU \
    mesa-libEGL \
    mesa-libGL \
    mesa-utils \
    intel-media-driver \
    intel-gpu-tools 2>/dev/null || true
  info "Video drivers verified/updated"
}

step_3() {
  dnf install -y \
    pipewire \
    pipewire-pulseaudio \
    pipewire-alsa \
    wireplumber \
    alsa-utils \
    alsa-sof-firmware \
    linux-firmware 2>/dev/null || true
  info "Audio drivers verified/updated"
}

step_4() {
  dnf install -y \
    dkms \
    bluez \
    bluez-tools 2>/dev/null || true
  info "Network drivers verified/updated"
}

step_5() {
  dnf install -y \
    linux-firmware \
    microcode_ctl \
    fwupd \
    tpm2-tools \
    thermald 2>/dev/null || true

  if systemctl is-enabled thermald &>/dev/null; then
    systemctl start thermald 2>/dev/null || true
    info "thermald is active"
  else
    systemctl enable --now thermald 2>/dev/null || warn "Could not enable thermald"
  fi

  if command -v fwupdmgr &>/dev/null; then
    info "Checking Lenovo firmware via fwupd..."
    fwupdmgr refresh --force 2>/dev/null || true
    fwupdmgr get-updates 2>/dev/null && fwupdmgr update -y 2>/dev/null || warn "No firmware updates available"
  fi
  info "Firmware and security verified/updated"
}

step_6() {
  dnf install -y curl git
  dnf install -y \
    make \
    gcc \
    gcc-c++ \
    openssl-devel \
    zlib-devel \
    bzip2-devel \
    readline-devel \
    sqlite-devel \
    llvm \
    ncurses-devel \
    xz \
    tk-devel \
    libffi-devel \
    xz-devel
  info "Build dependencies verified/updated"

  if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    rm -rf /home/linuxbrew/.linuxbrew
    sudo -u "$REAL_USER" NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    info "Homebrew installed"
  else
    info "Homebrew already installed"
  fi

  brew_run "brew update"
  brew_ensure_pkg "gcc"
}

step_7() {
  dnf remove -y docker docker-client docker-client-latest docker-common docker-latest \
    docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine 2>/dev/null || true

  curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
    -o /etc/yum.repos.d/docker-ce.repo

  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
  usermod -aG docker "$REAL_USER"
  info "Docker Engine installed/updated (relogin required for group changes)"
}

step_8() {
  local pkg
  for pkg in git curl wget vim fish starship gh asdf; do
    brew_ensure_pkg "$pkg"
  done

  BREW_FISH="$(/home/linuxbrew/.linuxbrew/bin/brew --prefix)/bin/fish"
  if ! grep -qF "$BREW_FISH" /etc/shells; then
    echo "$BREW_FISH" >> /etc/shells
  fi
  chsh -s "$BREW_FISH" "$REAL_USER"
  info "Fish shell set as default (Homebrew version)"
}

step_9() {
  as_user "mkdir -p '$REAL_HOME/.config/fish'"

  cat >"$REAL_HOME/.config/fish/config.fish" <<'FISHEOF'
if status is-interactive
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
    starship init fish | source
    set -gx PATH $HOME/.asdf/shims $PATH
end
FISHEOF
  chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config/fish/config.fish"

  cat >"$REAL_HOME/.config/starship.toml" <<'STAREOF'
"$schema" = 'https://starship.rs/config-schema.json'

add_newline = true

[character]
success_symbol = '[➜](bold green)'
error_symbol   = '[➜](bold red)'

[package]
disabled = true

[nodejs]
symbol = "⬢ "

[gcloud]
disabled = true
STAREOF
  chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config/starship.toml"

  brew_run "asdf plugin add python || true"
  brew_run "asdf plugin add nodejs || true"
  brew_run "asdf install python 3.10.14 && asdf set --home python 3.10.14"
  brew_run "asdf install nodejs 24.14.0 && asdf set --home nodejs 24.14.0"

  if brew_run "node --version >/dev/null && npm --version >/dev/null"; then
    info "Node.js and npm available via asdf shims"
  else
    err "Node.js/npm not found in PATH after asdf setup"
    exit 1
  fi

  info "Fish, Starship, asdf, Python, Node.js configured"
}

step_10() {
  local font_zip="$TMP_ROOT/JetBrainsMono.zip"
  local font_extract="$TMP_ROOT/JetBrainsMono"
  local font_dest="$REAL_HOME/.local/share/fonts/JetBrainsMono"
  local release_json
  local mono_download_url

  if as_user "test -d '$font_dest' && ls '$font_dest'/*.ttf >/dev/null 2>&1"; then
    info "JetBrains Mono already installed (skipping)"
    return
  fi

  dnf install -y fontconfig unzip
  release_json="$(curl -fsSL "$JETBRAINS_MONO_API_URL")"
  mono_download_url="$(python3 -c 'import json,sys; d=json.load(sys.stdin); a=next((x for x in d.get("assets",[]) if x.get("name","").startswith("JetBrainsMono-") and x.get("name","").endswith(".zip")), None); print((a or {}).get("browser_download_url",""))' <<< "$release_json")"

  if [[ -z "$mono_download_url" ]]; then
    warn "Could not find JetBrains Mono release asset URL"
    return
  fi

  curl -fL "$mono_download_url" -o "$font_zip"
  mkdir -p "$font_extract"
  unzip -q "$font_zip" -d "$font_extract"

  as_user "mkdir -p '$font_dest'"
  cp "$font_extract"/fonts/ttf/*.ttf "$font_dest/"
  chown "$REAL_USER":"$REAL_USER" "$font_dest"/*.ttf
  as_user "fc-cache -f '$REAL_HOME/.local/share/fonts'"
  info "JetBrains Mono installed from latest stable release"
}

step_11() {
  as_user 'curl -f https://zed.dev/install.sh | sh'
  info "Zed installed for $REAL_USER"
}

step_12() {
  dnf autoremove -y
  dnf clean all
  if [[ -x "$BREW" ]]; then
    brew_run "brew cleanup"
  fi
  info "Cleanup complete"
}

step_13() {
  as_user 'curl -fsSL https://claude.ai/install.sh | bash'
  info "Claude Code installed for $REAL_USER"
}

step_14() {
  local warp_rpm="$TMP_ROOT/warp.rpm"
  local warp_pkg="rpm"

  if [[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]]; then
    warp_pkg="rpm_arm64"
  fi

  curl -fL "https://app.warp.dev/download?package=$warp_pkg" -o "$warp_rpm"

  if ! rpm -qp "$warp_rpm" >/dev/null 2>&1; then
    warn "Downloaded Warp package is invalid"
    return
  fi

  dnf install -y "$warp_rpm"
  info "Warp installed/updated"
}

step_15() {
  local wallpaper_path="$SCRIPT_DIR/$WALLPAPER_REL_PATH"
  local wallpaper_uri="file://$wallpaper_path"
  local real_uid
  local runtime_dir
  local session_bus
  local current_uri

  if [[ ! -f "$wallpaper_path" ]]; then
    warn "Wallpaper file not found: $wallpaper_path"
    return
  fi

  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not found; wallpaper was not configured"
    return
  fi

  real_uid="$(id -u "$REAL_USER")"
  runtime_dir="/run/user/$real_uid"
  session_bus="$runtime_dir/bus"

  if [[ ! -S "$session_bus" ]]; then
    warn "Desktop session bus not found for $REAL_USER; log in graphically and run this step again"
    return
  fi

  as_user "export XDG_RUNTIME_DIR='$runtime_dir'; export DBUS_SESSION_BUS_ADDRESS='unix:path=$session_bus'; gsettings set org.gnome.desktop.background picture-uri '$wallpaper_uri'"
  as_user "export XDG_RUNTIME_DIR='$runtime_dir'; export DBUS_SESSION_BUS_ADDRESS='unix:path=$session_bus'; gsettings set org.gnome.desktop.background picture-uri-dark '$wallpaper_uri'"
  as_user "export XDG_RUNTIME_DIR='$runtime_dir'; export DBUS_SESSION_BUS_ADDRESS='unix:path=$session_bus'; gsettings set org.gnome.desktop.background picture-options '$WALLPAPER_OPTIONS'"

  current_uri="$(as_user "export XDG_RUNTIME_DIR='$runtime_dir'; export DBUS_SESSION_BUS_ADDRESS='unix:path=$session_bus'; gsettings get org.gnome.desktop.background picture-uri" 2>/dev/null || true)"
  if [[ "$current_uri" == "'$wallpaper_uri'" ]]; then
    info "Wallpaper configured for $REAL_USER"
  else
    warn "Wallpaper could not be confirmed via gsettings"
  fi
}

choose_steps() {
  local i
  local mark
  local pointer
  local key
  local current=1
  local all_selected
  local -i max_step=15
  declare -A selected

  for i in $(seq 1 "$max_step"); do
    selected[$i]=0
  done
  for i in 1 2 3 4 5; do
    selected[$i]=1
  done

  tput civis
  trap 'tput cnorm; stty echo; printf "\n"' RETURN

  while true; do
    tput clear
    printf "Driver Update - Select steps\n\n"
    printf "Use Up/Down to move, Space to toggle, Enter to run\n"
    printf "a: toggle all | q: quit\n\n"

    for i in $(seq 1 "$max_step"); do
      mark="[ ]"
      pointer=" "
      [[ ${selected[$i]} -eq 1 ]] && mark="[x]"
      [[ $i -eq $current ]] && pointer=">"
      printf "%s %2d %s %s\n" "$pointer" "$i" "$mark" "${STEP_TITLE[$i]}"
    done

    IFS= read -rsn1 key || true

    if [[ "$key" == "" ]]; then
      SELECTED_STEPS=()
      for i in $(seq 1 "$max_step"); do
        [[ ${selected[$i]} -eq 1 ]] && SELECTED_STEPS+=("$i")
      done
      if [[ ${#SELECTED_STEPS[@]} -gt 0 ]]; then
        tput cnorm
        trap - RETURN
        printf "\n"
        return
      fi
      continue
    fi

    case "$key" in
      q|Q)
        tput cnorm
        trap - RETURN
        printf "\n"
        warn "Cancelled by user."
        exit 0
        ;;
      a|A)
        all_selected=1
        for i in $(seq 1 "$max_step"); do
          if [[ ${selected[$i]} -eq 0 ]]; then
            all_selected=0
            break
          fi
        done
        for i in $(seq 1 "$max_step"); do
          if [[ $all_selected -eq 1 ]]; then
            selected[$i]=0
          else
            selected[$i]=1
          fi
        done
        ;;
      ' ')
        if [[ ${selected[$current]} -eq 1 ]]; then
          selected[$current]=0
        else
          selected[$current]=1
        fi
        ;;
      $'\x1b')
        IFS= read -rsn2 key || true
        case "$key" in
          "[A")
            if [[ $current -gt 1 ]]; then
              current=$((current - 1))
            else
              current=$max_step
            fi
            ;;
          "[B")
            if [[ $current -lt $max_step ]]; then
              current=$((current + 1))
            else
              current=1
            fi
            ;;
        esac
        ;;
    esac
  done
}

print_summary() {
  header "Summary"
  echo "  Kernel:     $(uname -r)"
  echo "  Mesa:       $(rpm -q mesa-dri-drivers 2>/dev/null | head -1 || echo 'N/A')"
  echo "  PipeWire:   $(pipewire --version 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Microcode:  $(rpm -q microcode_ctl 2>/dev/null | head -1 || echo 'N/A')"
  echo "  fwupd:      $(fwupdmgr --version 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Docker:     $(docker --version 2>/dev/null || echo 'N/A')"
  echo "  Homebrew:   $(brew_run 'brew --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Git:        $(brew_run 'git --version' 2>/dev/null || echo 'N/A')"
  echo "  Fish:       $(brew_run 'fish --version' 2>/dev/null || echo 'N/A')"
  echo "  Starship:   $(brew_run 'starship --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Python:     $(brew_run '$HOME/.asdf/shims/python --version' 2>/dev/null || echo 'N/A')"
  echo "  Node.js:    $(brew_run '$HOME/.asdf/shims/node --version' 2>/dev/null || echo 'N/A')"
  echo "  gh:         $(brew_run 'gh --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Claude:     $(as_user 'claude --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Warp:       $(warp-terminal --version 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Wallpaper:  $(as_user 'gsettings get org.gnome.desktop.background picture-uri' 2>/dev/null || echo 'N/A')"
  echo "  Zed:        $(as_user 'zed --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo ""
}

header "Driver Update — Lenovo ThinkPad E14 (Fedora 44)"
choose_steps

TOTAL_STEPS="${#SELECTED_STEPS[@]}"
CURRENT=1
for step in "${SELECTED_STEPS[@]}"; do
  run_step "$step" "$CURRENT" "$TOTAL_STEPS"
  CURRENT=$((CURRENT + 1))
done

print_summary

if [[ -f /var/run/reboot-required ]]; then
  warn "Reboot required to apply all updates."
  read -rp "Reboot now? [y/N]: " answer
  if [[ "${answer,,}" == "y" ]]; then
    reboot
  fi
else
  info "No reboot required."
fi

info "Done!"
