# GitHub 기반 개발환경 자동화

Windows와 macOS 개발환경을 같은 저장소에서 관리한다.

## 목적

이 저장소는 신규 장비 또는 재설치 장비의 기본 개발 도구 설치를 자동화한다.

- Windows: `winget` 기반 설치
- macOS: `Homebrew` 기반 설치
- 공통 원칙: 실행 스크립트와 설치 목록을 분리
- 실행 단위: GitHub 저장소 복제 후 루트 설치 스크립트 실행

## 빠른 실행

신규 장비에서는 아래 명령만 실행한다.

### Windows

Windows 11 PowerShell에서 실행한다.

```powershell
irm https://raw.githubusercontent.com/codestreamkr/dev-init/main/boot.ps1 | iex
```

### macOS

터미널에서 실행한다.

```bash
curl -fsSL https://raw.githubusercontent.com/codestreamkr/dev-init/main/boot.sh | bash
```

## 구조

```text
.
├── config
│   ├── brew
│   │   └── Brewfile
│   └── winget
│       └── packages.txt
├── scripts
│   ├── macos
│   │   └── bootstrap.sh
│   └── windows
│       └── bootstrap.ps1
├── boot.ps1
├── boot.sh
├── install.ps1
├── install.sh
└── README.md
```

## macOS 실행

macOS는 `Homebrew`와 `brew bundle`을 사용한다.

실행 시 Homebrew 설치 여부를 먼저 확인한다.

- 확인 순서: PATH의 `brew`, `/opt/homebrew/bin/brew`, `/usr/local/bin/brew`
- 미설치 상태: Homebrew 공식 설치 스크립트 실행
- 설치 후 처리: 현재 셸에서 `brew shellenv` 적용

```bash
bash install.sh
```

### macOS 옵션

- `--dry-run`: 설치 명령을 실행하지 않고 대상만 출력
- `--no-upgrade`: 설치 전 `brew upgrade` 생략
- `--skip-ai-init`: Codex와 Claude Code 기본 설정 실행 생략

예시:

```bash
bash install.sh --dry-run
bash install.sh --no-upgrade
bash install.sh --skip-ai-init
```

## Windows 실행

Windows는 PowerShell에서 `winget`을 사용한다.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

### Windows 옵션

- `-DryRun`: 설치 명령을 실행하지 않고 대상만 출력
- `-NoUpgrade`: 설치 전 `winget upgrade --all` 생략
- `-SkipAiInit`: Codex와 Claude Code 기본 설정 실행 생략

예시:

```powershell
.\install.ps1 -DryRun
.\install.ps1 -NoUpgrade
.\install.ps1 -SkipAiInit
```

## 설치 목록 수정

설치 목록은 OS별 설정 파일에서 관리한다.

- macOS: `config/brew/Brewfile`
- Windows: `config/winget/packages.txt`

## 필수 프로그램

필수 프로그램은 기본 실행 시 설치한다.

| 구분 | macOS | Windows |
| --- | --- | --- |
| Git | `git` | `Git.Git` |
| GitHub CLI | `gh` | `GitHub.cli` |
| Node.js | `node` | `OpenJS.NodeJS.LTS` |
| Java 8 | `openjdk@8` | `EclipseAdoptium.Temurin.8.JDK` |
| Java 21 | `openjdk@21` | `Microsoft.OpenJDK.21` |
| Python | `python@3.14` | `Python.Python.3.14` |
| IntelliJ IDEA Ultimate | `intellij-idea` | `JetBrains.IntelliJIDEA.Ultimate` |
| DataGrip | `datagrip` | `JetBrains.DataGrip` |
| Docker Desktop | `docker` | `Docker.DockerDesktop` |
| 클립보드 관리 | `maccy` | `Ditto.Ditto` |
| Visual Studio Code | `visual-studio-code` | `Microsoft.VisualStudioCode` |
| Chrome | `google-chrome` | `Google.Chrome` |
| 터미널 | - | `Microsoft.PowerShell` |
| Claude Code CLI | `curl -kfsSL https://claude.ai/install.sh \| bash` | `irm https://claude.ai/install.ps1 \| iex` |
| Codex CLI | `codex` | `OpenAI.Codex` |

## 추천 프로그램

추천 프로그램은 기본 설치에서 제외한다.

- `jq`: JSON 응답 가공과 스크립트 처리에 필요
- `mise`: Node, Python, Java 등 런타임 버전 고정에 유용
- `ripgrep`: 코드 검색 속도 개선
- `wget`: 설치 스크립트와 외부 파일 다운로드 보조
- `PowerToys`: Windows 개발 장비 생산성 보조
- `iTerm2`: macOS 터미널 사용성 개선
- `OrbStack`: macOS에서 Docker Desktop 대안으로 사용 가능

추천 항목을 설치하려면 설정 파일에서 해당 줄의 주석을 해제한다.

## AI 기본 설정

Codex와 Claude Code 기본 설정은 패키지 설치 후 실행한다.

- Codex 설정 저장소: `https://github.com/codestreamkr/chatgpt-codex-init.git`
- Claude Code 설정 저장소: `https://github.com/codestreamkr/claude-code-init.git`
- Windows 실행 위치: `$env:TEMP\codex-init`, `$env:TEMP\claude-init`
- macOS 실행 위치: `/tmp/codex-init`, `/tmp/claude-init`

실행 명령은 OS별 스크립트에 포함되어 있다.

```powershell
git clone https://github.com/codestreamkr/chatgpt-codex-init.git $env:TEMP\codex-init; & $env:TEMP\codex-init\install.ps1
git clone https://github.com/codestreamkr/claude-code-init.git $env:TEMP\claude-init; & $env:TEMP\claude-init\install.ps1
```

```bash
git clone https://github.com/codestreamkr/chatgpt-codex-init.git /tmp/codex-init && bash /tmp/codex-init/install.sh
git clone https://github.com/codestreamkr/claude-code-init.git /tmp/claude-init && bash /tmp/claude-init/install.sh
```

## Claude 인증서 오류 대응

Claude Code CLI는 인증서 우회 범위를 설치 명령 1회로 제한한다.

- Windows: 기존 인증서 검증 콜백 저장, 설치 실행, `finally`에서 원복
- macOS: `curl -kfsSL https://claude.ai/install.sh | bash` 실행
- 범위: Claude Code CLI 설치 명령에만 적용

## 운영 기준

이 저장소는 기본 개발환경 설치까지만 담당한다.

- 포함: 패키지 매니저 확인, Git 기반 저장소 복제, 기본 도구 설치, 설치 목록 관리
- 제외: 개인 계정 로그인, SSH 키 생성, 회사 내부 인증, 프로젝트별 환경 변수

## 이력관리

- 2026-05-19: 개발환경 자동화 최초 등록
