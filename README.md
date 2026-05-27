# ClCoBar (Claude + Codex Bar)

> Claude(`Cl`) + Codex(`Co`) 두 AI 의 사용량만 macOS 메뉴바에 표시하는 슬림 포크. UI 는 **한국어 전용**. 원본: [steipete/CodexBar](https://github.com/steipete/CodexBar).

현재 버전: **1.5.0**

<img width="520" height="60" alt="image" src="https://github.com/user-attachments/assets/31427d23-5648-4840-9e80-b1ed613ce963" />


## 요구사항

- macOS 14+ (Sonoma) — Companion 캐릭터 8종 중 일부 SF Symbol 은 macOS 15 (Sequoia)+ 필요 (미지원 OS 는 `pawprint.fill` 로 자동 fallback)
- Swift 6 toolchain (Xcode 16+ 또는 Command Line Tools)
- Apple Silicon (arm64) 기본. 인텔까지 지원하려면 universal 빌드 필요.

## 메뉴바 표시 (1.5.0 기준)

환경설정 → 표시 탭에서 메뉴바에 표시할 항목을 자유롭게 조합합니다.

**사용량 pill** (Claude / Codex 각각 한 개씩):
- **아이콘** — Claude/Codex 브랜드 글리프 (기본 ON)
- **퍼센트** — 남은/사용한 사용량 % 숫자 (기본 OFF)
- **배터리** — 사용량을 배터리 모양의 게이지로 (기본 ON)
- **시간** — 리셋까지 남은 시간 (기본 ON)
  - 시간 형식: 정확 (`2시간 14분 후`) / 근사치 (`~2h`) / 올림 (`2h+`) — 기본 **정확**

퍼센트와 시간을 동시에 켜면 `47% · 2h` 처럼 함께 표시됩니다.

**Companion 캐릭터** (선택, 기본 OFF):
- Apple SF Symbols vector 기반 8종 — 강아지 / 고양이 / 토끼 / 거북이 / 새 / 달리는 사람 / 불꽃 / 번개
- 추적 대상 (Claude 또는 Codex) 의 burn rate 에 따라 5 stage (휴식 / 느림 / 보통 / 빠름 / 폭주) 로 자동 변속
- Stage 임계값 (시간당 % 기준): idle 0~0.6%, slow 0.6~10%, normal 10~20%, fast 20~30%, burst ≥30%
- 5 프레임 cycle (회전 ±10°, 점프 -5px) 로 통통 튀는 motion

**자동 업데이트 알림** (1.4.0+):
- 1시간마다 `main` 의 `version.env` 익명 polling
- 새 버전 출시 시 메뉴에 "🆕 X.Y.Z 사용 가능 — 설치 안내" 한 줄 표시 (클릭 → Confluence 가이드 페이지)

**메뉴바 아이콘 자동 복구** (1.4.1+):
- macOS 가 NSStatusItem window 를 evict 한 경우 (장시간 idle / display sleep / Tahoe allow-list 등) 30초 안에 자동 복구. 사용자가 토글을 직접 끄지 않는 이상 메뉴바 아이콘은 사라지지 않음.

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

- **PATCH** (1.5.0 → 1.5.1) — 버그/번역/리팩토링
- **MINOR** (1.5.0 → 1.6.0) — 새 기능/옵션/토글
- **MAJOR** (1.5.0 → 2.0.0) — 설정 키 마이그레이션이나 대규모 재설계

같이 갱신: `version.env`, `docs/install-guide-ko.md` (zip 이름 + 다음 버전 예시), `docs/confluence-team-guide-ko.md` (히스토리 표 맨 위 새 행), `Scripts/install_for_team.sh` 주석. 상세는 [`CLAUDE.md`](CLAUDE.md) 참고.

## 개발

- 점진적 작업: `swift build` / `swift test`
- 전체 앱 번들 검증: `./Scripts/compile_and_run.sh`
- 빌드/배포 규칙 + 알려진 함정: [`CLAUDE.md`](CLAUDE.md)
- 리포 컨벤션: [`AGENTS.md`](AGENTS.md)

## 라이선스

MIT — [LICENSE](LICENSE). 원본 저작권 유지.
