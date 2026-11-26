# ec2-bootstrap

새 EC2 개발 서버를 한 번에 세팅하는 스크립트예요. 기본 개발 도구와 셸 설정에 더해, 에이전트 작업 환경(agent-work-kit: Devin CLI · Kiro CLI · Claude Code)까지 준비해요.

## 사용 순서

```bash
git clone git@github.com:NDS-Han/ec2-bootstrap.git
cd ec2-bootstrap
./bootstrap.sh
```

끝나면 새 셸을 열어요(`exec zsh -l`). docker 그룹, 기본 셸, conda, PATH 변경은 새 세션부터 적용돼요.

## 설치되는 것

| 구분 | 내용 |
|---|---|
| 기본 패키지 | git, curl, wget, jq, unzip, htop, tree, tmux, vim, zsh, make, gcc, fastfetch |
| 개발 도구 | Docker(BuildKit), AWS CLI, Node.js, Miniconda(Python) |
| 셸 | zsh, Oh My Zsh, Powerlevel10k, 자동완성·하이라이트 플러그인, dotfiles |
| 에이전트 도구 | Kiro CLI, Devin CLI, Claude Code (`~/.local/bin`, PATH 자동 추가) |
| agent-work-kit | `~/agent-work-kit`에 복사 (작업 레포에는 별도로 설치) |

## 설정 (bootstrap.sh 맨 위)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `INSTALL_DEVIN_CLI` | `true` | Devin CLI 설치 |
| `INSTALL_CLAUDE_CODE` | `true` | Claude Code 설치 |
| `INSTALL_AGENT_KIT` | `true` | agent-work-kit를 `AGENT_KIT_DEST`에 복사 |
| `AGENT_KIT_DEST` | `~/agent-work-kit` | 키트 복사 위치 |
| `AGENT_KIT_REPO_URL` | (비어 있음) | 넣으면 그 레포를 클론하고 키트까지 설치해요 |
| `AGENT_KIT_REPO_DIR` | `~/github/<레포 이름>` | 위 레포의 클론 위치 |

로그인 정보, API 키, 토큰은 스크립트가 저장하지 않아요. 로그인은 설치 후 직접 해요.

## 설치 후 할 일

```bash
devin            # Devin CLI 로그인 (브라우저 안내)
kiro-cli login   # Kiro CLI 로그인
claude           # Claude Code 로그인 후 /exit
```

작업 레포에 키트를 설치해요(`AGENT_KIT_REPO_URL`을 썼다면 이미 돼 있어요).

```bash
~/agent-work-kit/install.sh <작업 레포 경로>
# 이후 <레포>/.agent-work/agent-work.env 에서 BASE_BRANCH, DEPLOY_CMD, SERVICES, PROTECTED_FILES 등을 채워요
```

Claude Code는 반드시 tmux 안에서 실행해요. IDE 터미널에서 직접 띄우면 IDE를 재시작할 때 같이 꺼져요.

```bash
tmux new -s claude-main
cd <작업 레포> && claude --remote-control "<이름>"
# 빠져나오기: Ctrl-b d / 다시 붙기: tmux attach -t claude-main
```

키트 사용법(역할 분담, 작업 파일 규약, 토큰 전략, 주의할 점)은 `agent-work-kit/README.ko.md`를 봐요.

## 구동 테스트 (스모크 테스트)

앱 코드와 상관없는 빈 테스트 레포로 확인해요.

### 1. 설치 확인

```bash
exec zsh -l
which tmux devin claude kiro-cli   # 4개 모두 경로가 나와야 해요
ls ~/agent-work-kit                # install.sh, bin/, hooks/ 등
```

### 2. 테스트 레포에 키트 설치

```bash
mkdir -p ~/github/kit-smoke && cd ~/github/kit-smoke
git init -b main && echo "# smoke" > README.md && git add . && git commit -m init
~/agent-work-kit/install.sh ~/github/kit-smoke
git status   # .agent-work/ 가 보이지 않아야 정상(git 제외 처리)
```

원격 저장소가 없는 레포라서 `.agent-work/agent-work.env`의 `BASE_BRANCH`를 `main`으로 바꿔요(기본값은 `origin/main`).

### 3. 안전장치(guard hook) 테스트

```bash
python3 .agent-work/hooks/test_guard_hook.py -v   # 전부 OK
```

### 4. Devin CLI 작업 실행

```bash
mkdir -p .agent-work/smoke
cat > .agent-work/smoke/SPEC.md <<'SPEC'
Add hello.sh that prints "hello agent-work" and is executable. Commit it on your task branch.
Write .agent-work/smoke/REPORT.md (Korean summary on top) and SUMMARY.md, then create the DONE file.
SPEC
.agent-work/bin/devin-run smoke .agent-work/smoke/SPEC.md
.agent-work/bin/watch smoke   # 진행 확인, Ctrl-C로 빠져나옴
```

성공 기준:
- `.agent-work/wt/smoke`에 작업 전용 worktree와 브랜치가 생겨요.
- `.agent-work/smoke/`에 DONE 파일과 SUMMARY.md가 생겨요.
- `tmux ls`에 `devin-smoke` 세션이 보였다가, 끝나고 10분 뒤 자동으로 닫혀요.

### 5. Claude 원격 연결

```bash
tmux new -s claude-main
cd ~/github/kit-smoke && claude --remote-control "kit-smoke"
```

claude.ai에 새 세션이 보이면 브라우저(Claude in Chrome 확장)로 열어 지시를 주고받을 수 있는지 확인해요.

### 6. Kiro (선택)

Kiro 사용량이 여유 있을 때만 확인해요. 기본 effort는 high예요.

```bash
.agent-work/bin/kiro-run smoke-kiro high
```

## 문제 해결

| 증상 | 확인할 것 |
|---|---|
| `devin`/`claude` 명령을 못 찾음 | 새 셸을 열거나 `exec zsh -l`. `~/.local/bin`이 PATH에 있는지 확인 |
| 설치 후 conda가 안 잡힘 | `~/miniconda3/bin/conda init zsh && exec zsh` |
| IDE 원격 세션 재시작 필요 | `pkill -f 'vscode-server|cursor-server|devin-server'` |
| worktree 생성 실패 | `agent-work.env`의 `BASE_BRANCH`가 실제 브랜치(원격이 없으면 `main`)인지 확인 |
| Devin이 medium 모델로 돎 | `agent-work.env`의 `DEVIN_MODEL`이 `swe-2-1-max`인지 확인 |
