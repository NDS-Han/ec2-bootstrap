# agent-work-kit 사용 안내 (한국어)

`agent-work-kit`는 여러 코딩 에이전트를 **파일 계약 + git worktree + tmux + guard hook**으로 운영하기 위한,
프로젝트 비종속 작업 킷입니다. 애플리케이션 코드는 포함하지 않으며, 설치 후 모든 실행 산출물은 기본적으로
`<repo>/.agent-work/` 아래에 둡니다.

## 1. 구성 요소와 역할

| 역할 | 도구 | 하는 일 | 토큰 원칙 |
|---|---|---|---|
| 디스패처 | Claude Code | SPEC 작성, 큐 시작/중지, STATUS/SUMMARY 확인, 사용자 보고 | 짧게 읽고 짧게 답함 |
| 구현자 기본값 | Devin CLI | 실제 코드 구현, 테스트, REPORT/HANDOFF/SUMMARY 작성 | 항상 명시적으로 `swe-2-1-max` |
| 선택 구현/리뷰 | Kiro CLI | 보조 구현 또는 독립 리뷰 | Opus 계열, effort HIGH |
| 머지 전 리뷰/배포 | Devin IDE | 사용자가 명시적으로 요청한 경우에만 리뷰·머지·dev 배포 | 승인 없는 배포 금지 |

Claude의 별도 리뷰는 **보안/비용/핫패스** 작업만 대상으로 합니다. diff만 보고 targeted tests를 실행하며,
`REVIEW_BY_CLAUDE.md`는 약 30줄 이하로 유지합니다. 그 외 작업은 Devin IDE의 pre-merge review를 사용합니다.

## 2. 설치 순서

1. 호스트에 git, tmux, python3, Devin CLI, Kiro CLI, Claude Code를 설치합니다.
   `bootstrap-snippet.sh`는 EC2 user-data에 붙일 수 있는 예시이며, 로그인은 절대 자동화하지 않습니다.
2. 각 도구의 로그인은 사람이 수동으로 완료합니다.
3. 킷을 원하는 위치에 풀고 저장소에 설치합니다.

   ```sh
   ./agent-work-kit/install.sh /path/to/repo
   ```

   기본 설치 위치는 `/path/to/repo/.agent-work/`입니다. 다른 위치가 필요하면 `WORK_DIR`을 먼저 지정합니다.
   설치는 idempotent합니다. 두 번째 실행은 `install.sh: no changes`를 출력해야 합니다.
4. `<repo>/.agent-work/agent-work.env`를 편집합니다.
   - `REPO_DIR`, `WORK_DIR`, `BASE_BRANCH`, `PROTECTED_BRANCHES`
   - `DEPLOY_CMD`, `SERVICES`, `PROTECTED_FILES`, `HOT_PATH_DIRS`
   - `DEVIN_MODEL=swe-2-1-max`, `KIRO_AGENT`, `KIRO_EFFORT=high`, `MAX_CONCURRENT`
5. `<repo>/.agent-work/AGENTS.md`를 프로젝트에 맞게 편집합니다. 특히 테스트 명령, 보호 파일, 커밋 스타일,
   마이그레이션 규칙을 실제 값으로 채웁니다.
6. 설치 검증:

   ```sh
   python3 <repo>/.agent-work/hooks/test_guard_hook.py -v
   bash -n <repo>/.agent-work/bin/*
   ```

7. Claude 디스패처는 IDE 터미널이 아니라 tmux에서 실행합니다.

   ```sh
   tmux new-session -d -s dispatcher -c /path/to/repo 'claude --remote-control'
   tmux attach -r -t dispatcher   # read-only attach; detach는 Ctrl-b d
   ```

   `--remote-control`은 Claude Code 버전/계정 설정에 따라 달라질 수 있으므로, 실제 환경에서는 `claude --help`와
   조직 정책을 확인하십시오. 중요한 점은 **IDE 재시작과 분리된 tmux 세션**에서 디스패처를 유지하는 것입니다.

## 3. 작업 실행 흐름

1. `<repo>/.agent-work/<task>/SPEC.md`를 `templates/task/SPEC.md`로부터 작성합니다.
   반드시 다음 형태의 브랜치 줄이 필요합니다.

   ```md
   **Branch:** `<branch>` from **`<base>`**
   ```

2. 구현 시작:

   ```sh
   .agent-work/bin/devin-run <task> .agent-work/<task>/SPEC.md
   # 또는
   .agent-work/bin/kiro-run <task> high
   ```

3. 여러 작업:

   ```sh
   .agent-work/bin/work-queue task-a task-b task-c
   .agent-work/bin/after-done task-a task-b   # task-a DONE 후 task-b 시작
   .agent-work/bin/queue-extra task-c         # 동시 실행 수 제한을 지키며 추가
   ```

4. 상태 확인:

   ```sh
   .agent-work/bin/watch <task>
   cat .agent-work/<task>/SUMMARY.md
   tmux attach -r -t devin-<task>
   ```

5. runner는 tmux 세션 하나를 만들고, headless CLI가 첫 답변 후 멈춰도 `DONE`/`BLOCKED`가 생길 때까지 최대
   `MAX_ROUNDS`(기본 5)회 resume합니다. 작업 프로세스가 끝난 tmux 세션은 10분 후 자동으로 닫힙니다.
6. `DONE`이면 `AUTO_XREVIEW=1` 기본값에서 Kiro read-only review를 시도하고 `XREVIEW.md`를 씁니다.
   보안/비용/핫패스 작업은 `CLAUDE_REVIEW_TASKS`에 넣어 Claude 리뷰 대기 표시로 둡니다.

## 4. 토큰/비용 전략

- 구현은 기본적으로 Devin CLI `swe-2-1-max`입니다. 모델을 명시하지 않고 CLI 기본값에 의존하지 않습니다.
- Kiro는 effort HIGH가 기본입니다. MAX는 해당 작업에 대한 사용자의 명시 승인이 있을 때만 `KIRO_ALLOW_MAX=1`로 실행합니다.
- Claude 리뷰는 보안/비용/핫패스만, diff-only, targeted tests, 약 30줄 이하입니다.
- 디스패처는 전체 REPORT와 로그를 상시 읽지 않습니다. `STATUS`, `DONE`/`BLOCKED`, 5줄 `SUMMARY.md`만 읽고,
  상세 파일은 사용자가 요청하거나 실패 원인을 좁힐 때만 엽니다.
- `SUMMARY.md`는 정확히 5개의 한국어 줄로 유지합니다: 커밋, 핵심 수치, 설정 키, `--build` 대상, 열린 사항/리뷰 verdict.

## 5. 운영하면서 실제로 겪은 함정

1. **IDE 터미널의 Claude는 IDE 재시작에 죽습니다.** 디스패처는 반드시 tmux에서 실행하십시오.
2. **Kiro headless는 첫 응답 후 멈출 수 있습니다.** `_job`의 resume loop가 필요하며, 무한 재시도를 막기 위해
   최대 5회로 제한합니다.
3. **Devin CLI 기본 모델은 환경에 따라 medium 수준으로 잡힐 수 있습니다.** 비용은 들더라도 구현 품질이 필요한
   작업은 `DEVIN_MODEL=swe-2-1-max`와 `--model`을 명시하십시오.
4. **`.local` values 파일은 보통 render된 deploy config보다 우선합니다.** HANDOFF에는 각 키를 어느 계층에 넣을지
   적고, 에이전트가 protected values 파일을 직접 수정하지 못하게 합니다.
5. **시크릿/실값 파일은 hook과 git exclude로 이중 보호합니다.** `PROTECTED_FILES`에 넣고, git에는 올라가지 않게
   `.git/info/exclude` 또는 프로젝트의 기존 보호 방식을 사용합니다. hook은 방어선이지 완전한 보안 경계가 아닙니다.
6. **과거 운영에서는 guard hook이 `git merge-tree`까지 차단했습니다.** `merge-tree` 자체는 read-only지만,
   넓은 `git merge` 정규식에 걸렸던 사례입니다. 이 킷의 기본 hook은 `merge`와 `merge-tree`를 구분합니다.
   그래도 조직 정책상 더 보수적인 hook을 사용한다면 diff/stat/check 또는 별도 read-only clone에서 충돌을 확인하고,
   hook을 우회하기 위해 보호 규칙을 약하게 만들지 마십시오.
7. **tmux 환경 변수와 중첩 quoting은 깨지기 쉽습니다.** 이 킷은 프롬프트를 tmux 환경 변수로 전달해 중첩 quoting을
   줄입니다. 수동으로 runner를 고칠 때는 작은 프롬프트와 여러 줄/따옴표가 있는 프롬프트를 모두 시험하십시오.
8. **컨테이너 정리에 prune을 쓰지 마십시오.** 실험 컨테이너는 task id prefix를 붙이고 exact name/PID로 정리합니다.

## 6. 보안과 한계

- guard hook은 실수 방지 장치이며 완전한 sandbox가 아닙니다. shell 우회, 이미 로그인된 CLI 권한, 네트워크/API 권한은
  별도로 통제해야 합니다.
- `install.sh`와 `bootstrap-snippet.sh`는 로그인하지 않고 토큰도 저장하지 않습니다.
- `PROTECTED_FILES` 목록 값은 공백 없는 경로여야 합니다. 공백이 있는 경로가 꼭 필요하면 hook을 프로젝트에 맞게 확장하십시오.
- `REVIEW.template.md`는 checklist일 뿐이며, 실제 머지/배포 권한은 사용자와 조직 정책에 있습니다.

## 7. 업데이트

새 킷 버전으로 같은 `install.sh`를 다시 실행하면 runner/hook/template 파일은 갱신됩니다. 반대로
`agent-work.env`, `AGENTS.md`, `REVIEW.md`, Devin config, Kiro agent/steering처럼 프로젝트별로 수정하는 파일은
기본적으로 보존합니다. 차이가 있으면 `*.kit-update`가 생성되므로 사람이 diff를 보고 반영합니다.
`--force`는 이런 로컬 수정까지 덮어쓰므로 신중하게 사용하십시오.
