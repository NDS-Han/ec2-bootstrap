#!/usr/bin/env bash
# shellcheck shell=bash
# Common helpers for agent-work-kit scripts. This file is meant to be sourced, not executed.

_aw_bin_dir() {
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P
}

AW_BIN_DIR="$(_aw_bin_dir)"
AW_DEFAULT_WORK_DIR="$(cd -- "$AW_BIN_DIR/.." >/dev/null 2>&1 && pwd -P)"

if [ -n "${AGENT_WORK_ENV:-}" ]; then
    AW_ENV_FILE="$AGENT_WORK_ENV"
else
    AW_ENV_FILE="${WORK_DIR:-$AW_DEFAULT_WORK_DIR}/agent-work.env"
fi

if [ -f "$AW_ENV_FILE" ]; then
    # Environment variables explicitly set by the caller override the file.
    # Save/restore is needed because plain `source` assignment would otherwise win.
    declare -A _aw_saved=()
    declare -A _aw_was_set=()
    while IFS= read -r _aw_key; do
        if [ -n "${!_aw_key+x}" ]; then
            _aw_was_set[$_aw_key]=1
            _aw_saved[$_aw_key]="${!_aw_key}"
        fi
    done < <(sed -n -E 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\2/p' "$AW_ENV_FILE")
    set -a
    # shellcheck disable=SC1090
    . "$AW_ENV_FILE"
    set +a
    for _aw_key in "${!_aw_was_set[@]}"; do
        printf -v "$_aw_key" '%s' "${_aw_saved[$_aw_key]}"
    done
    unset _aw_key
elif [ -z "${REPO_DIR:-}" ]; then
    echo "agent-work: missing $AW_ENV_FILE (copy agent-work.env.example or set AGENT_WORK_ENV)" >&2
    if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 1; else exit 1; fi
fi

WORK_DIR="${WORK_DIR:-$AW_DEFAULT_WORK_DIR}"
BASE_BRANCH="${BASE_BRANCH:-origin/main}"
PROTECTED_BRANCHES="${PROTECTED_BRANCHES:-main master}"
DEPLOY_CMD="${DEPLOY_CMD:-./deploy}"
SERVICES="${SERVICES:-}"
PROTECTED_FILES="${PROTECTED_FILES:-}"
HOT_PATH_DIRS="${HOT_PATH_DIRS:-}"
DEVIN_BIN="${DEVIN_BIN:-devin}"
DEVIN_MODEL="${DEVIN_MODEL:-swe-2-1-max}"
DEVIN_PERMISSION_MODE="${DEVIN_PERMISSION_MODE:-dangerous}"
DEVIN_VERBOSITY="${DEVIN_VERBOSITY:-3}"
KIRO_BIN="${KIRO_BIN:-kiro-cli}"
KIRO_AGENT="${KIRO_AGENT:-project-impl}"
KIRO_EFFORT="${KIRO_EFFORT:-high}"
KIRO_ALLOW_MAX="${KIRO_ALLOW_MAX:-0}"
MAX_CONCURRENT="${MAX_CONCURRENT:-2}"
MAX_ROUNDS="${MAX_ROUNDS:-5}"
REPORT_LANG="${REPORT_LANG:-ko}"
AUTO_XREVIEW="${AUTO_XREVIEW:-1}"
REVIEW_TIMEOUT_SEC="${REVIEW_TIMEOUT_SEC:-5400}"
DEPENDENCY_POLL_SEC="${DEPENDENCY_POLL_SEC:-60}"
COMMIT_STYLE="${COMMIT_STYLE:-type(scope): concise summary}"
CLAUDE_REVIEW_TASKS="${CLAUDE_REVIEW_TASKS:-}"
WORKTREE_LINKS="${WORKTREE_LINKS:-}"

: "${REPO_DIR:?REPO_DIR is required in agent-work.env or the environment}"

aw_die() {
    echo "agent-work: $*" >&2
    exit 1
}

aw_require_task() {
    case "${1:-}" in
        ""|*[!A-Za-z0-9._-]*)
            aw_die "invalid task id '${1:-}' (use letters, digits, dot, underscore, dash)"
            ;;
    esac
}

aw_task_dir() {
    printf '%s/%s' "$WORK_DIR" "$1"
}

aw_spec_file() {
    printf '%s/%s/SPEC.md' "$WORK_DIR" "$1"
}

aw_branch_line() {
    local spec line
    spec="$(aw_spec_file "$1")"
    [ -f "$spec" ] || aw_die "missing $spec"
    # shellcheck disable=SC2016  # backticks are literal SPEC markdown, not command substitution
    line=$(grep -m1 -E '^\*\*Branch:\*\* `[^`]+` from \*\*(local )?`[^`]+`\*\*' "$spec" || true)
    [ -n "$line" ] || aw_die "cannot parse '**Branch:** \`X\` from **\`Y\`**' in $spec"
    printf '%s\n' "$line"
}

aw_spec_branch() {
    # shellcheck disable=SC2016  # backticks are literal SPEC markdown
    aw_branch_line "$1" | sed -E 's/^\*\*Branch:\*\* `([^`]+)`.*/\1/'
}

aw_spec_base() {
    # shellcheck disable=SC2016  # backticks are literal SPEC markdown
    aw_branch_line "$1" | sed -E 's/^.*`([^`]+)`\*\*.*$/\1/'
}

aw_list_contains() {
    local needle="$1" list="$2" item
    for item in $list; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

aw_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

aw_shell_join() {
    local out="" arg qarg
    for arg in "$@"; do
        printf -v qarg '%q' "$arg"
        out+=" $qarg"
    done
    printf '%s' "${out# }"
}

aw_tmux_running() {
    local session="$1" task="$2"
    tmux has-session -t "$session" 2>/dev/null && grep -q '^running' "$WORK_DIR/$task/STATUS" 2>/dev/null
}
