# CodexBar 슬림화 — Claude + Codex 전용 포크

작성일: 2026-05-18
작성자: sh.kim@madup.com (개인 포크용)

## 1. 목표

CodexBar(steipete/CodexBar) 포크에서 **Claude 와 Codex 두 provider 만** 추적하도록 코드베이스를 슬림화한다. 다른 AI provider 코드, 멀티-provider 가정 UI/설정, 원본의 배포·홍보 인프라, 그리고 Claude/Codex 동작에 불필요한 보조 타겟(CLI, Widget)을 모두 제거한다.

### 비목표
- 새 기능 추가 없음.
- 기능 동작 자체는 그대로(사용량 추적, 메뉴바 표시, 알림, 자동 시작 등 Claude/Codex 영역).
- 원본 upstream 과 sync 유지하지 않음(개인 포크).

## 2. 사전 결정 사항

| 항목 | 결정 |
|---|---|
| 정리 범위 | Provider 코드 + 관련 UI/설정 (균형) |
| 보조 타겟 | `CodexBarClaudeWatchdog`, `CodexBarClaudeWebProbe` 유지 / `CodexBarCLI`, `CodexBarWidget` 제거 |
| 작업 방식 | 단계별 커밋, 각 단계 끝에 `swift build` 통과 보장 |
| 배포 인프라 | Sparkle 자동 업데이트, appcast, CHANGELOG, 홈페이지 자산 모두 제거 |
| 검증 | 마지막 단계에서 사용자가 `Scripts/compile_and_run.sh` 로 메뉴바 동작 1회 확인 |

## 3. 결합도 분석 (사전 탐색 결과)

- **Codex → OpenAIWeb 의존성 있음**: `CodexWebDashboardStrategy.swift`, `CodexCLIDashboardAuthorityContext.swift`, `CodexReconciledState.swift` 가 `OpenAIWeb` / `OpenAIDashboardModels` 를 사용. 따라서 `Sources/CodexBarCore/OpenAIWeb/` 와 `OpenAIDashboardModels.swift` 는 **유지** 한다.
- **OpenAI provider 자체는 Codex 와 분리**: Admin API spend dashboard 용 별도 provider. 삭제 가능.
- **VertexAI** 는 Claude 로컬 로그를 읽지만 별도 provider 로만 동작. Claude 자체 추적 로직과 독립. 삭제 가능.
- **앱 본체 산재 파일**: `Sources/CodexBar/` 에 다른 provider 전용 토큰/쿠키 스토어, 메뉴 카드 확장, 로그인 러너가 흩어져 있음 (목록은 §4 참조).

## 4. 영향 범위

### 4-1. 삭제

#### Provider 코드 (`Sources/CodexBarCore/Providers/`)
다음을 제외한 53 폴더 모두 제거:
- 유지: `Claude/`, `Codex/`

#### 앱 본체 산재 파일 (`Sources/CodexBar/`)
- 토큰/쿠키 스토어: `CopilotTokenStore.swift`, `KimiK2TokenStore.swift`, `KimiTokenStore.swift`, `MiniMaxAPITokenStore.swift`, `MiniMaxCookieStore.swift`, `SyntheticTokenStore.swift`, `ZaiTokenStore.swift`
- 메뉴 카드 확장: `MenuCardView+Kiro.swift`, `MenuCardView+MiniMax.swift`
- 상태 컨트롤러 확장: `StatusItemController+ZaiHourlyChartMenu.swift`
- 차트 뷰: `ZaiHourlyUsageChartMenuView.swift`
- 로그인 러너: `CursorLoginRunner.swift`, `GeminiLoginRunner.swift`

> Step 2 에서 grep 으로 잔존 참조를 확인하면서 다른 provider 전용 파일이 추가로 식별되면 함께 제거.

#### 보조 타겟
- 폴더 제거: `Sources/CodexBarCLI/`, `Sources/CodexBarWidget/`
- `Package.swift` 에서 해당 target 정의 제거 + `Commander` 패키지 의존성 (CLI 전용) 제거

#### 배포·홍보 인프라
- `appcast.xml`
- `CHANGELOG.md`
- `docs/index.html`, `docs/CNAME`, `docs/social.png`
- `docs/logos/`, `docs/solutions/`, `docs/screenshots/`
- Claude/Codex 외 provider docs (`docs/abacus.md`, `docs/alibaba-coding-plan.md`, …, `docs/zai.md`)
- 유지할 provider docs: `docs/codex.md`, `docs/codex-oauth.md`, `docs/claude.md`, `docs/claude-comparison-since-0.18.0beta2.md` (마지막은 검토 후 결정)
- Sparkle 의존성 + `ENABLE_SPARKLE` 컴파일 플래그 제거 (Package.swift)
- Sparkle 호출 코드 비활성화 (앱 내 자동 업데이트 메뉴 항목)

### 4-2. 수정

#### UI / 설정 (`Sources/CodexBar/`)
멀티-provider 가정 코드 단순화:
- `PreferencesProvidersPane.swift` — 두 provider 만 표시, 토글 목록 단순화
- `SettingsStore.swift`, `SettingsStore+Defaults.swift`, `SettingsStore+ProviderDetection.swift` — 다른 provider 기본값/감지 로직 제거
- `MenuCardView.swift`, `MenuBarDisplayText.swift`, `MenuBarDisplayMode.swift`, `MenuBarMetricWindowResolver.swift`, `MenuBarVisibilityWatcher.swift` — 다른 provider 분기 제거
- `IconRenderer.swift`, `IconRemainingResolver.swift` — 다른 provider 아이콘/표시 로직 제거
- `UsageStore.swift`, `UsageStore+HighestUsage.swift`, `UsageStore+Accessors.swift` — 다른 provider case 제거
- `StatusItemController+Actions.swift`, `StatusItemController+Animation.swift` — 다른 provider 분기 제거
- `InlineUsageDashboardContent.swift`, `PreferencesDebugPane.swift`, `KeychainPromptCoordinator.swift` — 다른 provider 참조 제거
- `Localization.swift` — 다른 provider 문자열 제거
- `Config/` 하위 설정 스키마에서 다른 provider 필드 제거

> 각 파일은 grep 으로 잔존 참조를 확인하면서 점진적으로 정리. "정확히 어떤 줄을 지울지" 는 Step 2~3 진행 중 확정.

#### 패키지 / 빌드 설정
- `Package.swift` 정리: CLI/Widget target 제거, Sparkle 의존 제거, Commander 의존 제거
- `Makefile` 검토 — CLI 관련 타겟 제거
- `.github/` 워크플로 (있다면) — release/notarize/appcast 관련 단계 비활성화 또는 제거

#### 문서
- `README.md` 포크용으로 최소 재작성 (Claude + Codex 사용량 추적 메뉴바 앱; 빌드/실행 안내만)
- `AGENTS.md` 갱신 — 포크 컨텍스트 및 슬림화된 구조 반영
- `docs/architecture.md`, `docs/configuration.md`, `docs/cli-configuration.md`, `docs/cli.md` — 검토 후 보존/삭제/단순화 결정 (CLI 관련은 삭제)

### 4-3. 유지

- `Sources/CodexBarCore/Providers/Claude/`, `Codex/` 와 그 하위 모듈 (`ClaudeOAuth/`, `ClaudeWeb/`, `CodexOAuth/` 등)
- `Sources/CodexBarCore/OpenAIWeb/`, `OpenAIDashboardModels.swift` (Codex 가 사용)
- `Sources/CodexBarClaudeWatchdog/`, `Sources/CodexBarClaudeWebProbe/`
- `Sources/CodexBarMacros/`, `Sources/CodexBarMacroSupport/`
- 공통 인프라: `ProviderHTTPClient.swift`, `CookieHeader*`, `Keychain*`, `Logging/`, `Host/`, `WebKit/`, `Vendored/`, `UsageFetcher.swift`, `UsageFormatter.swift`, `UsagePace.swift`, `UsageStore.swift` (수정 후)
- `Tests/CodexBarTests/` 에서 Claude/Codex 관련 테스트는 유지, 다른 provider 테스트는 제거

## 5. 단계별 작업 계획 (5 단계 = 5 커밋)

각 단계 마지막에 `git commit`. 단계 진입 전 상태를 항상 복구 가능하도록 한다.

### Step 1 — Provider 코드 정리
- `Sources/CodexBarCore/Providers/` 에서 Claude/Codex 외 53 폴더 일괄 삭제.
- **빌드 결과**: 다른 곳에서 참조되어 `swift build` 실패 — **의도된 상태**. Step 2 에서 정리.
- 커밋: `chore: drop non-Claude/Codex provider sources`

### Step 2 — 앱 본체 산재 파일 제거 + 다른 provider 참조 끊기
- §4-1 의 앱 본체 산재 파일 삭제.
- `swift build` 실행 → 컴파일 에러 메시지를 가이드로 남은 파일에서 import / case / 분기 제거.
- `grep -rn "Kiro\|MiniMax\|Cursor\|Gemini\|Copilot\|Grok\|Ollama\|ElevenLabs\|Mistral\|Bedrock\|Augment\|Amp\|Kimi\|Kilo\|Doubao\|Manus\|DeepSeek\|JetBrains\|Warp\|Crof\|Codebuff\|Venice\|Perplexity\|Synthetic\|Windsurf\|OpenCode\|Antigravity\|Abacus\|Moonshot\|Zai\|Factory\|Droid\|MiMo\|StepFun\|CommandCode\|Alibaba\|Deepgram\|VertexAI\|OpenRouter\|Kiro" Sources/CodexBar Sources/CodexBarCore` 로 잔존 참조 확인.
- **빌드 결과**: `swift build` 통과 ✅
- 커밋: `chore: remove non-Claude/Codex references from app sources`

### Step 3 — UI / 설정 / 테스트 단순화
- `PreferencesProvidersPane.swift`, `SettingsStore*.swift`, `Localization.swift`, `MenuCardView.swift`, `IconRenderer.swift` 등에서 멀티-provider 가정 코드 단순화.
- `Tests/CodexBarTests/` 에서 다른 provider 테스트 / fixture 제거.
- **빌드 결과**: `swift build` + `swift test` 통과 ✅
- 커밋: `refactor: simplify UI/settings for Claude+Codex only`

### Step 4 — 보조 타겟 + 배포·홍보 인프라 제거
- `Sources/CodexBarCLI/`, `Sources/CodexBarWidget/` 폴더 삭제.
- `Package.swift` 에서 두 target + Sparkle + Commander 의존 제거. `ENABLE_SPARKLE` 컴파일 플래그 제거.
- 앱 내 Sparkle 호출 코드 제거 (자동 업데이트 메뉴/Updater 인스턴스 등).
- 배포 자산 제거: `appcast.xml`, `CHANGELOG.md`, `docs/index.html`, `docs/CNAME`, `docs/social.png`, `docs/logos/`, `docs/solutions/`, `docs/screenshots/`.
- 다른 provider docs 일괄 제거.
- `Makefile` 및 (있다면) `.github/` 워크플로 정리.
- **빌드 결과**: `swift build` + `swift test` 통과 ✅
- 커밋: `chore: drop CLI/Widget targets and upstream distribution assets`

### Step 5 — 문서 마무리 + 최종 검증
- `README.md` 포크용 최소 재작성.
- `AGENTS.md` 갱신.
- `docs/architecture.md` 등 잔존 문서 검토.
- `swift build -c release` + `swift test` 최종 실행.
- 사용자가 `Scripts/compile_and_run.sh` 로 메뉴바 동작을 한 번 확인 → Claude/Codex 카드 정상 표시, 다른 provider 자취 없음.
- 커밋: `docs: rewrite README/AGENTS for slim fork`

## 6. 검증 전략

- **자동**: 매 단계 끝 `swift build` 통과. Step 3·5 끝 `swift test` 통과.
- **수동(최종)**: `Scripts/compile_and_run.sh` 한 번 실행 → 메뉴바 클릭 시:
  - Claude 카드 정상 (OAuth/CLI/web 어떤 경로든 사용량 표시 OK)
  - Codex 카드 정상 (CLI dashboard authority 정상)
  - Preferences → Providers 에 두 항목만 노출
  - 메뉴/설정/단축키 흐름에서 다른 provider 이름 등장하지 않음

## 7. 위험 요소 및 대응

| # | 위험 | 대응 |
|---|---|---|
| R1 | Codex 의 OpenAIWeb/OpenAIDashboard 의존을 잘못 끊으면 Codex 깨짐 | Step 1 에서 OpenAIWeb 폴더 + OpenAIDashboardModels 는 손대지 않음. Codex provider 의 import 그대로 유지. |
| R2 | 남은 파일에 import/case/분기가 산재 — 한 번에 끊기 어려움 | Step 2 를 빌드 에러 0 이 될 때까지 반복. grep 명령으로 후속 잔존 참조 재확인. |
| R3 | 테스트 픽스처가 다른 provider 응답 기준 | Step 3 에서 해당 테스트와 fixture 함께 제거. |
| R4 | Sparkle 비활성화 시 메뉴/Updater 코드 잔존 가능 | Step 4 에서 `import Sparkle` / `SPUUpdater` / `SUUpdater` / `ENABLE_SPARKLE` 모두 grep 으로 확인 후 제거. |
| R5 | macOS 외 빌드 깨질 가능성(`TestsLinux`) | `TestsLinux/` 는 검토 후 유지/삭제 결정 (Linux CI 안 쓰면 삭제). |
| R6 | 사용자 환경에서 `swift test` 실패 (시스템 의존) | 단계 진행 중 실패 시 즉시 사용자에게 알리고 원인 파악. |

## 8. 미해결 / 후속 검토 사항

- `docs/architecture.md`, `docs/configuration.md`, `docs/claude-comparison-since-0.18.0beta2.md` — Step 5 진입 시점에 내용 보고 유지·단순화·삭제 결정.
- `TestsLinux/` 디렉토리 처리 — Step 4 에서 결정.
- `.github/` 워크플로 존재 여부 및 처리 — Step 4 에서 확인.
- `Icon.icns`, `codexbar.png`, `docs/codexbar.png` 등 아이콘/시각 자산 — 일단 유지(앱 아이콘 변경은 별도 작업으로 분리).
- `Makefile`, `Scripts/sign-and-notarize.sh`, `Scripts/make_appcast.sh` — 포크용으로는 불필요하지만 빌드 자체에는 영향 없음. Step 4 에서 삭제 또는 유지 결정.
