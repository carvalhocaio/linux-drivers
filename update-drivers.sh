#!/usr/bin/env bash

#
# Driver update script — Lenovo ThinkPad E14
# Ubuntu 26.04 LTS | Intel Iris Xe | Intel Tiger Lake Audio
#
# Strategy: apt for drivers/firmware/kernel (system-level)
#           Homebrew for userland tools (newer versions)
#
# Usage:
#   chmod +x update-drivers.sh   # required when downloading outside git clone
#   sudo ./update-drivers.sh
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()   { echo -e "${GREEN}[✔]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
err()    { echo -e "${RED}[✘]${NC} $*"; }
header() {
  echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN} $*${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ──────────────────────────────────────────────
# Initial checks
# ──────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
  err "Please run with sudo: sudo $0"
  exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
BREW="/home/linuxbrew/.linuxbrew/bin/brew"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

as_user() { sudo -u "$REAL_USER" bash -c "$*"; }

brew_run() {
  as_user "eval \"\$($BREW shellenv)\" && export PATH=\"\${ASDF_DATA_DIR:-\$HOME/.asdf}/shims:\$PATH\" && $*"
}

header "Driver Update — Lenovo ThinkPad E14 (Ubuntu 26.04)"

# ──────────────────────────────────────────────
header "1/10 — Updating system packages (apt)"
# ──────────────────────────────────────────────

apt update
apt upgrade -y
info "System packages updated"

# ──────────────────────────────────────────────
header "2/10 — Video drivers (Intel Iris Xe / Mesa)"
# ──────────────────────────────────────────────

# Note: xserver-xorg-video-intel was removed in Ubuntu 24.04+.
# The Iris Xe uses the kernel's 'modesetting' driver — no extra package needed.
apt install -y --only-upgrade \
  mesa-vulkan-drivers \
  libgl1-mesa-dri \
  libglu1-mesa \
  libegl-mesa0 \
  libglx-mesa0 \
  mesa-utils \
  intel-media-va-driver \
  intel-gpu-tools 2>/dev/null || true

if command -v ubuntu-drivers &>/dev/null; then
  info "Checking recommended drivers..."
  ubuntu-drivers install 2>/dev/null || warn "No additional recommended drivers found"
fi

info "Video drivers updated"

# ──────────────────────────────────────────────
header "3/10 — Audio drivers (Intel Tiger Lake / PipeWire)"
# ──────────────────────────────────────────────

apt install -y --only-upgrade \
  pipewire \
  pipewire-pulse \
  pipewire-alsa \
  wireplumber \
  alsa-utils \
  alsa-base \
  firmware-sof-signed \
  linux-firmware 2>/dev/null || true

info "Audio drivers updated"

# ──────────────────────────────────────────────
header "4/10 — Network drivers (Realtek Wi-Fi/Bluetooth/Ethernet)"
# ──────────────────────────────────────────────

# Note: 'firmware-realtek' and 'r8168-dkms' are Debian non-free packages,
# not available in Ubuntu repos. Realtek firmware is already covered by
# 'linux-firmware'. Only bluez/dkms are needed here.
apt install -y --only-upgrade \
  dkms \
  bluez \
  bluez-tools 2>/dev/null || true

info "Network drivers updated"

# ──────────────────────────────────────────────
header "5/10 — Firmware and security drivers"
# ──────────────────────────────────────────────

apt install -y --only-upgrade \
  linux-generic \
  linux-firmware \
  intel-microcode \
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
  fwupdmgr get-updates 2>/dev/null && \
    fwupdmgr update -y 2>/dev/null || warn "No firmware updates available"
fi

info "Firmware and security drivers updated"

# ──────────────────────────────────────────────
header "6/10 — Build dependencies (apt) + Homebrew"
# ──────────────────────────────────────────────

# curl and git are required by the Homebrew installer — must come before it.
apt install -y curl git
info "curl and git installed (Homebrew bootstrap)"

apt install -y \
  make \
  build-essential \
  libssl-dev \
  zlib1g-dev \
  libbz2-dev \
  libreadline-dev \
  libsqlite3-dev \
  llvm \
  libncurses-dev \
  xz-utils \
  tk-dev \
  libffi-dev \
  liblzma-dev

info "Build dependencies installed (apt)"

# Install Homebrew as the real (non-root) user.
# Uses the official command from the Homebrew docs:
#   https://docs.brew.sh/Installation
# The installer requires git and curl in PATH — installed above via apt.
# Checks for the brew binary (not just the directory) to detect incomplete installs.
if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  # Remove any incomplete previous installation
  rm -rf /home/linuxbrew/.linuxbrew
  sudo -u "$REAL_USER" \
    NONINTERACTIVE=1 \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  info "Homebrew installed"
else
  info "Homebrew already installed"
fi

brew_run "brew update"
brew_run "brew install gcc"
info "Homebrew updated (gcc installed)"

# ──────────────────────────────────────────────
header "7/10 — Docker Engine"
# ──────────────────────────────────────────────

apt remove -y docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null || true

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

usermod -aG docker "$REAL_USER"
info "Docker Engine installed (relogin required for group changes)"

# ──────────────────────────────────────────────
header "8/10 — Userland tools (Homebrew)"
# ──────────────────────────────────────────────

brew_run "brew install git curl wget vim fish starship gh asdf"
info "Tools installed via Homebrew (git, curl, wget, vim, fish, starship, gh, asdf)"

BREW_FISH="$(/home/linuxbrew/.linuxbrew/bin/brew --prefix)/bin/fish"
if ! grep -qF "$BREW_FISH" /etc/shells; then
  echo "$BREW_FISH" >> /etc/shells
fi
chsh -s "$BREW_FISH" "$REAL_USER"
info "Fish shell set as default (Homebrew version)"

# ──────────────────────────────────────────────
header "9/10 — Shell config + Languages (asdf)"
# ──────────────────────────────────────────────

as_user mkdir -p "$REAL_HOME/.config/fish"

cat > "$REAL_HOME/.config/fish/config.fish" << 'FISHEOF'
if status is-interactive
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
    starship init fish | source
    set -gx PATH $HOME/.asdf/shims $PATH
end
FISHEOF
chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config/fish/config.fish"

cat > "$REAL_HOME/.config/starship.toml" << 'STAREOF'
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

info "Fish and Starship configured"

# asdf plugins
brew_run "asdf plugin add python || true"
brew_run "asdf plugin add nodejs || true"
info "asdf plugins added (python, nodejs)"

# Fix: correct flag is '--home', not '--u' (--u does not exist in asdf)
brew_run "asdf install python 3.10.14 && asdf set --home python 3.10.14"
info "Python 3.10.14 installed"

brew_run "asdf install nodejs 24.14.0 && asdf set --home nodejs 24.14.0"
info "Node.js 24.14.0 installed"

if brew_run "node --version >/dev/null && npm --version >/dev/null"; then
  info "Node.js and npm available via asdf shims"
else
  err "Node.js/npm not found in PATH after asdf setup"
  exit 1
fi

brew_run "npm install -g aicommits"
info "aicommits installed"

# ──────────────────────────────────────────────
header "10/11 — JetBrains Mono font"
# ──────────────────────────────────────────────

JETBRAINS_SRC_DIR="$SCRIPT_DIR/JetBrainsMono-2.304/fonts/ttf"
JETBRAINS_DEST_DIR="$REAL_HOME/.local/share/fonts/JetBrainsMono"

if [[ -d "$JETBRAINS_SRC_DIR" ]]; then
  if ! command -v fc-cache &>/dev/null; then
    apt install -y fontconfig
  fi

  as_user "mkdir -p '$JETBRAINS_DEST_DIR'"
  cp "$JETBRAINS_SRC_DIR"/*.ttf "$JETBRAINS_DEST_DIR/"
  chown "$REAL_USER":"$REAL_USER" "$JETBRAINS_DEST_DIR"/*.ttf
  as_user "fc-cache -f '$REAL_HOME/.local/share/fonts'"
  info "JetBrains Mono installed (all TTF variants)"
else
  warn "JetBrains Mono source not found at: $JETBRAINS_SRC_DIR"
fi

# ──────────────────────────────────────────────
header "11/11 — Zed Editor + Cleanup"
# ──────────────────────────────────────────────

as_user 'curl -f https://zed.dev/install.sh | sh'
info "Zed editor installed"

apt autoremove -y
apt autoclean -y
brew_run "brew cleanup"
info "Cleanup complete"

# ──────────────────────────────────────────────
header "Summary"
# ──────────────────────────────────────────────

echo "  Kernel:     $(uname -r)"
echo "  Mesa:       $(dpkg -l libgl1-mesa-dri 2>/dev/null | awk '/^ii/{print $3}')"
echo "  PipeWire:   $(pipewire --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  Microcode:  $(dpkg -l intel-microcode 2>/dev/null | awk '/^ii/{print $3}')"
echo "  fwupd:      $(fwupdmgr --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  Docker:     $(docker --version 2>/dev/null || echo 'N/A')"
echo "  Homebrew:   $(brew_run 'brew --version' 2>/dev/null | head -1 || echo 'N/A')"
echo "  Git:        $(brew_run 'git --version' 2>/dev/null || echo 'N/A')"
echo "  Fish:       $(brew_run 'fish --version' 2>/dev/null || echo 'N/A')"
echo "  Starship:   $(brew_run 'starship --version' 2>/dev/null | head -1 || echo 'N/A')"
echo "  Python:     $(brew_run '$HOME/.asdf/shims/python --version' 2>/dev/null || echo 'N/A')"
echo "  Node.js:    $(brew_run '$HOME/.asdf/shims/node --version' 2>/dev/null || echo 'N/A')"
echo "  gh:         $(brew_run 'gh --version' 2>/dev/null | head -1 || echo 'N/A')"
echo "  Zed:        $(as_user '$HOME/.local/bin/zed --version' 2>/dev/null || echo 'N/A')"
echo ""

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
