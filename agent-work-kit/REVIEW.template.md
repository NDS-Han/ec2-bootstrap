# REVIEW.md — pre-merge checklist for every task branch

Run a review as read-only except for the review output file. Never merge, push, or deploy from a review run.
Suggested Devin CLI prompt:

```sh
${WORK_DIR}/bin/devin-run <task>-review -- "Review branch <branch> per ${WORK_DIR}/REVIEW.md and write ${WORK_DIR}/<task>/REVIEW_RESULT.md"
```

Checklist:

1. **Scope vs SPEC** — inspect `git diff <base>...<branch>`: every acceptance criterion in
   `${WORK_DIR}/<task>/SPEC.md` is met (list each ✅/❌ with file:line); nothing out of scope; protected files untouched.
2. **Tests pass locally** — run the project-specific commands from `AGENTS.md` in the branch worktree; record
   pass/fail/skip counts and compare with known pre-existing failures.
3. **Migrations** — ordered after the current head, single-head chain, lock-safe (`lock_timeout` ≤5 s + retry, no hot-table
   rewrite, concurrent indexes where required), downgrade or forward-fix documented, init/schema files synchronized.
4. **Config** — every new env var has a safe code default; deployment config changes are complete for dev; prod values are
   unchanged unless the SPEC says otherwise. Compare HANDOFF.md with the diff.
5. **Services to redeploy** — derive from the diff and compare with HANDOFF.md (`--build` list, migration job, shared images).
6. **Conflicts** — compare with the base and other open task branches. If the guard prevents even read-only merge
   simulation in your installation, use a disposable clone/worktree outside the guarded agent or report that limitation.
7. **Security/cost/hot path** — no secret leakage; authz/authn behavior preserved; cost semantics unchanged unless specified;
   hot-path allocations, network round trips, and failure behavior are justified by measurements.
8. **Rollback** — HANDOFF.md rollback steps are real (image rollback; migration downgrade safe or forward-fix documented).
9. **Verdict** — write `${WORK_DIR}/<task>/REVIEW_RESULT.md`, first line
   `Model: … · Effort: … · Agent: …`, verdict `APPROVE` or `CHANGES REQUESTED`, numbered findings with file:line.

After the user deploys from the IDE, write `${WORK_DIR}/<task>/DEPLOYED.md`: merge commit, image tag per service,
deployment revision, doctor/health result, verification evidence, and rollback-relevant notes.
