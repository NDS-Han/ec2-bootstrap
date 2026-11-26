# AGENTS.md — standing rules for coding agents on <PROJECT>

> **How to watch a run:** `tmux attach -r -t devin-<task>` (or `kiro-<task>`; read-only, detach with Ctrl-b d) ·
> `${WORK_DIR}/bin/watch <task>` shows STATUS plus live logs.

Applies to every agent run dispatched from this box (Devin CLI, optional Kiro CLI, Claude Code dispatcher, Devin IDE).
Repo: `${REPO_DIR}`. Workspace for agent outputs: `${WORK_DIR}` (git-excluded — never commit it).
Base integration branch unless a SPEC says otherwise: `${BASE_BRANCH}`.

## Roles

1. **Dispatcher — Claude Code.** Creates task folders and SPECs, starts/stops queues, monitors `STATUS`/`SUMMARY.md`,
   keeps user-facing replies short, and performs only the narrowly scoped Claude reviews described below.
   Run the dispatcher in tmux so it survives IDE restarts.
2. **Implementer — Devin CLI.** Default implementation runner. Use model `${DEVIN_MODEL}` explicitly; do not rely on a
   machine-wide default. Devin CLI works only in the pre-created wave worktree and writes the required task outputs.
3. **Optional implementer/reviewer — Kiro CLI.** Use the configured agent `${KIRO_AGENT}` at effort `${KIRO_EFFORT}`
   (normally HIGH). Effort MAX requires explicit user approval for that specific task.
4. **Devin IDE.** Performs pre-merge review, merge, and dev deployment **only when the user explicitly asks**.
   It writes `REVIEW_RESULT.md` and, after deployment, `DEPLOYED.md`.

## File contract per task

A task lives in `${WORK_DIR}/<task>/` and normally contains:

- `SPEC.md` — dispatcher-written requirements. It must contain a line of the form
  `**Branch:** \`<branch>\` from **\`<base>\`**` so the runner can create the worktree.
- `REPORT.md` — implementer-written. First line exactly `Model: <model> · Effort: <effort> · Agent: <agent>`;
  then a short Korean summary; then detailed evidence in English or the project language.
- `HANDOFF.md` — implementer-written deployment handoff: branch/base, dependencies, every config/env change as
  `service: KEY=value (default, why)`, services needing `--build`, migrations, verification, rollback.
- `DONE` — empty success sentinel, or `BLOCKED` — reason and exactly what is needed.
- `SUMMARY.md` — exactly 5 Korean lines written when DONE: commit, key numbers, config keys, services to `--build`,
  open findings/review verdict. Status checks read this file rather than full reports.
- `XREVIEW.md` — optional independent CLI review result or a pending marker.
- `REVIEW_BY_CLAUDE.md` — Claude dispatcher review for security/cost/hot-path tasks only; diff-only, targeted tests,
  about 30 lines or fewer.
- `REVIEW_RESULT.md` — Devin IDE pre-merge verdict.
- `DEPLOYED.md` — merge commit, image tag per service, deployment revision, doctor/health result, and verification.

## Hard rules (the guard hook enforces most destructive parts)

1. **Never** `git push`. **Never** merge, rebase, cherry-pick, reset-hard, or commit onto protected branches:
   `${PROTECTED_BRANCHES}`.
2. **Never** run the deploy command (`${DEPLOY_CMD}`), `helm upgrade|install|uninstall|rollback`,
   mutating `kubectl` commands, `terraform apply|destroy|import`, or any `docker … prune`.
3. **Never** recursively delete outside `${WORK_DIR}` and `/tmp`.
4. One **local** branch per task from the base named in the SPEC, upstream unset. The dispatcher pre-creates
   `${WORK_DIR}/wt/<task>`; agents work only there and never check out branches in the main checkout.
5. **No new infrastructure** unless the SPEC explicitly authorizes it. Record infrastructure ideas in `REPORT.md`
   as later sizing/prod notes instead.
6. DB migrations must be lock-safe: short `lock_timeout` (≤5 s) with retry, no rewrite of large/hot tables,
   concurrent indexes where the database requires them, downgrade/forward-fix notes, and init/schema files kept in sync.
7. Never edit protected or secret-bearing files: `${PROTECTED_FILES}`. If values are needed, list them in HANDOFF.
8. Do not change billing/cost/security semantics unless the SPEC says so. Preserve fail-closed behavior unless the
   SPEC explicitly approves a degraded mode.
9. Diagnostics against shared/dev systems are read-only.
10. No secrets in commits, logs, prompts, reports, or committed config.

## Tests (fill in project-specific commands after installation)

Run the relevant package tests before every commit and report pass/fail/skip counts. Record known pre-existing
failures separately instead of silently accepting them. Typical entries to customize here:

- backend: `<backend test command>`
- frontend: `npx tsc --noEmit`, `<frontend test command>`, `npm run lint`
- database/migrations: `<migration test command>`
- chart/deployment rendering: `<lint/template command>`
- load/fault harness: `${WORK_DIR}/harness/README.md`

## Commit style

Use the repository's existing convention. Configured placeholder: `${COMMIT_STYLE}`.
One logical commit per task unless the SPEC says otherwise. No secrets in commits.

## Config and deployment handoff rule

HANDOFF.md must list **every** config/env change as `service: KEY=value (default, why)`. It must also list every
service whose image needs rebuilding (`--build`) because code changed. Agents never edit protected deployment or
`.local` values files themselves; the deployer applies approved values. If both a deploy config and a `.local` values
file exist, remember that `.local` normally takes precedence and say which layer should carry each key.

## Migration numbering between parallel tasks

Check migration versions on the base branch and all open task branches before choosing a number; respect reserved
ranges in design docs. If two branches still collide, **whoever merges second renumbers** (file + revision id) and
re-chains `down_revision` onto the merged head so the migration tool reports a single head. Note this in HANDOFF.md.

## Token budget rules (dispatcher + agents)

1. All implementation runs on Devin CLI `${DEVIN_MODEL}` by default (`bin/devin-run` / `work-queue`).
2. Claude Code review covers only security, cost, and hot-path tasks (hot paths: `${HOT_PATH_DIRS}`). It is diff-only
   with targeted tests, and `REVIEW_BY_CLAUDE.md` stays at about 30 lines or fewer. Every other task relies on the
   Devin IDE pre-merge review.
3. The dispatcher reads `STATUS`/`DONE`/`SUMMARY.md`, not full reports, and keeps replies short.
4. When a task is DONE, write `${WORK_DIR}/<task>/SUMMARY.md`: exactly 5 Korean lines covering the commit, key numbers,
   config keys, services to `--build`, and open findings or review verdict.
5. Kiro uses the configured Opus agent at effort HIGH. Do not use effort MAX unless the user explicitly approves it
   for a specific task; runners should refuse unapproved MAX attempts.
