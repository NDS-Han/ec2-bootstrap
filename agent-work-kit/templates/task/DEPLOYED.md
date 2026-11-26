Model: <model> · Effort: <effort> · Agent: <agent>

# DEPLOYED — <task> / `<branch>`

## Decision

<DEPLOYED | NOT DEPLOYED | PARTIAL> — <one-line reason>.

## Merge and deployment

| Item | Value |
|---|---|
| Merge commit | `<hash>` (`<branch>` @ `<commit>` → `<base>`) |
| Deployment revision | `<helm revision or deployment id>` |
| Deployed at | `<timestamp + timezone>` |
| Rolled services | `<service:image-tag>` per service |
| Migration head | `<revision or none>` |
| Doctor/health | `<result, including pre-existing warnings>` |

## Review summary

- Pre-merge review: `<APPROVE/CHANGES REQUESTED>` — <key conditions>.
- Independent review: `<XREVIEW/REVIEW_BY_CLAUDE verdict or pending>`.

## Verification evidence

| Check | Result | Evidence |
|---|---|---|
| <route/job/metric/log/query> | <result> | <command/output reference> |
| Sent vs recorded / reconciliation | <result> | <evidence> |
| Rollback readiness | <result> | <evidence> |

## Config actually applied

- `<service>: KEY=value` — source <deploy config / `.local` / secret>; verified in pod/process env <yes/no>.

## Notes and follow-ups

- <operational note, deferred action, rollback caveat>

_Written by: <agent> · <date>_
