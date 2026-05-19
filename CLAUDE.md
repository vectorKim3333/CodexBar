# ClCoBar — Claude Notes

Personal fork of `steipete/CodexBar`. Tracks **only Claude + Codex** usage in the macOS menu bar. UI is Korean-only.

## 핵심 규칙

- **표시명 ClCoBar**, **내부명 CodexBar 유지**. Info.plist `CFBundleDisplayName/Name` 만 ClCoBar. Swift 모듈명 (`CodexBar`, `CodexBarCore`, `CodexBarClaudeWatchdog`, `CodexBarClaudeWebProbe`, `CodexBarMacros`, `CodexBarMacroSupport`) · 파일 경로 (`/Applications/ClCoBar.app`, `~/.codexbar/`, `~/Library/Application Support/CodexBar/`) · UserDefaults suite · Keychain entry 는 전부 `CodexBar`. 변경 시 Keychain ACL / 캐시가 풀린다.
- **한국어 전용.** `Sources/CodexBar/Localization.swift` 가 항상 `ko.lproj` 우선, `en.lproj` 폴백. 언어 picker UI 없음. `CodexbarApp.applyLanguagePreference` 가 `AppleLanguages=["ko"]` 강제. 영어로 둘 용어: `Claude`, `Codex`, `ClCoBar`, `API`, `OAuth`, `CLI`, `PTY`, `Cookie`, `Token`, `Keychain`, `MCP`, `Chrome/Safari/Firefox`, `GitHub`, 플랜명 `Pro/Max/Team/Enterprise`.

## 빌드 / 배포

- **Xcode 없이도 빌드 가능.** `./Scripts/build_for_distribution.sh` 가 자동으로 KeyboardShortcuts/Recorder.swift 의 `#Preview` 블록을 패치(매크로 플러그인 회피) 후 ad-hoc 서명 zip 생성 → `dist/ClCoBar-<ver>-<arch>.zip`. SKIP_TEST=1 로 swift test 건너뛰기 (PreviewsMacros 가 test 도 막음).
- **배포된 zip 내부 .app 이름은 `ClCoBar.app`** (Finder 에서는 ClCoBar 로 표시). 팀원 안내: `docs/install-guide-ko.md`. 첫 실행은 우클릭→열기 (ad-hoc 서명이라 Gatekeeper 경고).
- **사용자 코드 변경 후 재설치**: `pkill -x CodexBar; rm -rf /Applications/ClCoBar.app; ditto -x -k dist/ClCoBar-*.zip /tmp/cb && mv /tmp/cb/ClCoBar.app /Applications/ && xattr -dr com.apple.quarantine /Applications/ClCoBar.app && open /Applications/ClCoBar.app`.

## 버전 관리 (자동)

코드 작업이 끝나면 변경 범위를 보고 **`version.env`** 의 `MARKETING_VERSION` 을 다음 기준으로 올린다. `BUILD_NUMBER` 는 항상 +1.

- **PATCH (1.1.0 → 1.1.1)** — 버그 수정 / 문구·번역 변경 / 로컬라이제이션 / 작은 UI 보정 / 리팩토링만. 외부에서 보이는 동작이 거의 그대로일 때.
- **MINOR (1.1.0 → 1.2.0)** — 새 기능·옵션·토글 추가 / 메뉴 항목 추가 / 설정 화면에 새 섹션 / 의미 있는 UX 변화. 호환은 깨지 않는 추가성 변경.
- **MAJOR (1.1.0 → 2.0.0)** — 설정/UserDefaults 키 구조 변경으로 마이그레이션 필요 / 모듈/타겟 추가·제거 / 기능 대규모 재설계나 제거. 팀원이 재설치 후 설정을 다시 해야 하는 수준일 때.

판단 애매하면 보수적으로 한 단계 아래(예: MINOR ↔ PATCH 사이면 PATCH).

**버전을 올리면 같이 갱신해야 하는 파일** (한 군데라도 빠지면 안내가 어긋남):
- `version.env` — `MARKETING_VERSION`, `BUILD_NUMBER`
- `docs/install-guide-ko.md` — zip 파일명 예시 (`ClCoBar-<v>-arm64.zip`) + 1-4 절의 "다음 버전 예시" 도 한 칸씩 위로
- `Scripts/install_for_team.sh` — 주석의 사용 예시

버전 올린 후엔 기존 `dist/ClCoBar-<이전버전>-arm64.zip` 을 지우고 `./Scripts/build_for_distribution.sh` 로 새 zip 만든 뒤 본인 환경에도 재설치(`pkill ... && ditto ... && open ...`)까지 한 번에 끝낸다.

## 알려진 함정

- **`@Observable` nested-struct setter 버그.** `SettingsStore.defaultsState.X = newValue` 직접 변형은 `withMutation` 을 발화시키지 못해 SwiftUI 관찰자가 못 본다. 새 setter 추가 시 **반드시** copy-modify-reassign:
  ```swift
  var state = self.defaultsState
  state.X = newValue
  self.defaultsState = state
  ```
- **PreviewsMacros 툴체인 이슈.** CLI 환경에선 SwiftUI `#Preview` 매크로 플러그인을 못 찾는다. `build_for_distribution.sh` 가 자동 패치. 새 외부 의존 추가 시 같은 매크로 쓰면 패치 함수 확장 필요.
- **Anthropic OAuth rate-limit (HTTP 429).** `UsageStore+Refresh.swift` 가 fetch 결과에서 429 / `rate_limit` 인지 시 `rateLimitBackoffUntil[provider] = now+600s` (10분) backoff 등록. 메뉴 열기는 추가로 120s cooldown (`StatusItemController+Menu.swift:menuOpenRefreshCooldown`).
- **NSMenu provider 등록.** 각 status item 의 메뉴는 `menuProviders[ObjectIdentifier(menu)] = provider` 등록되어 있고, `menuWillOpen` 에서 그걸로 `selectedMenuProvider` 를 강제 snap + `menuVersions[menu]` 캐시 무효화. Claude pill 클릭 → Claude 카드, Codex pill 클릭 → Codex 카드 보장.

## 메뉴바 아이콘

`IconRenderer.makeBatteryPillIcon(remaining:resetText:stale:brand:)` 가 그린다. **`remaining` 은 0~1 fraction**. `IconRemainingResolver.resolvedPercents` 가 `showUsed` 기반으로 used/remaining 중 적절한 percent 를 이미 반환하므로 **call site 에서 절대 다시 뒤집지 말 것** (이전에 double-flip 버그). 그냥 `primary.map { $0 / 100 }`.

## 제거된 기능 (다시 추가하지 말 것)

- 모든 다른 AI provider (41 개)
- Merge Icons 모드 + 다중 계정 layout picker
- CLI 타겟 (`CodexBarCLI`) + Widget 타겟 (`CodexBarWidget`)
- Sparkle 자동 업데이트 + Vortex 컨페티 + Commander dep
- Debug 탭 / PreferencesDebugPane
- Display: 할당량 경고 마커, 프로바이더 변경 이력 링크, 다중 계정 layout
- Advanced: 놀라게 해줘(`randomBlinkEnabled`), 주간 한도 컨페티, 프로바이더 저장소 사용량
- General: 프로바이더 상태 확인(statusChecksEnabled), 할당량 경고 알림(`quotaWarningNotificationsEnabled`)
- 메뉴 항목: Add Account... / Switch Account... / Changelog
- 카드 호버 강조 (배경 tint + 차트 바 화이트 플립)
- 자동 업데이트 / 언어 picker UI

## 유지된 기능

- Claude / Codex provider 코어 (OAuth/CLI PTY/Web cookies/Admin API for Claude; OAuth/CLI RPC/OpenAI web extras for Codex)
- `OpenAIWeb/` + `OpenAIDashboardModels` (Codex 가 의존)
- Display: 사용량을 사용한 만큼 표시 / 리셋 시간을 시각으로 / 크레딧·추가 사용량 표시
- General: 로그인 시 시작 / 비용 요약 표시 / 새로고침 주기 / 세션 할당량 알림 / 종료
- Advanced: 메뉴 열기 단축키 / 개인 정보 숨김 / Keychain 접근 비활성화
- 메뉴 status item 1 개씩 (Claude pill + Codex pill), 클릭 시 통합 메뉴 (Claude 카드 + Codex 카드 + Overview)

## 디렉토리 가이드

```
Sources/
  CodexBar/                  앱 본체 (StatusItem, Preferences, Menu)
  CodexBarCore/              provider 코어 (Claude/Codex 폴더 + OpenAIWeb)
  CodexBarClaudeWatchdog/    Claude CLI 워치독 데몬
  CodexBarClaudeWebProbe/    Claude 웹 세션 헬스체크
  CodexBarMacros/            매크로 정의
  CodexBarMacroSupport/      매크로 wrappers
docs/
  CLAUDE.md                  Claude provider 데이터 경로 상세
  codex.md / codex-oauth.md  Codex provider 데이터 경로
  install-guide-ko.md        팀원용 설치 가이드
  usage-guide-ko.md          한글 사용법
  refactor/                  Claude refactor 베이스라인
  superpowers/               spec/plan 문서
Scripts/
  build_for_distribution.sh  배포용 zip 빌드 (권장)
  compile_and_run.sh         로컬 개발 빌드+실행 (Xcode 필요)
  install_for_team.sh        팀원이 zip 받아 설치
```

## 외부 자료

- Claude 데이터 흐름 / OAuth scope / Cookie 자동 import 순서: [`docs/CLAUDE.md`](docs/CLAUDE.md)
- Codex `~/.codex/auth.json` 구조 / ChatGPT backend usage API: [`docs/codex.md`](docs/codex.md), [`docs/codex-oauth.md`](docs/codex-oauth.md)
- 팀 빌드/배포 흐름: [README.md](README.md) + [`docs/install-guide-ko.md`](docs/install-guide-ko.md)
