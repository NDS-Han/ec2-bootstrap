Model: <model> · Effort: <effort> · Agent: claude-code (dispatcher review, diff-only)

# REVIEW_BY_CLAUDE — <task> (`<branch>` @ `<commit>` vs `<base>`)

**Verdict: <APPROVE | CHANGES REQUESTED>** — <one-line reason>.

## 요약 (한국어)

- <보안/비용/핫패스 관점 핵심 1~2줄>
- <테스트/증빙 핵심 1줄>

## Must-check list

| Item | Result |
|---|---|
| Scope vs SPEC | <✅/❌ + file:line> |
| Security/authz/secrets | <result> |
| Cost/billing semantics | <result> |
| Hot-path performance/failure mode | <result> |
| Config defaults and protected files | <result> |
| Targeted tests | <counts> |

## Findings

1. **[Must fix|Should|Note]** <finding with file:line and concrete fix>.

## Rebuild/deploy scope

<services to `--build`, migrations, config keys>. Keep this review at about 30 lines or fewer.
