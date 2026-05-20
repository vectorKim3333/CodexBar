# ClCoBar (Claude + Codex Bar)

> Claude(`Cl`) + Codex(`Co`) 두 AI 의 사용량만 macOS 메뉴바에 표시하는 슬림 포크. UI 는 **한국어 전용**. 원본: [steipete/CodexBar](https://github.com/steipete/CodexBar).

현재 버전: **1.2.0**

## 요구사항

- macOS 14+ (Sonoma)
- Swift 6 toolchain (Xcode 16+ 또는 Command Line Tools)
- Apple Silicon (arm64) 기본. 인텔까지 지원하려면 universal 빌드 필요.

## 메뉴바 표시 (1.2.0 기준)

환경설정 → 표시 탭에서 메뉴바에 표시할 항목을 자유롭게 조합합니다.

- **아이콘** — Claude/Codex 브랜드 글리프 (기본 ON)
- **퍼센트** — 남은/사용한 사용량 % 숫자 (기본 OFF)
- **배터리** — 사용량을 배터리 모양의 게이지로 (기본 ON)
- **시간** — 리셋까지 남은 시간 (기본 ON)
  - 시간 형식: 정확 (`2시간 14분 후`) / 근사치 (`~2h`) / 올림 (`2h+`) — 기본 **정확**

퍼센트와 시간을 동시에 켜면 `47% · 2h` 처럼 함께 표시됩니다. 모두 끄면 메뉴바 클릭을 유지하기 위한 작은 placeholder 만 남습니다.

## 빌드 & 실행

```bash
swift build -c release
./Scripts/compile_and_run.sh   # 빌드 → 패키징 → 재실행 (Xcode 필요)
```

> Xcode 가 설치되지 않은 환경에서는 `./Scripts/build_for_distribution.sh` 를 사용하세요 (KeyboardShortcuts `#Preview` 매크로 회피 패치 포함, SKIP_TEST=1 로 테스트 건너뛰기 가능).

## 첫 실행

1. zip 받아서 `ClCoBar.app` 을 `/Applications` 로 이동
2. **우클릭 → 열기** (ad-hoc 서명이라 첫 실행은 Gatekeeper 우회 필요)
3. 메뉴바에 Claude / Codex pill 아이콘 두 개 등장
4. 인증은 자동 감지:
   - **Claude** — Claude CLI 의 OAuth credentials (`~/.claude/.credentials.json`) 또는 `claude.ai` 브라우저 쿠키 (Safari/Chrome/Firefox) 를 자동으로 가져옵니다.
   - **Codex** — Codex CLI 의 `~/.codex/auth.json` 또는 ChatGPT 웹 세션을 자동으로 사용합니다.

자세한 동작은 [`docs/claude.md`](docs/claude.md), [`docs/codex.md`](docs/codex.md), 한글 사용법은 [`docs/usage-guide-ko.md`](docs/usage-guide-ko.md) 참고.

## 팀 배포

ad-hoc 서명된 공유용 zip:

```bash
./Scripts/build_for_distribution.sh                          # 호스트 아키텍처 (arm64)
ARCHES="arm64 x86_64" ./Scripts/build_for_distribution.sh    # universal
```

`dist/ClCoBar-<version>-<arch>.zip` 이 만들어집니다 (내부 번들 이름은 `CodexBar` 유지, 사용자에게 표시되는 이름은 `ClCoBar`). Slack/Drive 등에 공유하고 동료에게는 [`docs/install-guide-ko.md`](docs/install-guide-ko.md) 를 같이 보내세요.

## 버전 관리

작업 후 `version.env` 의 `MARKETING_VERSION` 을 다음 기준으로 올립니다 (`BUILD_NUMBER` 는 항상 +1).

- **PATCH** (1.2.0 → 1.2.1) — 버그/번역/리팩토링
- **MINOR** (1.2.0 → 1.3.0) — 새 기능/옵션/토글
- **MAJOR** (1.2.0 → 2.0.0) — 설정 키 마이그레이션이나 대규모 재설계

같이 갱신: `version.env`, `docs/install-guide-ko.md` (zip 이름 + 다음 버전 예시), `Scripts/install_for_team.sh` 주석. 상세는 [`CLAUDE.md`](CLAUDE.md) 참고.

## 개발

- 점진적 작업: `swift build` / `swift test`
- 전체 앱 번들 검증: `./Scripts/compile_and_run.sh`
- 빌드/배포 규칙 + 알려진 함정: [`CLAUDE.md`](CLAUDE.md)
- 리포 컨벤션: [`AGENTS.md`](AGENTS.md)

## 라이선스

MIT — [LICENSE](LICENSE). 원본 저작권 유지.
