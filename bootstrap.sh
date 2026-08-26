#!/bin/bash
set -euo pipefail

# EC2 개발환경 부트스트랩
# 사용법:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
#
# 또는 원격에서 실행:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/bootstrap.sh | bash

# 상단 변수를 필요에 따라 수정하세요.
PACKAGES="git curl wget jq unzip htop tree tmux vim zsh make gcc python3 python3-pip python3-venv"
INSTALL_DOCKER=true
INSTALL_NODE=false
NODE_VERSION="20"          # NodeSource LTS 버전
DOTFILES_REPO="git@github.com:NDS-Han/ec2-bootstrap.git"
DOTFILES_INSTALL_SCRIPT="" # dotfiles 안의 설치 스크립트 경로 (예: install.sh)
INSTALL_ANACONDA=true
ANACONDA_INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
# 전체 Anaconda를 설치하려면 위 URL을 Anaconda installer URL로 교체하세요.
ANACONDA_PREFIX="$HOME/miniconda3"
CONDA_PYTHON_VERSION="3.12"  # 비어 있으면 base에 Python을 별도 설치하지 않음
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
    log "지원하지 않는 패키지 매니저입니다. Amazon Linux / Ubuntu 계열 OS에서 실행해주세요."
    exit 1
  fi

  log "기본 패키지 설치: $PACKAGES"
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
    log "Docker가 이미 설치되어 있습니다."
  else
    log "Docker 설치 중..."
    curl -fsSL https://get.docker.com | sh
    sudo systemctl enable --now docker
  fi

  if id -nG "$USER" 2>/dev/null | grep -qw docker; then
    log "사용자가 이미 docker 그룹에 있습니다."
  else
    log "사용자를 docker 그룹에 추가합니다."
    sudo usermod -aG docker "$USER" || true
  fi
}

install_node() {
  if [[ "$INSTALL_NODE" != "true" ]]; then
    return
  fi

  if command -v node &>/dev/null; then
    log "Node.js가 이미 설치되어 있습니다."
    return
  fi

  log "Node.js v${NODE_VERSION} 설치 중..."
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
    log "Conda가 이미 설치되어 있습니다."
    return
  fi

  log "Conda 설치 중: $ANACONDA_INSTALLER_URL"
  local installer
  installer="/tmp/anaconda_installer.sh"
  wget -q "$ANACONDA_INSTALLER_URL" -O "$installer"
  chmod +x "$installer"
  "$installer" -b -p "$ANACONDA_PREFIX"
  rm -f "$installer"

  if [[ -n "$CONDA_PYTHON_VERSION" ]]; then
    log "Conda base에 Python $CONDA_PYTHON_VERSION 설치 중..."
    "$ANACONDA_PREFIX/bin/conda" install -y -n base "python=$CONDA_PYTHON_VERSION"
  fi

  # shell에서 conda를 사용할 수 있도록 초기화
  "$ANACONDA_PREFIX/bin/conda" init bash || true
  if command -v zsh &>/dev/null; then
    "$ANACONDA_PREFIX/bin/conda" init zsh || true
  fi

  log "Conda 설치 완료. 새 세션에서 'conda' 명령어를 사용할 수 있습니다."
}

setup_shell() {
  if [[ "$INSTALL_ZSH" != "true" ]]; then
    return
  fi

  if ! command -v zsh &>/dev/null; then
    log "zsh이 설치되지 않았습니다. 기본 패키지에 포함되어 있는지 확인하세요."
    return
  fi

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Oh My Zsh 설치 중..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  if [[ "$INSTALL_P10K" == "true" ]]; then
    local p10k_dir
    p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
      log "Powerlevel10k 설치 중..."
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi
  fi

  local zsh_custom
  zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  local plugins_dir
  plugins_dir="$zsh_custom/plugins"
  mkdir -p "$plugins_dir"

  if [[ ! -d "$plugins_dir/zsh-autosuggestions" ]]; then
    log "zsh-autosuggestions 설치 중..."
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$plugins_dir/zsh-autosuggestions"
  fi

  if [[ ! -d "$plugins_dir/zsh-syntax-highlighting" ]]; then
    log "zsh-syntax-highlighting 설치 중..."
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugins_dir/zsh-syntax-highlighting"
  fi

  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    log "기본 셸을 zsh로 변경합니다..."
    sudo chsh -s "$(command -v zsh)" "$USER" || true
  fi
}

setup_dotfiles() {
  if [[ -z "$DOTFILES_REPO" ]]; then
    return
  fi

  local dest="$HOME/dotfiles"
  log "dotfiles 클론: $DOTFILES_REPO"
  rm -rf "$dest"
  git clone "$DOTFILES_REPO" "$dest"

  if [[ -n "$DOTFILES_INSTALL_SCRIPT" && -x "$dest/$DOTFILES_INSTALL_SCRIPT" ]]; then
    log "dotfiles 설치 스크립트 실행: $DOTFILES_INSTALL_SCRIPT"
    (cd "$dest" && ./"$DOTFILES_INSTALL_SCRIPT")
  else
    log "dotfiles 파일을 $HOME에 복사합니다..."
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
  log "개발환경 부트스트랩을 시작합니다..."
  install_packages
  install_docker
  install_node
  setup_shell
  setup_dotfiles
  install_anaconda
  log "부트스트랩 완료. docker 그룹과 셸, conda 변경사항은 새 세션부터 적용됩니다."
}

main "$@"
