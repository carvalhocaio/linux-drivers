#!/usr/bin/env bash
#
# Driver update script — Lenovo ThinkPad E14
# Ubuntu | Intel Iris Xe | Intel Tiger Lake Audio
#
# Strategy: apt for drivers/firmware/kernel (system-level)
#           Homebrew for userland tools (newer versions)
#
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✘]${NC} $*"; }
header(){ echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${GREEN}  $*${NC}"; echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    err "Please run with sudo: sudo $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
BREW="/home/linuxbrew/.linuxbrew/bin/brew"
as_user() { sudo -u "$REAL_USER" bash -c "$*"; }
brew_run() {
    as_user "eval \"\$($BREW shellenv)\" && export PATH=\"\${ASDF_DATA_DIR:-\$HOME/.asdf}/shims:\$PATH\" && $*"
}

header "Driver Update — Lenovo ThinkPad E14"

# ──────────────────────────────────────────────
header "1/10 — Updating system packages (apt)"
# ──────────────────────────────────────────────
apt update
apt upgrade -y
info "System packages updated"

# ──────────────────────────────────────────────
header "2/10 — Video Drivers (Intel Iris Xe / Mesa)"
# ──────────────────────────────────────────────
apt install -y --only-upgrade \
    mesa-vulkan-drivers \
    libgl1-mesa-dri \
    libglu1-mesa \
    libegl-mesa0 \
    libglx-mesa0 \
    mesa-utils \
    intel-media-va-driver \
    intel-gpu-tools \
    xserver-xorg-video-intel 2>/dev/null || true

if command -v ubuntu-drivers &>/dev/null; then
    info "Checking recommended drivers..."
    ubuntu-drivers install 2>/dev/null || warn "No additional recommended drivers found"
fi

info "Video drivers updated"

# ──────────────────────────────────────────────
header "3/10 — Audio Drivers (Intel Tiger Lake / PipeWire)"
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
header "4/10 — Network Drivers (Realtek Wi-Fi/Bluetooth/Ethernet)"
# ──────────────────────────────────────────────
apt install -y --only-upgrade \
    firmware-realtek \
    r8168-dkms \
    bluez \
    bluez-tools 2>/dev/null || true

info "Network drivers updated"

# ──────────────────────────────────────────────
header "5/10 — Firmware and Security Drivers"
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

info "Security drivers and firmware updated"

# ──────────────────────────────────────────────
header "6/10 — Build Dependencies (apt) + Homebrew"
# ──────────────────────────────────────────────

# Pre-requisite: curl (needed for Homebrew installer)
apt install -y curl
info "curl installed"

# System libraries needed for compiling (must stay in apt)
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
# Tmpfile goes in REAL_HOME (not /tmp) because Ubuntu 26.04 mounts /tmp
# with noexec, causing "Permission denied" even after chmod +x.
if [[ ! -d /home/linuxbrew/.linuxbrew ]]; then
    BREW_INSTALLER="$REAL_HOME/.brew-install-$$.sh"
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
        -o "$BREW_INSTALLER"
    chown "$REAL_USER":"$REAL_USER" "$BREW_INSTALLER"
    chmod 755 "$BREW_INSTALLER"
    sudo -u "$REAL_USER" env -i \
        HOME="$REAL_HOME" \
        USER="$REAL_USER" \
        LOGNAME="$REAL_USER" \
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        NONINTERACTIVE=1 \
        /bin/bash "$BREW_INSTALLER"
    rm -f "$BREW_INSTALLER"
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

# Remove conflicting packages
apt remove -y docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null || true

# Set up Docker's official apt repository
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

# Install Docker Engine + plugins
apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Add user to docker group (no sudo required after relogin)
usermod -aG docker "$REAL_USER"
info "Docker Engine installed (relogin required for group changes)"

# ──────────────────────────────────────────────
header "8/10 — Userland Tools (Homebrew)"
# ──────────────────────────────────────────────
brew_run "brew install git curl wget vim fish starship gh asdf"
info "Tools installed via Homebrew (git, curl, wget, vim, fish, starship, gh, asdf)"

# Set Homebrew's fish as default shell
BREW_FISH="$(/home/linuxbrew/.linuxbrew/bin/brew --prefix)/bin/fish"
if ! grep -qF "$BREW_FISH" /etc/shells; then
    echo "$BREW_FISH" >> /etc/shells
fi
chsh -s "$BREW_FISH" "$REAL_USER"
info "Fish shell set as default (Homebrew version)"

# ──────────────────────────────────────────────
header "9/10 — Shell Config + Languages (asdf)"
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
error_symbol = '[➜](bold green)'

[package]
disabled = true

[nodejs]
symbol = "⬢ "

[gcloud]
disabled = true
STAREOF
chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config/starship.toml"
info "Fish and Starship configured"

# asdf languages
brew_run "asdf plugin add python || true"
brew_run "asdf plugin add nodejs || true"
info "asdf plugins added (python, nodejs)"

brew_run "asdf install python 3.10.14 && asdf set --u python 3.10.14"
info "Python 3.10.14 installed"

brew_run "asdf install nodejs 24.14.0 && asdf set --u nodejs 24.14.0"
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
header "10/10 — Zed Editor + Cleanup"
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
echo "  Kernel:    $(uname -r)"
echo "  Mesa:      $(dpkg -l libgl1-mesa-dri 2>/dev/null | awk '/^ii/{print $3}')"
echo "  PipeWire:  $(pipewire --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  Microcode: $(dpkg -l intel-microcode 2>/dev/null | awk '/^ii/{print $3}')"
echo "  fwupd:     $(fwupdmgr --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  Docker:    $(docker --version 2>/dev/null || echo 'N/A')"
echo "  Homebrew:  $(brew_run 'brew --version' 2>/dev/null | head -1 || echo 'N/A')"
echo "  Git:       $(brew_run 'git --version' 2>/dev/null || echo 'N/A')"
echo "  Fish:      $(brew_run 'fish --version' 2>/dev/null || echo 'N/A')"
echo "  Starship:  $(brew_run 'starship --version' 2>/dev/null | head -1 || echo 'N/A')"
echo "  Python:    $(brew_run '$HOME/.asdf/shims/python --version' 2>/dev/null || echo 'N/A')"
echo "  Node.js:   $(brew_run '$HOME/.asdf/shims/node --version' 2>/dev/null || echo 'N/A')"
echo "  gh:        $(brew_run 'gh --version' 2>/dev/null | head -1 || echo 'N/A')"
echo "  Zed:       $(as_user '$HOME/.local/bin/zed --version' 2>/dev/null || echo 'N/A')"
echo ""

NEEDS_REBOOT=false
if [[ -f /var/run/reboot-required ]]; then
    NEEDS_REBOOT=true
fi

if $NEEDS_REBOOT; then
    warn "Reboot required to apply all updates."
    read -rp "Reboot now? [y/N]: " answer
    if [[ "${answer,,}" == "y" ]]; then
        reboot
    fi
else
    info "No reboot required."
fi

info "Done!"
