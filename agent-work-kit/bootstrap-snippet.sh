#!/usr/bin/env bash
# bootstrap-snippet.sh — EC2 user-data/bootstrap fragment for agent-work-kit hosts.
# It installs OS packages and the official CLI installers only. It never logs in and never stores secrets.
# Review before use; run CLIs once as the target user afterwards and complete browser/device logins manually.
set -euo pipefail

INSTALL_USER="${INSTALL_USER:-ubuntu}"

# Optional initial-version pins. Leave empty for the vendor's current stable installer.
# Versioned Devin installer form: https://static.devin.ai/cli/<version>/setup.sh
DEVIN_VERSION="${DEVIN_VERSION:-}"
# Kiro installer supports: --version X.Y.Z
KIRO_CLI_VERSION="${KIRO_CLI_VERSION:-}"
# Claude installer supports an optional VERSION argument. Native Claude installations may auto-update afterwards.
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-}"

log() { printf '[agent-work bootstrap] %s\n' "$*"; }

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        log "missing root privileges for: $*"
        return 1
    fi
}

install_os_packages() {
    # OS package versions are distro-managed; pin them in your image pipeline/AMI if required.
    if command -v apt-get >/dev/null 2>&1; then
        as_root env DEBIAN_FRONTEND=noninteractive apt-get update
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            git tmux curl unzip ca-certificates python3
    elif command -v dnf >/dev/null 2>&1; then
        as_root dnf install -y git tmux curl unzip ca-certificates python3
    elif command -v yum >/dev/null 2>&1; then
        as_root yum install -y git tmux curl unzip ca-certificates python3
    else
        log "unsupported package manager; install git, tmux, curl, unzip, ca-certificates, python3 manually"
    fi
}

run_as_install_user() {
    if [ "$(id -u)" -eq 0 ] && id "$INSTALL_USER" >/dev/null 2>&1; then
        local cmd
        printf -v cmd '%q ' "$@"
        su - "$INSTALL_USER" -c "$cmd"
    else
        "$@"
    fi
}

fetch_installer() {
    local url="$1" out="$2"
    curl -fsSL "$url" -o "$out"
    chmod 0755 "$out"
}

run_official_installer() {
    local url="$1"
    shift
    local tmp
    tmp="$(mktemp)"
    fetch_installer "$url" "$tmp"
    if run_as_install_user bash "$tmp" "$@"; then
        rm -f "$tmp"
    else
        local rc=$?
        rm -f "$tmp"
        return "$rc"
    fi
}

install_devin_cli() {
    local url="https://cli.devin.ai/install.sh"
    if [ -n "$DEVIN_VERSION" ]; then
        url="https://static.devin.ai/cli/$DEVIN_VERSION/setup.sh"
    fi
    log "installing Devin CLI${DEVIN_VERSION:+ $DEVIN_VERSION} (official installer)"
    run_official_installer "$url"
}

install_kiro_cli() {
    local args=(--no-modify-path)
    if [ -n "$KIRO_CLI_VERSION" ]; then
        args+=(--version "$KIRO_CLI_VERSION")
    fi
    log "installing Kiro CLI${KIRO_CLI_VERSION:+ $KIRO_CLI_VERSION} (official installer)"
    run_official_installer "https://cli.kiro.dev/install" "${args[@]}"
}

install_claude_code() {
    local args=()
    if [ -n "$CLAUDE_CODE_VERSION" ]; then
        args+=("$CLAUDE_CODE_VERSION")
    fi
    log "installing Claude Code${CLAUDE_CODE_VERSION:+ $CLAUDE_CODE_VERSION} (official installer)"
    run_official_installer "https://claude.ai/install.sh" "${args[@]}"
}

install_os_packages
install_devin_cli
install_kiro_cli
install_claude_code

log "installation finished. Manual next steps for ${INSTALL_USER}: devin auth login, kiro-cli login, claude login (exact commands may vary)."
log "no credentials, API keys, or tokens were written by this snippet."
