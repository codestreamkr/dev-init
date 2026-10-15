# GitHub 기반 개발환경 자동화

Windows와 macOS 개발환경을 같은 저장소에서 관리한다.

## 목적

이 저장소는 신규 장비 또는 재설치 장비의 기본 개발 도구 설치를 자동화한다.

- Windows: `winget` 기반 설치
- macOS: `Homebrew` 기반 설치
- 기본 동작: 없으면 설치하고, 있으면 설치 목록의 버전 정책 안에서 최신 버전으로 업데이트
- 공통 원칙: 실행 스크립트와 설치 목록을 분리
- 실행 단위: GitHub 저장소 복제 후 루트 설치 스크립트 실행

## 빠른 실행

신규 장비에서는 아래 명령만 실행한다.

### Windows

Windows 11의 기본 Windows PowerShell에서 실행한다.

```powershell
irm https://raw.githubusercontent.com/codestreamkr/dev-init/refs/heads/main/boot.ps1 | iex
```

### macOS

터미널에서 실행한다.

```bash
curl -fsSL https://raw.githubusercontent.com/codestreamkr/dev-init/refs/heads/main/boot.sh | bash
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

macOS는 `Homebrew`와 `brew bundle`을 사용한다. 기본적으로 `brew upgrade --greedy`로 자동 업데이트 앱을 포함한 기존 Homebrew 패키지를 갱신하고, 설치 목록에서 빠진 항목을 설치한다.

실행 시 Homebrew 설치 여부를 먼저 확인한다.

- 확인 순서: PATH의 `brew`, `/opt/homebrew/bin/brew`, `/usr/local/bin/brew`
- 미설치 상태: Homebrew 공식 설치 스크립트 실행
- 설치 후 처리: 현재 셸에서 `brew shellenv` 적용

```bash
bash install.sh
```

### macOS 옵션

- `--dry-run`: 설치 명령을 실행하지 않고 대상만 출력
- `--no-upgrade`: `brew upgrade`, `brew bundle`, Claude CLI의 기존 패키지 업그레이드 생략
- `--skip-ai-init`: Codex와 Claude Code 기본 설정 실행 생략

예시:

```bash
bash install.sh --dry-run
bash install.sh --no-upgrade
bash install.sh --skip-ai-init
```

## Windows 실행

Windows는 Windows PowerShell에서 `winget`을 사용한다.

PowerShell 7이 없어도 실행할 수 있다.

- 실행 대상: Windows 기본 내장 `Windows PowerShell`
- 실행 파일: `powershell.exe`
- 기준 버전: Windows PowerShell 5.1
- 호환 대상: PowerShell 7 이상
- 사전 조건: `winget` 사용 가능

PowerShell 7에서도 같은 명령을 사용할 수 있다.

- Windows PowerShell: `powershell.exe`
- PowerShell 7 이상: `pwsh.exe`
- 기준 원칙: Windows 기본 설치 환경인 Windows PowerShell 5.1에서 먼저 동작해야 함

파일로 받은 `install.ps1`은 실행 정책을 우회한 새 PowerShell 프로세스에서 실행한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

설치 대상은 패키지별로 확인한 뒤 처리한다.

- 확인: `winget list --id <패키지ID> --exact` 실행 후 출력에 같은 패키지 ID가 있는지 확인
- 설치됨: `winget upgrade --id <패키지ID> --exact --silent --include-unknown` 실행
- 이미 최신: 업데이트 없음 종료 코드를 정상 처리
- `-NoUpgrade`: 설치된 패키지는 유지하고 누락된 항목만 설치
- 미설치: `winget install --id <패키지ID> --exact --silent` 실행
- 실패: 다음 패키지 설치를 계속 진행하고 마지막에 실패 목록 출력
- 종료: 실패 패키지가 있으면 전체 실행을 실패로 종료

CLI와 AI 기본 설정도 설치 여부를 먼저 확인한다.

- Claude Code CLI: 없으면 설치, 있으면 `claude update` 실행 (`--no-upgrade` / `-NoUpgrade` 사용 시 업데이트 생략)
- AI 기본 설정: CLI 존재 여부와 별개로, 설정 스크립트가 성공한 기록이 있을 때만 건너뜀

### Windows 빠른 실행 오류 대응

`irm` 이후 clone은 성공했지만 `install.ps1` 실행에서 보안 오류가 나면 예전 `boot.ps1`이 실행된 상태다.

- 증상: `이 시스템에서 스크립트를 실행할 수 없으므로 ... install.ps1 파일을 로드할 수 없습니다.`
- 원인: clone된 `install.ps1`을 실행 정책 우회 없이 파일로 실행함
- 조치: 최신 `boot.ps1`은 `powershell.exe -ExecutionPolicy Bypass -File`로 `install.ps1`을 실행함

```powershell
irm https://raw.githubusercontent.com/codestreamkr/dev-init/refs/heads/main/boot.ps1 | iex
```

한 줄로 새 Windows PowerShell 프로세스에서 실행할 수도 있다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/codestreamkr/dev-init/refs/heads/main/boot.ps1 | iex"
```

현재 정책 확인은 아래 명령으로 한다.

```powershell
Get-ExecutionPolicy -List
```

`winget.exe` 경로가 인식할 수 없는 명령으로 출력되면 App Installer 업데이트 직후 상태일 수 있다.

- 증상: `인식할 수 없는 명령임: 'C:\Users\...\WindowsApps\winget.exe'`
- 원인: `Microsoft.AppInstaller` 업데이트 후 현재 PowerShell 세션의 `winget` 실행 별칭이 갱신 대기 상태가 됨
- 조치: Windows PowerShell 창을 닫고 새로 연 뒤 최신 `boot.ps1`을 다시 실행

```powershell
irm https://raw.githubusercontent.com/codestreamkr/dev-init/refs/heads/main/boot.ps1 | iex
```

### Windows 옵션

- `-DryRun`: 설치 명령을 실행하지 않고 대상만 출력
- `-NoUpgrade`: 설치된 패키지와 Claude CLI의 업데이트 생략. 누락된 패키지는 설치
- 기본 실행에서는 설치 목록의 패키지만 개별 업데이트하며 `winget upgrade --all`은 사용하지 않음
- `-SkipAiInit`: Codex와 Claude Code 기본 설정 실행 생략

예시:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoUpgrade
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SkipAiInit
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
| Node.js LTS | `node@24` | `OpenJS.NodeJS.LTS` |
| Java 21 | `openjdk@21` | `Microsoft.OpenJDK.21` |
| Python | `python@3.14` | `Python.Python.3.14` |
| IntelliJ IDEA Ultimate | `intellij-idea` | `JetBrains.IntelliJIDEA.Ultimate` |
| JetBrains Toolbox | `jetbrains-toolbox` | `JetBrains.Toolbox` |
| DataGrip | `datagrip` | `JetBrains.DataGrip` |
| Android Studio | `android-studio` | `Google.AndroidStudio` |
| Docker Desktop | `docker-desktop` | `Docker.DockerDesktop` |
| 클립보드 관리 | `maccy` | `Ditto.Ditto` |
| Visual Studio Code | `visual-studio-code` | `Microsoft.VisualStudioCode` |
| Chrome | `google-chrome` | `Google.Chrome` |
| Google Drive | `google-drive` | `Google.GoogleDrive` |
| 네이버 MYBOX | 네이버 공식 `.pkg` 설치 | `NAVER.MYBOX` |
| 카카오톡 | Mac App Store (`869223134`) | `Kakao.KakaoTalk` |
| Logi Options+ | `logi-options+` | `Logitech.OptionsPlus` |
| Discord | `discord` | `Discord.Discord` |
| Cloudflare WARP | `cloudflare-warp` | `Cloudflare.Warp` |
| 터미널 | - | `Microsoft.PowerShell` |
| Claude Code CLI | `curl -fsSL https://claude.ai/install.sh \| bash` | `irm https://claude.ai/install.ps1 \| iex` |
| Codex CLI | `codex` | `OpenAI.Codex` |
| Antigravity CLI (`agy`) | Google 공식 네이티브 설치기 | Google 공식 네이티브 설치기 |
| Grok CLI (`grok`) | xAI 공식 네이티브 설치기 | xAI 공식 네이티브 설치기 |
| Pi CLI (`pi`) | `@earendil-works/pi-coding-agent` | `@earendil-works/pi-coding-agent` |

macOS 카카오톡은 `mas`로 설치한다. 실행 전에 Mac App Store에 로그인한다.
Logi Options+는 설치 후 권한 설정과 재부팅이 필요할 수 있다.
계정 로그인과 동기화 폴더 선택은 각 앱에서 직접 진행한다.

macOS MYBOX는 [네이버 공식 다운로드 페이지](https://mybox.naver.com/about/explorer-guide/mac)의 설치 패키지를 사용한다.
macOS 14 이상이 필요하다. 네이버 설치 서명을 검증한 뒤 관리자 권한으로 설치한다.
기본 실행에서는 최신 패키지를 다시 설치한다. `--no-upgrade`는 기존 MYBOX 앱의 재설치를 생략한다.

Node는 macOS에서 `node@24` LTS, Windows에서 `OpenJS.NodeJS.LTS`를 사용한다. macOS는 keg-only 패키지의 실행 경로를 현재 프로세스와 `~/.zprofile`에 추가한다. Windows LTS 패키지가 다음 메이저로 전환되면 macOS 버전도 함께 갱신한다.

Java 8은 기본 설치에서 제외하며 Java 21을 유지한다. 기존에 설치된 Java 8이나 Node는 자동 삭제하지 않는다.

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

## AI CLI 설치와 기본 설정

`dev-init`은 CLI를 설치한다. `ai-comm-init`은 설치된 CLI의 지침과 스킬을 연결한다.

- `agy`: [Google 공식 설치기](https://antigravity.google/docs/cli/install/)로 설치한다. 기존 설치는 `agy update`로 갱신한다.
- `grok`: [xAI 공식 설치기](https://x.ai/build)로 설치한다. 기존 설치는 `grok update`로 갱신한다.
- `pi`: [Pi 공식 npm 패키지](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/quickstart.md)를 `--ignore-scripts` 옵션으로 설치한다.
- Pi 패키지: `@earendil-works/pi-coding-agent@latest`
- Pi 설치 경로: macOS `~/.local`, Windows `%APPDATA%\npm`
- 기본 실행: 미설치 CLI는 설치하고 기존 CLI는 갱신한다.
- `--no-upgrade` / `-NoUpgrade`: 기존 CLI 갱신을 생략한다. 미설치 CLI는 설치한다.
- `--dry-run` / `-DryRun`: 설치와 갱신 명령만 출력한다.
- 새 CLI를 설치하면 기존 완료 기록이 있어도 `ai-comm-init`을 다시 실행한다.
- `--skip-ai-init` / `-SkipAiInit`: CLI는 설치하고 지침과 스킬 연결은 생략한다.
- 계정 로그인과 API 키 설정은 각 CLI에서 직접 진행한다.

- 공통 설정 저장소: `https://github.com/codestreamkr/ai-comm-init.git`
- 실행 시점: 최초 설정 또는 새 CLI 설치 후 공통 스킬과 런타임 링크 구성
- 실행 기준: 설정 저장소의 설치 스크립트가 성공한 경우에만 완료 파일 기록
- 완료 기록: macOS `${XDG_STATE_HOME:-$HOME/.local/state}/dev-init/ai-comm-init.initialized`, Windows `$env:LOCALAPPDATA\dev-init\ai-comm-init.initialized`
- 이전 `codex.initialized`, `claude.initialized` 기록은 통합 설정의 완료 기록으로 사용하지 않음
- 재설정: 통합 완료 파일을 삭제한 뒤 재실행. 실패하면 완료 기록을 남기지 않으므로 재시도 가능
- Windows 실행 위치: `$env:TEMP\ai-comm-init`
- macOS 실행 위치: `/tmp/ai-comm-init`
- 기존 개인 설정은 보존하며 강제 덮어쓰기 옵션을 전달하지 않음
- 설치 완료 출력의 Claude, Codex 등 개인 설정 병합 안내는 별도 작업
- macOS는 공통 CLI 실행 경로 `~/.local/bin`을 현재 프로세스와 `~/.zprofile`에 추가

수동 실행 예시:

```powershell
git clone https://github.com/codestreamkr/ai-comm-init.git $env:TEMP\ai-comm-init
if ($LASTEXITCODE -eq 0) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\ai-comm-init\install.ps1
}
```

```bash
git clone https://github.com/codestreamkr/ai-comm-init.git /tmp/ai-comm-init && bash /tmp/ai-comm-init/install.sh
```

## Claude 인증서 오류 대응

Claude 설치 파일은 OS의 기본 인증서 검증을 사용해 다운로드한다.

- Windows PowerShell 5.1에서는 TLS 1.2를 추가하고 설치 후 원래 프로토콜 설정을 복원
- 인증서 검증을 끄거나 검증 없는 다운로드로 재시도하지 않음
- 인증서 오류가 발생하면 시스템 시간과 신뢰 인증서, 회사 프록시의 인증서 설정을 확인한 뒤 재실행

## 운영 기준

이 저장소는 기본 개발환경 설치까지만 담당한다.

- 포함: 패키지 매니저 확인, Git 기반 저장소 복제, 기본 도구 설치, 설치 목록 관리
- 제외: 개인 계정 로그인, SSH 키 생성, 회사 내부 인증, 프로젝트별 환경 변수

## 이력관리

- 2026-10-16: AI 기본 설정 저장소를 ai-comm-init으로 통합하고 Claude PATH를 영구 설정
- 2026-10-16: Windows 패키지별 업데이트와 양쪽 Claude CLI 업데이트를 기본 동작으로 적용
- 2026-10-16: Java 8 제거, Node LTS 적용, Docker cask 이름 갱신, 인증서 검증 복구, AI 초기화 완료 기록 및 실패 처리 수정

- 2026-05-19: macOS Codex와 Claude 설치 여부 확인 추가
- 2026-05-19: 개발환경 자동화 최초 등록
