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
PACKAGES="git curl wget jq unzip htop tree tmux vim zsh make gcc python3 python3-pip python3-venv"
INSTALL_DOCKER=true
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

log() {
  echo "[bootstrap] $*"
}

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

install_docker() {
  if [[ "$INSTALL_DOCKER" != "true" ]]; then
    return
  fi

  if command -v docker &>/dev/null; then
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
}

install_node() {
  if [[ "$INSTALL_NODE" != "true" ]]; then
    return
  fi

  if command -v node &>/dev/null; then
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

  if command -v conda &>/dev/null; then
    log "Conda is already installed."
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
  if command -v zsh &>/dev/null; then
    "$ANACONDA_PREFIX/bin/conda" init zsh || true
  fi

  log "Conda installed. You can use 'conda' in a new session."
}

setup_shell() {
  if [[ "$INSTALL_ZSH" != "true" ]]; then
    return
  fi

  if ! command -v zsh &>/dev/null; then
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

main() {
  log "Starting development environment bootstrap..."
  install_packages
  install_docker
  install_node
  setup_shell
  setup_dotfiles
  install_anaconda
  log "Bootstrap complete. Changes for the docker group, shell, and conda take effect in a new session."
}

main "$@"
