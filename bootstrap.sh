#!/bin/bash
set -euo pipefail

# EC2 development environment bootstrap
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
#
# Or run remotely:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/bootstrap.sh | bash

# Modify the variables at the top as needed.
PACKAGES="git curl wget jq unzip htop tree tmux vim zsh make gcc"
INSTALL_DOCKER=true
INSTALL_AWSCLI=true
INSTALL_NODE=false
NODE_VERSION="20"          # NodeSource LTS version
DOTFILES_REPO="git@github.com:NDS-Han/ec2-bootstrap.git"
DOTFILES_INSTALL_SCRIPT="" # Path to an install script inside the dotfiles repo (e.g., install.sh)
INSTALL_ANACONDA=true
ANACONDA_INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
# Replace the URL above with the Anaconda installer URL to install the full Anaconda distribution.
ANACONDA_PREFIX="$HOME/miniconda3"
CONDA_PYTHON_VERSION="3.12"  # Leave empty to skip installing a specific Python in the base environment.
INSTALL_ZSH=true
INSTALL_P10K=true

log() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

detect_pkg_manager() {
  if command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  elif command -v apt-get &>/dev/null; then
    echo "apt"
  else
    echo "unknown"
  fi
}

install_packages() {
  local pkg_mgr
  pkg_mgr=$(detect_pkg_manager)

  if [[ "$pkg_mgr" == "unknown" ]]; then
    log "Unsupported package manager. Please run on an Amazon Linux or Ubuntu based OS."
    exit 1
  fi

  log "Installing base packages: $PACKAGES"
  case "$pkg_mgr" in
    dnf|yum)
      sudo "$pkg_mgr" update -y
      sudo "$pkg_mgr" install -y $PACKAGES
      ;;
    apt)
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGES
      ;;
  esac
}

install_awscli() {
  if [[ "$INSTALL_AWSCLI" != "true" ]]; then
    return
  fi

  if have aws; then
    log "AWS CLI is already installed."
    return
  fi

  log "Installing AWS CLI..."
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64)
      arch="x86_64"
      ;;
    aarch64|arm64)
      arch="aarch64"
      ;;
    *)
      log "Unsupported architecture for AWS CLI: $arch"
      return
      ;;
  esac

  local aws_zip
  aws_zip="/tmp/awscliv2.zip"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o "$aws_zip"
  unzip -q "$aws_zip" -d /tmp
  sudo /tmp/aws/install --update
  rm -rf /tmp/aws "$aws_zip"
}

install_docker() {
  if [[ "$INSTALL_DOCKER" != "true" ]]; then
    return
  fi

  if have docker; then
    log "Docker is already installed."
  else
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo systemctl enable --now docker
  fi

  if id -nG "$USER" 2>/dev/null | grep -qw docker; then
    log "User is already in the docker group."
  else
    log "Adding user to the docker group."
    sudo usermod -aG docker "$USER" || true
  fi

  # Ensure BuildKit is the default builder (idempotent)
  if [[ "$(sudo cat /etc/docker/daemon.json 2>/dev/null | jq -r '.features.buildkit' 2>/dev/null)" != "true" ]]; then
    log "Enabling Docker BuildKit in /etc/docker/daemon.json"
    sudo mkdir -p /etc/docker
    local existing
    existing=$(sudo cat /etc/docker/daemon.json 2>/dev/null || echo '{}')
    echo "$existing" | jq '.features.buildkit = true' | sudo tee /etc/docker/daemon.json >/dev/null
    sudo systemctl restart docker || true
  else
    log "Docker BuildKit already enabled — skipping"
  fi
}

install_node() {
  if [[ "$INSTALL_NODE" != "true" ]]; then
    return
  fi

  if have node; then
    log "Node.js is already installed."
    return
  fi

  log "Installing Node.js v${NODE_VERSION}..."
  if command -v apt-get &>/dev/null; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -
    sudo apt-get install -y nodejs
  elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
    curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION}.x" | sudo bash -
    sudo dnf install -y nodejs || sudo yum install -y nodejs
  fi
}

install_anaconda() {
  if [[ "$INSTALL_ANACONDA" != "true" ]]; then
    return
  fi

  if have conda; then
    log "Conda is already installed."
    return
  fi

  if [[ -d "$ANACONDA_PREFIX" ]]; then
    log "Conda prefix already exists at $ANACONDA_PREFIX. Skipping installation."
    return
  fi

  log "Installing Conda: $ANACONDA_INSTALLER_URL"
  local installer
  installer="/tmp/anaconda_installer.sh"
  wget -q "$ANACONDA_INSTALLER_URL" -O "$installer"
  chmod +x "$installer"
  "$installer" -b -p "$ANACONDA_PREFIX"
  rm -f "$installer"

  if [[ -n "$CONDA_PYTHON_VERSION" ]]; then
    log "Installing Python $CONDA_PYTHON_VERSION in the Conda base environment..."
    "$ANACONDA_PREFIX/bin/conda" install -y -n base "python=$CONDA_PYTHON_VERSION"
  fi

  # Initialize conda for the shell
  "$ANACONDA_PREFIX/bin/conda" init bash || true
  if have zsh; then
    "$ANACONDA_PREFIX/bin/conda" init zsh || true
  fi

  log "Conda installed. You can use 'conda' in a new session."
}

setup_shell() {
  if [[ "$INSTALL_ZSH" != "true" ]]; then
    return
  fi

  if ! have zsh; then
    log "zsh is not installed. Make sure it's included in the base packages."
    return
  fi

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  if [[ "$INSTALL_P10K" == "true" ]]; then
    local p10k_dir
    p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
      log "Installing Powerlevel10k..."
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi
  fi

  local zsh_custom
  zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  local plugins_dir
  plugins_dir="$zsh_custom/plugins"
  mkdir -p "$plugins_dir"

  if [[ ! -d "$plugins_dir/zsh-autosuggestions" ]]; then
    log "Installing zsh-autosuggestions..."
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$plugins_dir/zsh-autosuggestions"
  fi

  if [[ ! -d "$plugins_dir/zsh-syntax-highlighting" ]]; then
    log "Installing zsh-syntax-highlighting..."
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugins_dir/zsh-syntax-highlighting"
  fi

  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    log "Changing default shell to zsh..."
    sudo chsh -s "$(command -v zsh)" "$USER" || true
  fi
}

setup_dotfiles() {
  if [[ -z "$DOTFILES_REPO" ]]; then
    return
  fi

  local dest="$HOME/dotfiles"
  log "Cloning dotfiles: $DOTFILES_REPO"
  rm -rf "$dest"
  git clone "$DOTFILES_REPO" "$dest"

  if [[ -n "$DOTFILES_INSTALL_SCRIPT" && -x "$dest/$DOTFILES_INSTALL_SCRIPT" ]]; then
    log "Running dotfiles install script: $DOTFILES_INSTALL_SCRIPT"
    (cd "$dest" && ./"$DOTFILES_INSTALL_SCRIPT")
  else
    log "Copying dotfiles to $HOME..."
    while IFS= read -r f; do
      name=$(basename "$f")
      if [[ -d "$f" ]]; then
        cp -RT "$f" "$HOME/$name"
      else
        cp -f "$f" "$HOME/$name"
      fi
    done < <(find "$dest" -maxdepth 1 -name '.[^.]*' ! -name '.git' ! -name '.DS_Store' ! -name '.gitignore' ! -name '.gitattributes')
  fi
}

verify_installations() {
  log "Verifying installations"
  local fail=0
  local v

  if have aws; then
    v=$(aws --version 2>&1 | head -1)
    printf '  %-10s %-40s [OK]\n' "aws:" "$v"
  else
    printf '  %-10s %-40s [FAIL] not installed\n' "aws:" "—"
    fail=1
  fi

  if have docker; then
    v=$(docker --version 2>&1 | head -1)
    printf '  %-10s %-40s [OK]\n' "docker:" "$v"
  else
    printf '  %-10s %-40s [FAIL] not installed\n' "docker:" "—"
    fail=1
  fi

  if have python3; then
    v=$(python3 --version 2>&1 | head -1)
    printf '  %-10s %-40s [OK]\n' "python:" "$v"
  elif [[ -x "$ANACONDA_PREFIX/bin/python" ]]; then
    v=$("$ANACONDA_PREFIX/bin/python" --version 2>&1 | head -1)
    printf '  %-10s %-40s [OK]\n' "python:" "$v"
  else
    printf '  %-10s %-40s [FAIL] not installed\n' "python:" "—"
    fail=1
  fi

  if [[ "$INSTALL_ANACONDA" == "true" ]]; then
    if [[ -x "$ANACONDA_PREFIX/bin/conda" ]]; then
      v=$("$ANACONDA_PREFIX/bin/conda" --version 2>&1 | head -1)
      printf '  %-10s %-40s [OK]\n' "conda:" "$v"
    else
      printf '  %-10s %-40s [FAIL] not installed\n' "conda:" "—"
      fail=1
    fi
  fi

  if have git; then
    v=$(git --version 2>&1 | head -1)
    printf '  %-10s %-40s [OK]\n' "git:" "$v"
  else
    printf '  %-10s %-40s [FAIL] not installed\n' "git:" "—"
    fail=1
  fi

  if have zsh; then
    v=$(zsh --version 2>&1 | head -1)
    printf '  %-10s %-40s [OK]\n' "zsh:" "$v"
  else
    printf '  %-10s %-40s [FAIL] not installed\n' "zsh:" "—"
    fail=1
  fi

  if [[ "$INSTALL_NODE" == "true" ]]; then
    if have node; then
      v=$(node --version 2>&1 | head -1)
      printf '  %-10s %-40s [OK]\n' "node:" "$v"
    else
      printf '  %-10s %-40s [FAIL] not installed\n' "node:" "—"
      fail=1
    fi
  fi

  if [[ "$fail" -ne 0 ]]; then
    log "Verification failed. Please fix the missing tools and re-run."
    exit 1
  fi
}

main() {
  log "Starting development environment bootstrap..."
  install_packages
  install_awscli
  install_docker
  install_node
  setup_shell
  setup_dotfiles
  install_anaconda
  verify_installations
  log "Bootstrap complete. Changes for the docker group, shell, and conda take effect in a new session."
}

main "$@"
