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

pacman_ensure_pkg() {
  local pkg="$1"
  if pacman -Qi "$pkg" &>/dev/null; then
    info "$pkg already installed"
  else
    pacman -S --noconfirm --needed "$pkg"
    info "$pkg installed"
  fi
}

# Builds an AUR package as the real user and installs the resulting .pkg.tar.* as root.
# Works without an AUR helper — requires only git and base-devel to be present.
build_and_install_aur() {
  local pkg="$1"
  local build_dir="$TMP_ROOT/aur_${pkg}"

  if pacman -Qi "$pkg" &>/dev/null; then
    info "$pkg already installed (AUR)"
    return
  fi

  info "Building $pkg from AUR..."
  as_user "git clone 'https://aur.archlinux.org/${pkg}.git' '${build_dir}'"
  as_user "cd '${build_dir}' && makepkg -f --noconfirm --skippgpcheck"

  local pkg_file
  pkg_file="$(find "${build_dir}" -maxdepth 1 -name '*.pkg.tar.*' | sort | head -1)"

  if [[ -z "$pkg_file" ]]; then
    warn "Could not build AUR package: $pkg"
    return 1
  fi

  pacman -U --noconfirm "$pkg_file"
  info "$pkg installed from AUR"
}

declare -A STEP_TITLE
declare -A STEP_DESC

STEP_TITLE[1]="Updating system packages (pacman)"
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
STEP_TITLE[14]="OpenCode"
STEP_TITLE[15]="gh CLI"
STEP_TITLE[16]="Warp Terminal"
STEP_TITLE[17]="JetBrains Toolbox"
STEP_TITLE[18]="Wallpaper"

STEP_DESC[1]="pacman -Syu"
STEP_DESC[2]="mesa, vulkan-intel, intel-media-driver, libva"
STEP_DESC[3]="pipewire, alsa-utils, sof-firmware"
STEP_DESC[4]="dkms, bluez, bluez-utils"
STEP_DESC[5]="linux-firmware, intel-ucode, fwupd, thermald (AUR)"
STEP_DESC[6]="base-devel + install Homebrew"
STEP_DESC[7]="docker + docker-compose + docker-buildx"
STEP_DESC[8]="git curl wget vim fish starship asdf"
STEP_DESC[9]="fish config + python/node via asdf"
STEP_DESC[10]="download and install latest JetBrains Mono"
STEP_DESC[11]="install Zed for current user"
STEP_DESC[12]="pacman/brew cleanup"
STEP_DESC[13]="install Claude Code for current user"
STEP_DESC[14]="install OpenCode for current user"
STEP_DESC[15]="install github-cli via pacman"
STEP_DESC[16]="install warp-terminal (AUR)"
STEP_DESC[17]="download and install JetBrains Toolbox"
STEP_DESC[18]="set GNOME wallpaper"

run_step() {
  local n="$1"
  local idx="$2"
  local total="$3"
  header "$idx/$total — ${STEP_TITLE[$n]}"
  "step_$n"
}

step_1() {
  pacman -Syu --noconfirm
  info "System packages updated"
}

step_2() {
  local pkgs=(
    mesa
    mesa-utils
    vulkan-intel
    intel-media-driver
    libva-mesa-driver
    libva-utils
    intel-gpu-tools
  )
  for pkg in "${pkgs[@]}"; do
    pacman_ensure_pkg "$pkg"
  done

  if command -v vainfo &>/dev/null; then
    info "VA-API status:"
    vainfo 2>&1 | grep -E "VAProfile|error|libva" | head -10 || true
  fi

  info "Video drivers verified/updated"
}

step_3() {
  local pkgs=(
    pipewire
    pipewire-pulse
    pipewire-alsa
    wireplumber
    alsa-utils
    sof-firmware
    linux-firmware
  )
  for pkg in "${pkgs[@]}"; do
    pacman_ensure_pkg "$pkg"
  done

  as_user "systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true"
  info "Audio drivers verified/updated"
}

step_4() {
  local pkgs=(
    dkms
    bluez
    bluez-utils
  )
  for pkg in "${pkgs[@]}"; do
    pacman_ensure_pkg "$pkg"
  done

  systemctl enable --now bluetooth 2>/dev/null || true
  info "Network drivers verified/updated"
}

step_5() {
  local pkgs=(
    linux-firmware
    intel-ucode
    fwupd
    tpm2-tools
  )
  for pkg in "${pkgs[@]}"; do
    pacman_ensure_pkg "$pkg"
  done

  build_and_install_aur "thermald"

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
  pacman -S --noconfirm --needed base-devel curl git
  info "Build dependencies verified/updated"

  if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    info "Installing Homebrew (manual method)..."
    mkdir -p /home/linuxbrew/.linuxbrew
    chown -R "$REAL_USER":"$REAL_USER" /home/linuxbrew
    sudo -u "$REAL_USER" git clone https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew
    mkdir -p /home/linuxbrew/.linuxbrew/bin
    ln -sf /home/linuxbrew/.linuxbrew/Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew
    sudo -u "$REAL_USER" bash -c "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\" && brew update --force --quiet"
    chmod -R go-w /home/linuxbrew/.linuxbrew/share/zsh 2>/dev/null || true
    info "Homebrew installed"
  else
    info "Homebrew already installed"
  fi

  if ! grep -qF "linuxbrew" "$REAL_HOME/.bashrc" 2>/dev/null; then
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$REAL_HOME/.bashrc"
    chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/.bashrc" 2>/dev/null || true
    info "Homebrew added to .bashrc"
  fi

  brew_run "brew update"
  brew_ensure_pkg "gcc"
}

step_7() {
  if ! pacman -Qi docker &>/dev/null; then
    pacman -S --noconfirm docker docker-buildx docker-compose
    info "Docker installed"
  else
    info "Docker already installed — skipping reinstall"
  fi

  systemctl enable --now docker 2>/dev/null || true

  if ! id -nG "$REAL_USER" 2>/dev/null | grep -qw docker; then
    usermod -aG docker "$REAL_USER"
    warn "User $REAL_USER added to docker group — run 'newgrp docker' or re-login to use Docker without sudo"
  else
    info "User $REAL_USER already in docker group"
  fi
}

step_8() {
  local pkg
  for pkg in git curl wget vim fish starship asdf; do
    brew_ensure_pkg "$pkg"
  done

  BREW_FISH="$(/home/linuxbrew/.linuxbrew/bin/brew --prefix)/bin/fish"
  if ! grep -qF "$BREW_FISH" /etc/shells; then
    echo "$BREW_FISH" >> /etc/shells
  fi
  usermod -s "$BREW_FISH" "$REAL_USER"
  info "Fish shell set as default (Homebrew version)"

  as_user "git config --global user.email 'caiocarvalho.py@gmail.com'"
  as_user "git config --global user.name 'Caio Carvalho'"
  as_user "git config --global github.user 'carvalhocaio'"
  info "Git global config set"
}

step_9() {
  as_user "mkdir -p '$REAL_HOME/.config/fish'"

  cat >"$REAL_HOME/.config/fish/config.fish" <<'FISHEOF'
if status is-interactive
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
    starship init fish | source
    set -gx PATH $HOME/.asdf/shims $HOME/.local/bin $PATH
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

  pacman_ensure_pkg "tk"

  brew_run "asdf plugin add python || true"
  brew_run "asdf plugin add nodejs || true"
  brew_run "asdf install python 3.12.10 && asdf set --home python 3.12.10"
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

  pacman_ensure_pkg "fontconfig"
  pacman_ensure_pkg "unzip"

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

  if as_user "fc-list | grep -qi 'JetBrains Mono'" 2>/dev/null; then
    info "JetBrains Mono installed and recognized by font system"
  else
    info "JetBrains Mono installed (font cache still refreshing)"
  fi
}

step_11() {
  as_user 'curl -f https://zed.dev/install.sh | sh'

  local fish_config="$REAL_HOME/.config/fish/config.fish"
  if [[ -f "$fish_config" ]] && ! grep -qF ".local/bin" "$fish_config"; then
    sed -i 's|set -gx PATH \$HOME/.asdf/shims|set -gx PATH $HOME/.asdf/shims $HOME/.local/bin|' "$fish_config" || true
    info "~/.local/bin added to fish PATH (required for Zed)"
  fi

  # Expose ~/.local/bin to graphical (non-login) sessions via systemd environment.d
  local env_d="$REAL_HOME/.config/environment.d"
  as_user "mkdir -p '$env_d'"
  if [[ ! -f "$env_d/local-bin.conf" ]]; then
    printf 'PATH=%s/.local/bin:$PATH\n' "$REAL_HOME" > "$env_d/local-bin.conf"
    chown "$REAL_USER":"$REAL_USER" "$env_d/local-bin.conf"
    info "~/.local/bin registered in environment.d for graphical sessions"
  fi

  # Refresh GNOME app database so Zed appears in the launcher immediately
  as_user "update-desktop-database '$REAL_HOME/.local/share/applications'" 2>/dev/null || true

  info "Zed installed for $REAL_USER — available in launcher after re-login"
}

step_12() {
  local orphans
  orphans="$(pacman -Qtdq 2>/dev/null || true)"
  if [[ -n "$orphans" ]]; then
    pacman -Rns --noconfirm $orphans
  fi
  find /var/cache/pacman/pkg/ -maxdepth 1 -name 'download-*' -delete 2>/dev/null || true
  pacman -Sc --noconfirm
  if [[ -x "$BREW" ]]; then
    brew_run "brew cleanup"
  fi
  info "Cleanup complete"
}

step_13() {
  as_user 'curl -fsSL https://claude.ai/install.sh | bash'

  if ! grep -qF ".local/bin" "$REAL_HOME/.config/fish/config.fish" 2>/dev/null; then
    sed -i 's|set -gx PATH \$HOME/.asdf/shims|set -gx PATH $HOME/.asdf/shims $HOME/.local/bin|' \
      "$REAL_HOME/.config/fish/config.fish" 2>/dev/null || true
  fi

  info "Claude Code installed for $REAL_USER (available in new Fish terminals)"
}

step_14() {
  as_user 'curl -fsSL https://opencode.ai/install | bash'
  info "OpenCode installed for $REAL_USER"
}

step_15() {
  pacman_ensure_pkg "github-cli"
  info "gh CLI installed"
}

step_16() {
  build_and_install_aur "warp-terminal"
  info "Warp installed/updated"
}

step_17() {
  local toolbox_api="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
  local toolbox_tar="$TMP_ROOT/jetbrains-toolbox.tar.gz"
  local toolbox_dir="$TMP_ROOT/jetbrains-toolbox"
  local local_tarball="$REAL_HOME/Downloads/jetbrains-toolbox-3.4.3.81140.tar.gz"
  local download_url

  download_url="$(curl -fsSL "$toolbox_api" | python3 -c '
import json, sys
data = json.load(sys.stdin)
releases = data.get("TBA", [])
if releases:
    linux = releases[0].get("downloads", {}).get("linux", {})
    print(linux.get("link", ""))
' 2>/dev/null || true)"

  if [[ -n "$download_url" ]]; then
    curl -fL "$download_url" -o "$toolbox_tar"
    info "JetBrains Toolbox downloaded from JetBrains"
  elif [[ -f "$local_tarball" ]]; then
    cp "$local_tarball" "$toolbox_tar"
    info "Using local JetBrains Toolbox tarball: $local_tarball"
  else
    warn "Could not download or locate JetBrains Toolbox tarball"
    return
  fi

  mkdir -p "$toolbox_dir"
  tar -xzf "$toolbox_tar" -C "$toolbox_dir" --strip-components=1
  chmod +x "$toolbox_dir/jetbrains-toolbox"
  as_user "'$toolbox_dir/jetbrains-toolbox' &"
  info "JetBrains Toolbox launched and installing for $REAL_USER"
}

step_18() {
  local wallpaper_path="$SCRIPT_DIR/$WALLPAPER_REL_PATH"
  local wallpaper_uri="file://$wallpaper_path"
  local real_uid
  local runtime_dir
  local session_bus

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

  if [[ -S "$session_bus" ]]; then
    local env_prefix="export XDG_RUNTIME_DIR='$runtime_dir'; export DBUS_SESSION_BUS_ADDRESS='unix:path=$session_bus'"

    as_user "$env_prefix; gsettings set org.gnome.desktop.background picture-uri '$wallpaper_uri'" || true
    as_user "$env_prefix; gsettings set org.gnome.desktop.background picture-uri-dark '$wallpaper_uri'" || true
    as_user "$env_prefix; gsettings set org.gnome.desktop.background picture-options '$WALLPAPER_OPTIONS'" || true

    local current_uri
    current_uri="$(as_user "$env_prefix; gsettings get org.gnome.desktop.background picture-uri" 2>/dev/null || true)"
    if [[ "$current_uri" == *"$wallpaper_path"* ]]; then
      info "Wallpaper configured for $REAL_USER"
      return
    fi
  fi

  # No active D-Bus session (script runs as root): write a helper script and
  # an autostart entry that applies the wallpaper on first login and removes both.
  local autostart_dir="$REAL_HOME/.config/autostart"
  local helper="$REAL_HOME/.config/set-wallpaper.sh"
  as_user "mkdir -p '$autostart_dir'"

  cat > "$helper" <<EOF
#!/bin/bash
gsettings set org.gnome.desktop.background picture-uri '$wallpaper_uri'
gsettings set org.gnome.desktop.background picture-uri-dark '$wallpaper_uri'
gsettings set org.gnome.desktop.background picture-options '$WALLPAPER_OPTIONS'
rm -f '$autostart_dir/set-wallpaper.desktop' '$helper'
EOF
  chmod +x "$helper"
  chown "$REAL_USER":"$REAL_USER" "$helper"

  cat > "$autostart_dir/set-wallpaper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Set Wallpaper
Exec=$helper
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
  chown "$REAL_USER":"$REAL_USER" "$autostart_dir/set-wallpaper.desktop"
  warn "No active desktop session — wallpaper will be applied automatically on next login"
}

choose_steps() {
  local i
  local mark
  local pointer
  local key
  local current=1
  local all_selected
  local -i max_step=18
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
  echo "  Mesa:       $(pacman -Qi mesa 2>/dev/null | awk '/^Version/{print $3}' || echo 'N/A')"
  echo "  PipeWire:   $(pipewire --version 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Microcode:  $(pacman -Qi intel-ucode 2>/dev/null | awk '/^Version/{print $3}' || echo 'N/A')"
  echo "  fwupd:      $(fwupdmgr --version 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Docker:     $(docker --version 2>/dev/null || echo 'N/A')"
  echo "  Homebrew:   $(brew_run 'brew --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Git:        $(brew_run 'git --version' 2>/dev/null || echo 'N/A')"
  echo "  Fish:       $(brew_run 'fish --version' 2>/dev/null || echo 'N/A')"
  echo "  Starship:   $(brew_run 'starship --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Python:     $(brew_run '$HOME/.asdf/shims/python --version' 2>/dev/null || echo 'N/A')"
  echo "  Node.js:    $(brew_run '$HOME/.asdf/shims/node --version' 2>/dev/null || echo 'N/A')"
  echo "  gh:         $(gh --version 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Claude:     $(as_user 'claude --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  OpenCode:   $(as_user 'opencode --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Warp:       $(warp-terminal --version 2>/dev/null | head -1 || echo 'N/A')"
  echo "  Wallpaper:  $(as_user 'gsettings get org.gnome.desktop.background picture-uri' 2>/dev/null || echo 'N/A')"
  echo "  Zed:        $(as_user 'zed --version' 2>/dev/null | head -1 || echo 'N/A')"
  echo "  JB Toolbox: $(as_user 'ls ~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox' 2>/dev/null && echo 'installed' || echo 'N/A')"
  echo ""
}

header "Driver Update — Lenovo ThinkPad E14 (Arch Linux)"
choose_steps

TOTAL_STEPS="${#SELECTED_STEPS[@]}"
CURRENT=1
for step in "${SELECTED_STEPS[@]}"; do
  run_step "$step" "$CURRENT" "$TOTAL_STEPS"
  CURRENT=$((CURRENT + 1))
done

print_summary

RUNNING_KERNEL="$(uname -r)"
INSTALLED_KERNEL="$(pacman -Q linux 2>/dev/null | awk '{print $2}' || true)"
if [[ -n "$INSTALLED_KERNEL" && "$RUNNING_KERNEL" != "${INSTALLED_KERNEL%.arch*}"* ]]; then
  warn "Kernel updated (running: $RUNNING_KERNEL). A reboot is recommended."
  read -rp "Reboot now? [y/N]: " answer
  if [[ "${answer,,}" == "y" ]]; then
    reboot
  fi
else
  info "No reboot required."
fi

info "Done!"
