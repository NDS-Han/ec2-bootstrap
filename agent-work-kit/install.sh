#!/usr/bin/env bash
# install.sh — install agent-work-kit into a git repository.
# Idempotent. Never logs in to any service and never stores or prints secrets.
set -euo pipefail

usage() {
    cat <<'USAGE'
usage: install.sh [--force] [REPO_DIR]

Installs the kit into REPO_DIR/.agent-work (or WORK_DIR if set), adds that work dir to
the repository's git exclude file, installs Devin/Kiro hook configuration, and checks for
required tools. Existing local customizations are preserved unless --force is given; when
a newer kit version differs, a *.kit-update file is written for manual merge.
USAGE
}

FORCE=0
REPO_ARG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            if [ -n "$REPO_ARG" ]; then
                echo "install.sh: unexpected extra argument: $1" >&2
                usage >&2
                exit 2
            fi
            REPO_ARG="$1"
            ;;
    esac
    shift
done

command -v git >/dev/null 2>&1 || { echo "install.sh: git is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "install.sh: python3 is required" >&2; exit 1; }

KIT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
if [ -z "$REPO_ARG" ]; then
    REPO_ARG="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -n "$REPO_ARG" ] || { echo "install.sh: pass REPO_DIR or run inside a git repository" >&2; exit 1; }
[ -d "$REPO_ARG" ] || { echo "install.sh: not a directory: $REPO_ARG" >&2; exit 1; }
REPO_DIR="$(cd -- "$REPO_ARG" >/dev/null 2>&1 && pwd -P)"
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || { echo "install.sh: not a git repository: $REPO_DIR" >&2; exit 1; }

WORK_DIR="${WORK_DIR:-$REPO_DIR/.agent-work}"
case "$WORK_DIR" in
    /*) ;;
    *) WORK_DIR="$REPO_DIR/$WORK_DIR" ;;
esac
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd -- "$WORK_DIR" >/dev/null 2>&1 && pwd -P)"
PROJECT_NAME="${PROJECT_NAME:-$(basename -- "$REPO_DIR")}"
PROJECT_SLUG="$(printf '%s' "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[ -n "$PROJECT_SLUG" ] || PROJECT_SLUG="project"

BASE_BRANCH="${BASE_BRANCH:-origin/main}"
PROTECTED_BRANCHES="${PROTECTED_BRANCHES:-main master}"
DEPLOY_CMD="${DEPLOY_CMD:-./deploy}"
SERVICES="${SERVICES:-}"
PROTECTED_FILES="${PROTECTED_FILES:-}"
HOT_PATH_DIRS="${HOT_PATH_DIRS:-}"
COMMIT_STYLE="${COMMIT_STYLE:-type(scope): concise summary}"
DEVIN_BIN="${DEVIN_BIN:-devin}"
DEVIN_MODEL="${DEVIN_MODEL:-swe-2-1-max}"
DEVIN_PERMISSION_MODE="${DEVIN_PERMISSION_MODE:-dangerous}"
DEVIN_VERBOSITY="${DEVIN_VERBOSITY:-3}"
DEVIN_CONFIG="${DEVIN_CONFIG:-$WORK_DIR/devin/config.json}"
KIRO_BIN="${KIRO_BIN:-kiro-cli}"
KIRO_AGENT="${KIRO_AGENT:-$PROJECT_SLUG-impl}"
KIRO_AGENT_MAX="${KIRO_AGENT_MAX:-$KIRO_AGENT-max}"
KIRO_EFFORT="${KIRO_EFFORT:-high}"
KIRO_ALLOW_MAX="${KIRO_ALLOW_MAX:-0}"
MAX_CONCURRENT="${MAX_CONCURRENT:-2}"
MAX_ROUNDS="${MAX_ROUNDS:-5}"
QUEUE_TASKS="${QUEUE_TASKS:-}"
QUEUE_START_STAGGER_SEC="${QUEUE_START_STAGGER_SEC:-15}"
DEPENDENCY_POLL_SEC="${DEPENDENCY_POLL_SEC:-60}"
AUTO_XREVIEW="${AUTO_XREVIEW:-1}"
REVIEW_TIMEOUT_SEC="${REVIEW_TIMEOUT_SEC:-5400}"
CLAUDE_REVIEW_TASKS="${CLAUDE_REVIEW_TASKS:-}"
REPORT_LANG="${REPORT_LANG:-ko}"
ALLOWED_RM_ROOTS="${ALLOWED_RM_ROOTS:-$WORK_DIR /tmp}"
WORKTREE_LINKS="${WORKTREE_LINKS:-}"
HOOK_PATH="$WORK_DIR/hooks/guard-hook.py"
KIRO_HOME="${KIRO_HOME:-$HOME/.kiro}"
KIRO_STEERING_FILE="$KIRO_HOME/steering/$PROJECT_SLUG.md"
KIRO_AGENT_FILE="$KIRO_HOME/agents/$KIRO_AGENT.json"

export PROJECT_NAME PROJECT_SLUG REPO_DIR WORK_DIR BASE_BRANCH PROTECTED_BRANCHES DEPLOY_CMD SERVICES \
    PROTECTED_FILES HOT_PATH_DIRS COMMIT_STYLE DEVIN_BIN DEVIN_MODEL DEVIN_PERMISSION_MODE DEVIN_VERBOSITY DEVIN_CONFIG \
    KIRO_BIN KIRO_AGENT KIRO_AGENT_MAX KIRO_EFFORT KIRO_ALLOW_MAX MAX_CONCURRENT MAX_ROUNDS QUEUE_TASKS \
    QUEUE_START_STAGGER_SEC DEPENDENCY_POLL_SEC AUTO_XREVIEW REVIEW_TIMEOUT_SEC CLAUDE_REVIEW_TASKS \
    REPORT_LANG ALLOWED_RM_ROOTS WORKTREE_LINKS HOOK_PATH KIRO_STEERING_FILE KIRO_AGENT_FILE
AW_RENDER_KEYS="PROJECT_NAME PROJECT_SLUG REPO_DIR WORK_DIR BASE_BRANCH PROTECTED_BRANCHES DEPLOY_CMD SERVICES PROTECTED_FILES HOT_PATH_DIRS COMMIT_STYLE DEVIN_BIN DEVIN_MODEL DEVIN_PERMISSION_MODE DEVIN_VERBOSITY DEVIN_CONFIG KIRO_BIN KIRO_AGENT KIRO_AGENT_MAX KIRO_EFFORT KIRO_ALLOW_MAX MAX_CONCURRENT MAX_ROUNDS QUEUE_TASKS QUEUE_START_STAGGER_SEC DEPENDENCY_POLL_SEC AUTO_XREVIEW REVIEW_TIMEOUT_SEC CLAUDE_REVIEW_TASKS REPORT_LANG ALLOWED_RM_ROOTS WORKTREE_LINKS HOOK_PATH KIRO_STEERING_FILE KIRO_AGENT_FILE"
export AW_RENDER_KEYS

CHANGED=0

render_template_file() {
    python3 - "$1" "$2" <<'PY'
import json
import os
import shlex
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
text = src.read_text(encoding="utf-8")
keys = os.environ.get("AW_RENDER_KEYS", "").split()
values = {key: os.environ.get(key, "") for key in keys}

for key in sorted(values, key=len, reverse=True):
    value = values[key]
    text = text.replace(f"@@{key}_SH@@", shlex.quote(value))
    text = text.replace(f"__{key}_JSON__", json.dumps(value)[1:-1])
    text = text.replace(f"__{key}__", value)
    text = text.replace("${" + key + "}", value)

text = text.replace("<PROJECT>", values.get("PROJECT_NAME", "<PROJECT>"))
dst.write_text(text, encoding="utf-8")
PY
}

install_managed_file() {
    # Managed files are byte-for-byte copies of the kit. In particular, shell scripts must
    # not have variable expansions rewritten at install time; only seed/config files are rendered.
    local src="$1" dst="$2" mode="$3"
    mkdir -p "$(dirname -- "$dst")"
    if [ -e "$dst" ] && cmp -s "$src" "$dst"; then
        return 0
    fi
    install -m "$mode" "$src" "$dst"
    CHANGED=$((CHANGED + 1))
    printf 'installed/updated %s\n' "$dst"
}

install_seed_file() {
    local src="$1" dst="$2" mode="$3" tmp update
    tmp="$(mktemp)"
    render_template_file "$src" "$tmp"
    mkdir -p "$(dirname -- "$dst")"
    if [ ! -e "$dst" ]; then
        install -m "$mode" "$tmp" "$dst"
        rm -f "$tmp"
        CHANGED=$((CHANGED + 1))
        printf 'installed %s\n' "$dst"
        return 0
    fi
    if cmp -s "$tmp" "$dst"; then
        rm -f "$tmp"
        return 0
    fi
    if [ "$FORCE" = 1 ]; then
        install -m "$mode" "$tmp" "$dst"
        rm -f "$tmp"
        CHANGED=$((CHANGED + 1))
        printf 'force-updated %s\n' "$dst"
        return 0
    fi
    update="$dst.kit-update"
    if [ ! -e "$update" ] || ! cmp -s "$tmp" "$update"; then
        install -m "$mode" "$tmp" "$update"
        CHANGED=$((CHANGED + 1))
        printf 'wrote update candidate %s\n' "$update"
    fi
    rm -f "$tmp"
    printf 'preserved existing %s (kit version differs; see %s)\n' "$dst" "$update" >&2
}

mkdir -p "$WORK_DIR/bin" "$WORK_DIR/hooks" "$WORK_DIR/templates/task" "$WORK_DIR/devin" "$WORK_DIR/kiro" "$WORK_DIR/harness" "$WORK_DIR/wt"

for f in _common.sh _job _prep_wt devin-run kiro-run work-queue queue-extra after-done review-task watch; do
    install_managed_file "$KIT_DIR/bin/$f" "$WORK_DIR/bin/$f" 0755
done
for f in guard-hook.py test_guard_hook.py; do
    install_managed_file "$KIT_DIR/hooks/$f" "$WORK_DIR/hooks/$f" 0755
done
for f in SPEC.md REPORT.md HANDOFF.md SUMMARY.md REVIEW_BY_CLAUDE.md DEPLOYED.md; do
    install_managed_file "$KIT_DIR/templates/task/$f" "$WORK_DIR/templates/task/$f" 0644
done
install_managed_file "$KIT_DIR/harness/README.md" "$WORK_DIR/harness/README.md" 0644
install_managed_file "$KIT_DIR/devin/config.template.json" "$WORK_DIR/devin/config.template.json" 0644
install_managed_file "$KIT_DIR/kiro/agent.template.json" "$WORK_DIR/kiro/agent.template.json" 0644
install_managed_file "$KIT_DIR/kiro/steering.template.md" "$WORK_DIR/kiro/steering.template.md" 0644
install_managed_file "$KIT_DIR/agent-work.env.example" "$WORK_DIR/agent-work.env.example" 0644
install_managed_file "$KIT_DIR/bootstrap-snippet.sh" "$WORK_DIR/bootstrap-snippet.sh" 0644
install_managed_file "$KIT_DIR/README.ko.md" "$WORK_DIR/README.ko.md" 0644

# Local project customizations: create if absent, preserve if edited.
install_seed_file "$KIT_DIR/AGENTS.template.md" "$WORK_DIR/AGENTS.md" 0644
install_seed_file "$KIT_DIR/REVIEW.template.md" "$WORK_DIR/REVIEW.md" 0644
install_seed_file "$KIT_DIR/agent-work.env.example" "$WORK_DIR/agent-work.env" 0600
install_seed_file "$KIT_DIR/devin/config.template.json" "$DEVIN_CONFIG" 0644
install_seed_file "$KIT_DIR/kiro/steering.template.md" "$KIRO_STEERING_FILE" 0644
install_seed_file "$KIT_DIR/kiro/agent.template.json" "$KIRO_AGENT_FILE" 0644

# Add the work directory to git's local exclude file (not a committed .gitignore).
case "$WORK_DIR" in
    "$REPO_DIR"/*)
        rel_work="${WORK_DIR#"$REPO_DIR"/}"
        exclude_line="$rel_work/"
        git_common="$(git -C "$REPO_DIR" rev-parse --git-common-dir)"
        case "$git_common" in
            /*) ;;
            *) git_common="$REPO_DIR/$git_common" ;;
        esac
        exclude_file="$git_common/info/exclude"
        mkdir -p "$(dirname -- "$exclude_file")"
        touch "$exclude_file"
        if ! grep -qxF "$exclude_line" "$exclude_file"; then
            printf '\n%s\n' "$exclude_line" >> "$exclude_file"
            CHANGED=$((CHANGED + 1))
            printf 'added %s to %s\n' "$exclude_line" "$exclude_file"
        fi
        ;;
    *)
        printf 'note: WORK_DIR is outside REPO_DIR; no git exclude entry added\n'
        ;;
esac

printf '\nTool check:\n'
missing=0
for tool in git tmux python3 kiro-cli devin claude; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '  ok      %s (%s)\n' "$tool" "$(command -v "$tool")"
    else
        printf '  missing %s\n' "$tool"
        missing=$((missing + 1))
    fi
done
if [ "$missing" -gt 0 ]; then
    printf 'install.sh: %s tool(s) missing; install them before using the corresponding runner. No login was attempted.\n' "$missing" >&2
fi

if [ "$CHANGED" -eq 0 ]; then
    printf 'install.sh: no changes\n'
else
    printf 'install.sh: complete (%s item(s) installed/updated)\n' "$CHANGED"
fi
printf 'next: edit %s/agent-work.env, then review %s/AGENTS.md; logins for devin/kiro/claude remain manual.\n' "$WORK_DIR" "$WORK_DIR"
