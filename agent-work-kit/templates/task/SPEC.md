# <task> — <short title>

**Assignee:** <Devin CLI | Kiro | other> — `<runner command and effort>`.
**Branch:** `<branch>` from **`<base>`** (worktree `${WORK_DIR}/wt/<task>`, pre-created by the dispatcher).

Read `${WORK_DIR}/AGENTS.md` first and follow it exactly. Hard rules unchanged: no push, no merge/rebase onto protected
branches, no deploy or infrastructure mutation, no recursive delete outside the workspace/`/tmp`, no protected-file edits,
and no secrets in outputs. Work only in the pre-created worktree; do not create another worktree and do not touch the
main checkout. Write outputs to `${WORK_DIR}/<task>/`: `REPORT.md` (line 1 model/effort/agent, Korean summary first),
`HANDOFF.md` (`service: KEY=value (default, why)`, services to `--build`, migrations, verification, rollback),
`DONE` or `BLOCKED`, and `SUMMARY.md` when done.

## User instruction (verbatim)

> <Paste the user's instruction here without rewriting it.>

## Inputs and pointers

- <design docs, prior reports, source files, related task folders>
- <known constraints, reserved migration numbers, parallel tasks>

## Acceptance criteria

- [ ] <criterion 1, measurable where possible>
- [ ] <criterion 2, measurable where possible>
- [ ] Required tests pass; report pass/fail/skip counts and known pre-existing failures.
- [ ] REPORT/HANDOFF/SUMMARY/DONE or BLOCKED are complete.

## Out of scope

- <explicit non-goals>
