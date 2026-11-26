# Steering — <PROJECT> agent-work implementation

Before acting, read `${WORK_DIR}/AGENTS.md` and the task `SPEC.md`; those files are authoritative.

Core behavior:

- Work only in the pre-created task worktree `${WORK_DIR}/wt/<task>`; never create another worktree or use the main checkout.
- Never push, merge/rebase onto protected branches, deploy, mutate cluster/cloud resources, prune containers, or edit protected files.
- Keep the hot path and security/cost semantics unchanged unless the SPEC explicitly says otherwise.
- Make DB migrations lock-safe and explain ordering, rollback, and renumbering interactions in HANDOFF.md.
- Use effort HIGH. Effort MAX requires explicit user approval for the specific task.
- Write `${WORK_DIR}/<task>/REPORT.md` with line 1 `Model: claude-opus-5.5 · Effort: high · Agent: ${KIRO_AGENT}`,
  then a Korean summary, then detailed evidence. Write HANDOFF.md, DONE or BLOCKED, and a 5-line Korean SUMMARY.md when done.
- HANDOFF.md must list every config key as `service: KEY=value (default, why)`, every service needing `--build`,
  migration order/lock behavior, verification steps, and rollback.
