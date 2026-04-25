#!/usr/bin/env bash

#
# Driver update script — Lenovo ThinkPad E14
# Ubuntu 26.04 LTS | Intel Iris Xe | Intel Tiger Lake Audio
#
# Strategy: apt for drivers/firmware/kernel (system-level)
#           Homebrew for userland tools (newer versions)
#
# Usage:
#   chmod +x update-drivers.sh   # necessário ao baixar fora do git clone
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
# Verificações iniciais
# ──────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
  err "Execute com sudo: sudo $0"
  exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
BREW="/home/linuxbrew/.linuxbrew/bin/brew"

as_user() { sudo -u "$REAL_USER" bash -c "$*"; }

brew_run() {
  as_user "eval \"\$($BREW shellenv)\" && export PATH=\"\${ASDF_DATA_DIR:-\$HOME/.asdf}/shims:\$PATH\" && $*"
}

header "Driver Update — Lenovo ThinkPad E14 (Ubuntu 26.04)"

# ──────────────────────────────────────────────
header "1/10 — Atualizando pacotes do sistema (apt)"
# ──────────────────────────────────────────────

apt update
apt upgrade -y
info "Pacotes do sistema atualizados"

# ──────────────────────────────────────────────
header "2/10 — Drivers de vídeo (Intel Iris Xe / Mesa)"
# ──────────────────────────────────────────────

# Nota: xserver-xorg-video-intel foi removido do Ubuntu 24.04+.
# O Iris Xe usa o driver 'modesetting' do kernel — não precisa de pacote adicional.
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
  info "Verificando drivers recomendados..."
  ubuntu-drivers install 2>/dev/null || warn "Nenhum driver adicional recomendado encontrado"
fi

info "Drivers de vídeo atualizados"

# ──────────────────────────────────────────────
header "3/10 — Drivers de áudio (Intel Tiger Lake / PipeWire)"
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

info "Drivers de áudio atualizados"

# ──────────────────────────────────────────────
header "4/10 — Drivers de rede (Realtek Wi-Fi/Bluetooth/Ethernet)"
# ──────────────────────────────────────────────

# Nota: 'firmware-realtek' e 'r8168-dkms' são pacotes Debian (non-free),
# não existem nos repositórios Ubuntu. O firmware Realtek já está incluído
# em 'linux-firmware'. Apenas bluez/dkms são necessários aqui.
apt install -y --only-upgrade \
  dkms \
  bluez \
  bluez-tools 2>/dev/null || true

info "Drivers de rede atualizados"

# ──────────────────────────────────────────────
header "5/10 — Firmware e drivers de segurança"
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
  info "thermald ativo"
else
  systemctl enable --now thermald 2>/dev/null || warn "Não foi possível habilitar thermald"
fi

if command -v fwupdmgr &>/dev/null; then
  info "Verificando firmware Lenovo via fwupd..."
  fwupdmgr refresh --force 2>/dev/null || true
  fwupdmgr get-updates 2>/dev/null && \
    fwupdmgr update -y 2>/dev/null || warn "Nenhuma atualização de firmware disponível"
fi

info "Firmware e drivers de segurança atualizados"

# ──────────────────────────────────────────────
header "6/10 — Dependências de build (apt) + Homebrew"
# ──────────────────────────────────────────────

apt install -y curl
info "curl instalado"

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

info "Dependências de build instaladas (apt)"

# Instala Homebrew como usuário real (não root).
#
# Fix: o installer do Homebrew verifica permissão no prefix ANTES de criar o
# diretório. Criando /home/linuxbrew/.linuxbrew como root e transferindo o
# ownership ao usuário real, o installer encontra o diretório com permissão
# correta e prossegue sem o erro "Insufficient permissions".
#
# O installer é salvo em REAL_HOME (não /tmp) pois o Ubuntu 26.04 monta /tmp
# com noexec, causando "Permission denied" mesmo após chmod +x.
if [[ ! -d /home/linuxbrew/.linuxbrew ]]; then
  # Cria o prefix como root e entrega ao usuário real
  mkdir -p /home/linuxbrew/.linuxbrew
  chown -R "$REAL_USER":"$REAL_USER" /home/linuxbrew

  BREW_INSTALLER="$REAL_HOME/.brew-install-$$.sh"
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
    -o "$BREW_INSTALLER"
  chown "$REAL_USER":"$REAL_USER" "$BREW_INSTALLER"
  chmod 755 "$BREW_INSTALLER"

  sudo -u "$REAL_USER" \
    HOME="$REAL_HOME" \
    USER="$REAL_USER" \
    LOGNAME="$REAL_USER" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NONINTERACTIVE=1 \
    /bin/bash "$BREW_INSTALLER"

  rm -f "$BREW_INSTALLER"
  info "Homebrew instalado"
else
  info "Homebrew já instalado"
fi

brew_run "brew update"
brew_run "brew install gcc"
info "Homebrew atualizado (gcc instalado)"

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
info "Docker Engine instalado (relogin necessário para mudanças de grupo)"

# ──────────────────────────────────────────────
header "8/10 — Ferramentas userland (Homebrew)"
# ──────────────────────────────────────────────

brew_run "brew install git curl wget vim fish starship gh asdf"
info "Ferramentas instaladas via Homebrew (git, curl, wget, vim, fish, starship, gh, asdf)"

BREW_FISH="$(/home/linuxbrew/.linuxbrew/bin/brew --prefix)/bin/fish"
if ! grep -qF "$BREW_FISH" /etc/shells; then
  echo "$BREW_FISH" >> /etc/shells
fi
chsh -s "$BREW_FISH" "$REAL_USER"
info "Fish shell definido como padrão (versão Homebrew)"

# ──────────────────────────────────────────────
header "9/10 — Config do shell + Linguagens (asdf)"
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

info "Fish e Starship configurados"

# Plugins asdf
brew_run "asdf plugin add python || true"
brew_run "asdf plugin add nodejs || true"
info "Plugins asdf adicionados (python, nodejs)"

# FIX: flag correta é '--home', não '--u' (--u não existe no asdf)
brew_run "asdf install python 3.10.14 && asdf set --home python 3.10.14"
info "Python 3.10.14 instalado"

brew_run "asdf install nodejs 24.14.0 && asdf set --home nodejs 24.14.0"
info "Node.js 24.14.0 instalado"

if brew_run "node --version >/dev/null && npm --version >/dev/null"; then
  info "Node.js e npm disponíveis via asdf shims"
else
  err "Node.js/npm não encontrado no PATH após setup do asdf"
  exit 1
fi

brew_run "npm install -g aicommits"
info "aicommits instalado"

# ──────────────────────────────────────────────
header "10/10 — Zed Editor + Limpeza"
# ──────────────────────────────────────────────

as_user 'curl -f https://zed.dev/install.sh | sh'
info "Zed editor instalado"

apt autoremove -y
apt autoclean -y
brew_run "brew cleanup"
info "Limpeza concluída"

# ──────────────────────────────────────────────
header "Resumo"
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
  warn "Reboot necessário para aplicar todas as atualizações."
  read -rp "Reiniciar agora? [y/N]: " answer
  if [[ "${answer,,}" == "y" ]]; then
    reboot
  fi
else
  info "Sem necessidade de reboot."
fi

info "Pronto!"
