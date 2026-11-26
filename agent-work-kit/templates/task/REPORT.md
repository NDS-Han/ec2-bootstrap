Model: <model> · Effort: <effort> · Agent: <agent>

## 요약 (한국어)

- 브랜치/커밋: `<branch>` @ `<commit>` (base `<base>`), push/merge/deploy 없음.
- 핵심 변경: <무엇이 바뀌었는지 1~2문장>.
- 핵심 수치: <before → after, 테스트/측정 결과>.
- 설정/배포: <새 env 또는 설정 키>, `--build` 대상 <services>.
- 남은 사항: <review findings, risks, follow-ups 또는 "없음">.

## Detail

### What changed

- <change 1 — why>
- <change 2 — why>

### Evidence / measurements

| Case | Before | After | Notes |
|---|---:|---:|---|
| <measurement> | <value> | <value> | <method> |

### Tests

| Suite | Command | Result | Known pre-existing failures |
|---|---|---|---|
| <suite> | `<command>` | <passed/failed/skipped> | <none/list> |

### Commits and files

- Commit(s): `<hash>` — <summary>
- Changed files: <count>; important paths: `<paths>`

### Configuration

- `<service>: KEY=value (default, why)`

### Assumptions / decisions

- <assumption or user-visible decision>

### Infrastructure notes (not implemented)

- <future sizing/prod note, if any>

### Open findings / follow-ups

- <none or numbered list>
