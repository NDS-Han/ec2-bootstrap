#!/usr/bin/env python3
"""PreToolUse guard for agent-work-kit.

Reads a hook event JSON document on stdin, extracts shell commands and edited file paths,
and exits 2 (with the reason on stderr) when a forbidden action is detected. Exit 0 allows
the tool call. The hook is local-only and performs no network access.

Configuration comes from environment variables, falling back to agent-work.env beside the
installed work directory (the parent of this hooks/ directory):
  PROTECTED_BRANCHES  space/comma-separated branch names (default: main master)
  DEPLOY_CMD          deploy command(s), space/comma-separated (default: ./deploy)
  PROTECTED_FILES     space-separated paths, relative to REPO_DIR unless absolute
  ALLOWED_RM_ROOTS    space-separated roots for recursive rm (default: WORK_DIR and /tmp)
  REPO_DIR, WORK_DIR  repository and agent workspace roots
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

HOOK_DIR = Path(__file__).resolve().parent
DEFAULT_WORK_DIR = HOOK_DIR.parent


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return values
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[7:].strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            continue
        value = value.strip()
        try:
            parts = shlex.split(value, posix=True)
            value = parts[0] if len(parts) == 1 else " ".join(parts)
        except ValueError:
            value = value.strip("'\"")
        values[key] = value
    return values


FILE_ENV = parse_env_file(Path(os.environ.get("AGENT_WORK_ENV", str(DEFAULT_WORK_DIR / "agent-work.env"))))


def cfg(name: str, default: str = "") -> str:
    return os.environ.get(name, FILE_ENV.get(name, default))


def split_list(value: str) -> list[str]:
    return [part for part in re.split(r"[\s,]+", value.strip()) if part]


WORK_DIR = cfg("WORK_DIR", str(DEFAULT_WORK_DIR))
REPO_DIR = cfg("REPO_DIR", str(Path(WORK_DIR).parent))
PROTECTED_BRANCHES = split_list(cfg("PROTECTED_BRANCHES", "main master"))
DEPLOY_COMMANDS = split_list(cfg("DEPLOY_CMD", "./deploy"))
PROTECTED_FILES = split_list(cfg("PROTECTED_FILES", ""))
ALLOWED_RM_ROOTS = split_list(cfg("ALLOWED_RM_ROOTS", f"{WORK_DIR} /tmp"))


def short_branch(branch: str) -> str:
    branch = branch.strip()
    if branch.startswith("refs/heads/"):
        branch = branch[len("refs/heads/"):]
    if branch.startswith("origin/"):
        branch = branch[len("origin/"):]
    return branch


PROTECTED_BRANCH_SET = {short_branch(b) for b in PROTECTED_BRANCHES}


def commands_from(event: dict[str, Any]) -> list[str]:
    tool_input = event.get("tool_input") or event.get("toolInput") or event.get("input") or {}
    out: list[str] = []
    if isinstance(tool_input, dict):
        for key in ("command", "cmd", "commands", "script"):
            value = tool_input.get(key)
            if isinstance(value, str):
                out.append(value)
            elif isinstance(value, list):
                out.extend(str(item) for item in value)
    elif isinstance(tool_input, str):
        out.append(tool_input)
    return out


def collect_file_paths(value: Any) -> Iterable[str]:
    """Collect path-like values from a tool_input object."""
    if isinstance(value, dict):
        for key, item in value.items():
            if key in {"file_path", "filepath", "notebook_path", "path", "file"} and isinstance(item, str):
                yield item
            else:
                yield from collect_file_paths(item)
    elif isinstance(value, list):
        for item in value:
            yield from collect_file_paths(item)


def resolve_path(path: str, base: str | None = None) -> str:
    expanded = os.path.expanduser(path)
    if not os.path.isabs(expanded):
        expanded = os.path.join(base or REPO_DIR, expanded)
    return os.path.realpath(expanded)


def protected_entries() -> list[tuple[str, bool]]:
    entries: list[tuple[str, bool]] = []
    for raw in PROTECTED_FILES:
        is_dir = raw.endswith("/")
        resolved = resolve_path(raw.rstrip("/") if is_dir else raw, REPO_DIR)
        if os.path.isdir(resolved):
            is_dir = True
        entries.append((resolved, is_dir))
    return entries


PROTECTED_ENTRIES = protected_entries()


def path_within(path: str, root: str) -> bool:
    try:
        return os.path.commonpath([path, root]) == root
    except (OSError, ValueError):
        return False


def is_protected_path(path: str, cwd: str | None = None) -> bool:
    resolved = resolve_path(path, cwd or REPO_DIR)
    for protected, is_dir in PROTECTED_ENTRIES:
        if is_dir:
            if path_within(resolved, protected):
                return True
        elif resolved == protected:
            return True
    return False


def current_branch(cwd: str | None) -> str:
    try:
        proc = subprocess.run(
            ["git", "-C", cwd or os.getcwd(), "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        if proc.returncode == 0:
            return proc.stdout.strip()
        # In a new repository with an unborn HEAD, rev-parse fails even though
        # the symbolic branch name is already meaningful for policy decisions.
        sym = subprocess.run(
            ["git", "-C", cwd or os.getcwd(), "symbolic-ref", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        return sym.stdout.strip() if sym.returncode == 0 else ""
    except Exception:
        return ""


def protected_branch_ref(ref: str) -> bool:
    return short_branch(ref) in PROTECTED_BRANCH_SET


def split_shell_segments(command: str) -> list[str]:
    # Conservative segmentation. It intentionally treats command substitution contents as shell text too.
    return [segment for segment in re.split(r"[;&|\n]+", command) if segment.strip()]


def shell_tokens(segment: str) -> list[str]:
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def executable_index(tokens: list[str]) -> int | None:
    i = 0
    while i < len(tokens) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[i]):
        i += 1
    if i < len(tokens) and os.path.basename(tokens[i]) in {"sudo", "command"}:
        i += 1
        while i < len(tokens) and tokens[i].startswith("-"):
            i += 1
    if i < len(tokens) and os.path.basename(tokens[i]) == "env":
        i += 1
        while i < len(tokens) and (tokens[i].startswith("-") or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[i])):
            i += 1
    return i if i < len(tokens) else None




def command_token(token: str) -> str:
    """Normalize a shell token enough to identify the executable being invoked.

    This deliberately catches simple command-subshell forms such as $(rm ...) and `(rm ...)`.
    It is not a complete shell parser; the hook remains a guardrail rather than a sandbox.
    """
    changed = True
    while changed and token:
        changed = False
        for prefix in ("$(", "`", "("):
            if token.startswith(prefix):
                token = token[len(prefix):]
                changed = True
        while token.endswith((")", "`")) and token:
            token = token[:-1]
            changed = True
    return token


def executable_name(tokens: list[str]) -> str:
    idx = executable_index(tokens)
    return command_token(os.path.basename(tokens[idx])) if idx is not None else ""


STATIC_RULES = [
    (r"\bgit\s+(?:-C\s+\S+\s+)?push(?:\s|$)", "git push is forbidden"),
    (r"\bhelm\s+(?:upgrade|install|uninstall|rollback)(?:\s|$)", "helm install/upgrade/uninstall/rollback is forbidden"),
    (r"\bkubectl\s+(?:apply|delete|create|replace|patch|edit|scale|cordon|uncordon|drain|taint)(?:\s|$)", "mutating kubectl commands are forbidden"),
    (r"\bkubectl\s+rollout\s+restart(?:\s|$)", "kubectl rollout restart is forbidden"),
    (r"\bterraform\s+(?:apply|destroy|import)(?:\s|$)", "terraform apply/destroy/import is forbidden"),
]


def deploy_token_matches(token: str) -> bool:
    for configured in DEPLOY_COMMANDS:
        base = os.path.basename(configured)
        if token == configured or os.path.basename(token) == base:
            return True
    return False


def check_deploy(command: str) -> str | None:
    for segment in split_shell_segments(command):
        tokens = shell_tokens(segment)
        idx = executable_index(tokens)
        if idx is not None and deploy_token_matches(command_token(tokens[idx])):
            return f"deploy command is forbidden ({tokens[idx]})"
    return None


def check_docker_prune(command: str) -> str | None:
    for segment in split_shell_segments(command):
        tokens = shell_tokens(segment)
        idx = executable_index(tokens)
        if idx is not None and command_token(os.path.basename(tokens[idx])) == "docker" and "prune" in tokens[idx + 1:]:
            return "docker prune is forbidden"
    return None


def protected_branch_in_args(args: str) -> bool:
    for token in shell_tokens(args):
        token = token.strip("'\"")
        if protected_branch_ref(token):
            return True
    return False


GIT_MUTATION_RE = re.compile(
    r"\bgit\s+(?:-C\s+(?P<dir>\S+)\s+)?(?P<sub>merge|rebase|cherry-pick|commit|reset)(?=\s|$)(?P<args>[^;&|\n]*)"
)


def check_git_branch_mutation(command: str, cwd: str | None) -> str | None:
    for match in GIT_MUTATION_RE.finditer(command):
        subcommand = match.group("sub")
        args = match.group("args") or ""
        if subcommand == "reset" and "--hard" not in shell_tokens(args):
            continue
        target_dir = match.group("dir") or cwd
        branch = short_branch(current_branch(target_dir))
        if branch in PROTECTED_BRANCH_SET:
            return f"git {subcommand} on protected branch {branch} is forbidden"
        if subcommand in {"merge", "rebase", "cherry-pick"} and protected_branch_in_args(args):
            return f"git {subcommand} involving a protected branch is forbidden"
    return None


def check_rm(command: str, cwd: str | None) -> str | None:
    allowed_roots = [resolve_path(root, "/") for root in ALLOWED_RM_ROOTS]
    for segment in split_shell_segments(command):
        tokens = shell_tokens(segment)
        idx = executable_index(tokens)
        if idx is None or command_token(os.path.basename(tokens[idx])) != "rm":
            continue
        args = tokens[idx + 1:]
        recursive = False
        operands: list[str] = []
        after_double_dash = False
        for token in args:
            if token == "--" and not after_double_dash:
                after_double_dash = True
                continue
            if not after_double_dash and token.startswith("--"):
                if token == "--recursive":
                    recursive = True
                continue
            if not after_double_dash and token.startswith("-") and token != "-":
                if "r" in token[1:].lower():
                    recursive = True
                continue
            operands.append(token)
        if not recursive:
            continue
        for operand in operands:
            if any(marker in operand for marker in ("$", "`", "*", "?", "[")):
                return f"recursive rm operand is dynamic and cannot be proven safe ({operand})"
            resolved = resolve_path(operand, cwd or os.getcwd())
            if not any(path_within(resolved, root) for root in allowed_roots):
                return f"recursive rm outside allowed roots is forbidden ({operand})"
    return None


def check_shell_protected_files(command: str, cwd: str | None) -> str | None:
    if not PROTECTED_ENTRIES:
        return None
    for segment in split_shell_segments(command):
        tokens = shell_tokens(segment)
        # Compact and spaced redirections: echo x>protected, echo x > protected.
        # This is conservative and may reject a redirection-looking string inside quotes.
        for match in re.finditer(r">>?\s*([^\s;&|]+)", segment):
            target = match.group(1).strip("'\"")
            if target not in {"&1", "&2"} and is_protected_path(target, cwd):
                return f"edit to protected file is forbidden ({target})"
        for i, token in enumerate(tokens[:-1]):
            if token in {">", ">>"} and is_protected_path(tokens[i + 1], cwd):
                return f"edit to protected file is forbidden ({tokens[i + 1]})"
        idx = executable_index(tokens)
        if idx is None:
            continue
        exe = command_token(os.path.basename(tokens[idx]))
        args = tokens[idx + 1:]
        if exe == "tee" and any(is_protected_path(arg, cwd) for arg in args if not arg.startswith("-")):
            return "tee to a protected file is forbidden"
        if exe in {"sed", "perl"} and any(arg.startswith("-i") or arg == "-pi" for arg in args):
            if any(is_protected_path(arg, cwd) for arg in args if not arg.startswith("-")):
                return f"in-place edit of a protected file is forbidden ({exe})"
        if exe in {"chmod", "chown", "chgrp", "touch"}:
            if any(is_protected_path(arg, cwd) for arg in args if not arg.startswith("-")):
                return f"metadata/content mutation of a protected file is forbidden ({exe})"
        # cp/mv/install are directional. Treat a protected final operand as the destination.
        if exe in {"cp", "mv", "install"} and len(args) >= 2:
            destination = args[-1]
            if is_protected_path(destination, cwd):
                return f"write to protected file is forbidden ({destination})"
    return None


def check_command(command: str, cwd: str | None) -> str | None:
    flat = " ".join(command.split())
    for pattern, reason in STATIC_RULES:
        if re.search(pattern, flat):
            return reason
    for checker in (
        check_deploy,
        check_docker_prune,
        lambda cmd: check_git_branch_mutation(cmd, cwd),
        lambda cmd: check_rm(cmd, cwd),
        lambda cmd: check_shell_protected_files(cmd, cwd),
    ):
        reason = checker(command)
        if reason:
            return reason
    return None


def main() -> int:
    raw = sys.stdin.read()
    try:
        event = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        event = {"tool_input": raw}
    if not isinstance(event, dict):
        event = {}
    cwd = event.get("cwd") or os.getcwd()
    tool_input = event.get("tool_input") or event.get("toolInput") or event.get("input") or {}

    reasons: list[str] = []
    for command in commands_from(event):
        reason = check_command(command, cwd)
        if reason:
            reasons.append(reason)

    # File-editing tools do not use shell commands, so inspect their paths directly.
    # Do not block read-only tools merely because their input contains a protected path.
    tool_name = str(event.get("tool_name") or event.get("toolName") or "").lower()
    mutation_tool = any(marker in tool_name for marker in ("edit", "write", "create", "replace", "delete", "fs_write"))
    if mutation_tool:
        for path in collect_file_paths(tool_input):
            if is_protected_path(path, cwd):
                reasons.append(f"edit to protected file is forbidden ({path})")

    if reasons:
        print(f"BLOCKED by agent-work guard: {reasons[0]}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
