# CodexBar 슬림화 (Claude + Codex 전용) — 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CodexBar 포크에서 Claude + Codex 두 provider 만 동작하도록 다른 provider 코드, 멀티-provider UI/설정, 보조 타겟(CLI/Widget), 배포·홍보 인프라를 제거한다.

**Architecture:** 단계별 5 커밋. 각 단계는 (1) 파일/폴더 삭제 → (2) `swift build` 로 잔존 참조 식별 → (3) 잔존 참조 제거 → (4) 빌드(+테스트) 통과 → (5) 커밋. 코드 제거 작업이므로 TDD 가 어색 — 대신 `swift build` / `swift test` 통과를 회귀 검증 게이트로 사용한다.

**Tech Stack:** Swift 6.x, Swift Package Manager (SwiftPM), macOS 14+ AppKit, Sparkle(제거 대상), Sindre `KeyboardShortcuts`, `swift-log`, `swift-syntax` 매크로, `SweetCookieKit`.

**Working directory:** `/Users/madup/Developer/CodexBar` (모든 경로는 이 디렉토리 기준 상대경로).

**스펙:** `docs/superpowers/specs/2026-05-18-codexbar-slim-claude-codex-design.md` (commit `c822d88f`)

---

## 작업 기준선 (모든 Task 공통)

- 빌드 명령: `swift build`
- 테스트 명령: `swift test`
- 릴리스 빌드 (마지막 단계): `swift build -c release`
- 절대로 사용 금지: `git push --force`, `git reset --hard` (사용자 승인 없이), `--no-verify`
- 각 Task 마지막 커밋 메시지에 `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` 포함

**제거 대상 provider 키워드 (모든 grep 의 기준 목록):**

```
Abacus, Alibaba, Amp, Antigravity, Augment, Bedrock, Codebuff, CommandCode,
Copilot, Crof, Cursor, DeepSeek, Deepgram, Doubao, ElevenLabs, Factory,
Gemini, Grok, JetBrains, Kilo, Kimi, KimiK2, Kiro, Manus, MiMo, MiniMax,
Mistral, Moonshot, Ollama, OpenAI(except OpenAIWeb/OpenAIDashboardModels —
Codex 의존), OpenCode, OpenCodeGo, OpenRouter, Perplexity, StepFun,
Synthetic, Venice, VertexAI, Warp, Windsurf, Zai
```

> 주의: `OpenAI` 는 두 가지가 있다.
> - `Sources/CodexBarCore/Providers/OpenAI/` — Admin API spend dashboard 용 provider. **삭제 대상.**
> - `Sources/CodexBarCore/OpenAIWeb/`, `OpenAIDashboardModels.swift` — Codex 가 OpenAI 웹 대시보드 데이터를 읽을 때 사용. **유지.**
> - 앱 본체의 `OpenAIAPIUsageChartMenuView.swift`, `OpenAICreditsPurchaseWindowController.swift` — OpenAI provider 전용. **삭제 대상.**
> - 앱 본체의 `UsageStore+OpenAIWeb.swift` — OpenAIWeb 데이터를 Codex 카드에 반영하는 어댑터일 가능성. Task 2 에서 내용 보고 유지 결정.

---

## Task 1: Provider 코드 정리

**목표:** `Sources/CodexBarCore/Providers/` 에서 Claude/Codex 외 41 폴더 삭제. 빌드는 깨진 상태로 두고 Task 2 에서 참조 정리.

**Files:**
- Delete: `Sources/CodexBarCore/Providers/{Abacus,Alibaba,Amp,Antigravity,Augment,Bedrock,Codebuff,CommandCode,Copilot,Crof,Cursor,DeepSeek,Deepgram,Doubao,ElevenLabs,Factory,Gemini,Grok,JetBrains,Kilo,Kimi,KimiK2,Kiro,Manus,MiMo,MiniMax,Mistral,Moonshot,Ollama,OpenAI,OpenCode,OpenCodeGo,OpenRouter,Perplexity,StepFun,Synthetic,Venice,VertexAI,Warp,Windsurf,Zai}/`
- Keep (변경 없음): `Sources/CodexBarCore/Providers/Claude/`, `Codex/`
- Keep (Task 2/3 에서 case 정리): `Sources/CodexBarCore/Providers/*.swift` (공통 인프라 12 파일: `Providers.swift`, `ProviderDescriptor.swift`, `ProviderBranding.swift`, `ProviderCLIConfig.swift`, `ProviderCandidateRetryRunner.swift`, `ProviderCookieSource.swift`, `ProviderFetchPlan.swift`, `ProviderInteractionContext.swift`, `ProviderSettingsSnapshot.swift`, `ProviderTokenResolver.swift`, `ProviderVersionDetector.swift`, `CLIProbeSessionResetter.swift`)

- [ ] **Step 1: 작업 시작 전 상태 스냅샷**

```bash
cd /Users/madup/Developer/CodexBar
git status
git log --oneline -3
```

Expected:
```
On branch main
nothing to commit, working tree clean
c822d88f docs: add Claude+Codex slim fork design spec
...
```

- [ ] **Step 2: 삭제 전 폴더 목록 확인 (안전 가드)**

```bash
ls Sources/CodexBarCore/Providers/ | grep -v '^Claude$' | grep -v '^Codex$' | grep -v '\.swift$' | sort
```

Expected: 41 폴더 이름이 알파벳 순으로 출력 (Abacus … Zai). 만약 41개가 아니면 즉시 중단하고 사용자에게 알린다.

- [ ] **Step 3: 41 폴더 일괄 삭제**

```bash
cd /Users/madup/Developer/CodexBar
for d in Abacus Alibaba Amp Antigravity Augment Bedrock Codebuff CommandCode \
         Copilot Crof Cursor DeepSeek Deepgram Doubao ElevenLabs Factory \
         Gemini Grok JetBrains Kilo Kimi KimiK2 Kiro Manus MiMo MiniMax \
         Mistral Moonshot Ollama OpenAI OpenCode OpenCodeGo OpenRouter \
         Perplexity StepFun Synthetic Venice VertexAI Warp Windsurf Zai; do
  rm -rf "Sources/CodexBarCore/Providers/$d"
done
ls Sources/CodexBarCore/Providers/
```

Expected: 출력에 `Claude`, `Codex`, 그리고 공통 인프라 12 `.swift` 파일만 남는다.

- [ ] **Step 4: 빌드 시도 (실패 예상 — 컴파일 에러 메시지를 Task 2 의 지도로 사용)**

```bash
swift build 2>&1 | tee /tmp/codexbar-step1-build.log | tail -50
```

Expected: 다수의 `error: cannot find 'XxxProvider' in scope` / `error: no such module` 류 에러. 빌드 실패. **이는 의도된 상태**.

- [ ] **Step 5: 변경 사항 검토 + 커밋**

```bash
git status | head -20
git add -u Sources/CodexBarCore/Providers/
```

> `-u` 는 추적 중 파일의 삭제만 스테이지. 새 파일은 의도적으로 무시.

```bash
git commit -m "$(cat <<'EOF'
chore: drop non-Claude/Codex provider sources

Removes 41 provider folders under Sources/CodexBarCore/Providers/.
Build is intentionally broken at this step; the next commit removes
remaining references in app sources and common provider scaffolding.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git log --oneline -2
```

Expected: 새 커밋이 HEAD. 변경 통계에 41 폴더 / 수백 파일 삭제 표시.

---

## Task 2: 앱 본체 산재 파일 제거 + 잔존 참조 끊기

**목표:** Claude/Codex 외 provider 전용 산재 파일을 삭제하고, 공통 인프라/UI/UsageStore/SettingsStore 등에 흩어진 다른 provider 참조를 모두 제거해 `swift build` 가 통과하도록 한다.

**Files:**
- Delete (앱 본체 provider 전용):
  - `Sources/CodexBar/CopilotTokenStore.swift`
  - `Sources/CodexBar/KimiK2TokenStore.swift`
  - `Sources/CodexBar/KimiTokenStore.swift`
  - `Sources/CodexBar/MiniMaxAPITokenStore.swift`
  - `Sources/CodexBar/MiniMaxCookieStore.swift`
  - `Sources/CodexBar/SyntheticTokenStore.swift`
  - `Sources/CodexBar/ZaiTokenStore.swift`
  - `Sources/CodexBar/MenuCardView+Kiro.swift`
  - `Sources/CodexBar/MenuCardView+MiniMax.swift`
  - `Sources/CodexBar/StatusItemController+ZaiHourlyChartMenu.swift`
  - `Sources/CodexBar/ZaiHourlyUsageChartMenuView.swift`
  - `Sources/CodexBar/CursorLoginRunner.swift`
  - `Sources/CodexBar/GeminiLoginRunner.swift`
  - `Sources/CodexBar/OpenAIAPIUsageChartMenuView.swift`
  - `Sources/CodexBar/OpenAICreditsPurchaseWindowController.swift`
- Modify (잔존 참조 제거 — 빌드 에러를 따라가며 수정):
  - `Sources/CodexBarCore/Providers/Providers.swift`
  - `Sources/CodexBarCore/Providers/ProviderDescriptor.swift`
  - `Sources/CodexBarCore/Providers/ProviderBranding.swift`
  - `Sources/CodexBarCore/Providers/ProviderCLIConfig.swift`
  - `Sources/CodexBarCore/Providers/ProviderCookieSource.swift`
  - `Sources/CodexBarCore/Providers/ProviderFetchPlan.swift`
  - `Sources/CodexBarCore/Providers/ProviderSettingsSnapshot.swift`
  - `Sources/CodexBarCore/Providers/ProviderTokenResolver.swift`
  - `Sources/CodexBarCore/Providers/ProviderVersionDetector.swift`
  - `Sources/CodexBarCore/Providers/ProviderCandidateRetryRunner.swift`
  - `Sources/CodexBarCore/Providers/ProviderInteractionContext.swift`
  - `Sources/CodexBarCore/Providers/CLIProbeSessionResetter.swift`
  - `Sources/CodexBarCore/TokenAccountSupport.swift`
  - `Sources/CodexBarCore/TokenAccountSupportCatalog+Data.swift`
  - `Sources/CodexBarCore/TokenAccounts.swift`
  - `Sources/CodexBar/CodexbarApp.swift` (다른 provider 초기화/등록 코드)
  - `Sources/CodexBar/ProviderRegistry.swift`
  - `Sources/CodexBar/ProviderToggleStore.swift`
  - `Sources/CodexBar/ProviderBrandIcon.swift`
  - `Sources/CodexBar/Notifications+CodexBar.swift`
  - `Sources/CodexBar/UsageStore.swift` + `UsageStore+*.swift` 시리즈 (다른 provider case)
  - `Sources/CodexBar/StatusItemController+*.swift` 시리즈 (다른 provider 분기)
  - `Sources/CodexBar/MenuCardView.swift`, `MenuContent.swift`, `MenuDescriptor.swift`
  - `Sources/CodexBar/Localization.swift`
  - 기타 빌드 에러가 가리키는 모든 파일

> 이 Task 는 빌드 에러를 가이드 삼아 점진적으로 진행한다. 아래 step 들은 "한 번 돌리고 끝" 이 아니라 "에러가 0 이 될 때까지 step 6 ↔ step 7 루프" 임을 명심한다.

- [ ] **Step 1: 앱 본체 산재 파일 일괄 삭제**

```bash
cd /Users/madup/Developer/CodexBar
rm -f Sources/CodexBar/CopilotTokenStore.swift \
      Sources/CodexBar/KimiK2TokenStore.swift \
      Sources/CodexBar/KimiTokenStore.swift \
      Sources/CodexBar/MiniMaxAPITokenStore.swift \
      Sources/CodexBar/MiniMaxCookieStore.swift \
      Sources/CodexBar/SyntheticTokenStore.swift \
      Sources/CodexBar/ZaiTokenStore.swift \
      Sources/CodexBar/MenuCardView+Kiro.swift \
      Sources/CodexBar/MenuCardView+MiniMax.swift \
      Sources/CodexBar/StatusItemController+ZaiHourlyChartMenu.swift \
      Sources/CodexBar/ZaiHourlyUsageChartMenuView.swift \
      Sources/CodexBar/CursorLoginRunner.swift \
      Sources/CodexBar/GeminiLoginRunner.swift \
      Sources/CodexBar/OpenAIAPIUsageChartMenuView.swift \
      Sources/CodexBar/OpenAICreditsPurchaseWindowController.swift
ls Sources/CodexBar | wc -l
```

Expected: 약 132 (147 - 15) 정도. 정확한 수치는 환경에 따라 다를 수 있으니 참고용.

- [ ] **Step 2: `UsageStore+OpenAIWeb.swift` 파일 내용 확인 → 유지 여부 결정**

```bash
sed -n '1,80p' Sources/CodexBar/UsageStore+OpenAIWeb.swift
```

판단 기준:
- 파일이 Codex 카드/Codex 사용량 표시를 위해 `OpenAIWeb` 모듈을 호출한다면 **유지** (변경 없이 통과).
- 파일이 (삭제된) OpenAI provider 의 카드 자체를 위해 작성된 것이라면 **삭제**.
- 모호하면 Codex 가 import 하는지 grep 으로 확인:
  ```bash
  grep -rn "OpenAIWebUsage\|OpenAIWebFetcher\|OpenAIDashboard" Sources/CodexBarCore/Providers/Codex Sources/CodexBar/UsageStore.swift | head -20
  ```
- 결정 후 (삭제 시): `rm Sources/CodexBar/UsageStore+OpenAIWeb.swift`. 유지 시 변경 없음.

- [ ] **Step 3: 빌드 한 번 돌려 에러 지도 확보**

```bash
swift build 2>&1 | tee /tmp/codexbar-step2-build-1.log | grep -E "error:" | head -60
```

Expected: 다수의 에러. 흔히 다음 패턴:
- `error: cannot find 'XxxProvider' in scope`
- `error: type 'Provider' has no member 'xxx'`
- `error: cannot find type 'XxxUsageFetcher' in scope`
- `error: cannot find 'XxxTokenStore' in scope`
- `error: 'xxx' is unavailable` (enum case 제거 후)

- [ ] **Step 4: 공통 인프라 파일 정리 (Providers.swift / ProviderDescriptor.swift)**

`Sources/CodexBarCore/Providers/Providers.swift` 를 열고 다른 provider enum case / registry 항목을 제거한다. 패턴 예시:

```swift
// Before
enum Provider: String, CaseIterable {
    case claude
    case codex
    case openai
    case cursor
    case gemini
    // ... 등 40+ case
}

// After
enum Provider: String, CaseIterable {
    case claude
    case codex
}
```

`ProviderDescriptor.swift`, `ProviderBranding.swift`, `ProviderCLIConfig.swift`, `ProviderCookieSource.swift`, `ProviderFetchPlan.swift`, `ProviderSettingsSnapshot.swift`, `ProviderTokenResolver.swift`, `ProviderVersionDetector.swift` 도 동일한 방식으로 다른 provider 관련 분기/매핑/팩토리 호출 제거.

> 정확한 코드는 파일을 열어 본 뒤 확정. 핵심 원칙: **case 자체가 사라지면 그 case 를 참조하던 switch / dictionary entry / case array 도 함께 제거**.

- [ ] **Step 5: TokenAccountSupport / 카탈로그 정리**

`Sources/CodexBarCore/TokenAccountSupport.swift`, `TokenAccountSupportCatalog+Data.swift`, `TokenAccounts.swift` 에서 다른 provider 토큰 계정 정의 제거. Claude / Codex 항목만 남긴다.

- [ ] **Step 6: 빌드 → 에러 → 수정 루프**

```bash
swift build 2>&1 | tee /tmp/codexbar-step2-build-N.log | grep -E "error:" | head -40
```

각 에러를 따라 해당 파일을 열고 수정:
- `case .xxx:` 분기 → 분기 자체 제거 (또는 `default:` 로 흡수)
- `XxxTokenStore`, `XxxLoginRunner`, `XxxUsageFetcher` import / 참조 → 제거
- `Localization.swift` 의 `"provider.xxx.title"` 등 키 → 제거
- 다른 provider 만을 위한 helper 함수 → 함수 자체 제거 + 호출처 정리

에러가 0 이 될 때까지 반복.

> **잔존 참조 grep 으로 후속 확인** (에러가 없어도 텍스트 잔존이 있을 수 있음):
> ```bash
> grep -rnE "Abacus|Alibaba|Amp[A-Z]|Antigravity|Augment|Bedrock|Codebuff|CommandCode|Copilot|Crof|Cursor[A-Z]|DeepSeek|Deepgram|Doubao|ElevenLabs|Factory|Gemini|Grok|JetBrains|Kilo|Kimi|KimiK2|Kiro|Manus|MiMo|MiniMax|Mistral|Moonshot|Ollama|OpenCode|OpenCodeGo|OpenRouter|Perplexity|StepFun|Synthetic|Venice|VertexAI|Warp|Windsurf|Zai" Sources/CodexBar Sources/CodexBarCore | grep -v "OpenAIWeb\|OpenAIDashboard" | head -40
> ```
> 출력이 있으면 해당 위치의 텍스트(코멘트 / case / dictionary key)를 확인하고 의미 있는 것이면 제거.

- [ ] **Step 7: 빌드 통과 확인**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!` (warning 은 허용, error 0).

- [ ] **Step 8: 최소 회귀 확인 (테스트는 Task 3 에서 본격 정리)**

```bash
swift build --target CodexBarCore 2>&1 | tail -3
```

Expected: `Build complete!`

- [ ] **Step 9: 커밋**

```bash
git status | head -30
git add -A
git commit -m "$(cat <<'EOF'
chore: remove non-Claude/Codex references from app sources

- Delete provider-specific files scattered under Sources/CodexBar
- Strip non-Claude/Codex cases from common provider scaffolding
  (Providers.swift, ProviderDescriptor.swift, TokenAccount*.swift, etc.)
- swift build now passes; tests still need cleanup (next commit)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git log --oneline -3
```

Expected: 새 커밋이 HEAD.

---

## Task 3: UI/설정/테스트 단순화

**목표:** Preferences UI, SettingsStore, Localization, MenuCardView 등에서 멀티-provider 가정을 단순화한다. 테스트 픽스처에서 다른 provider 관련 항목을 제거한다. `swift build` + `swift test` 모두 통과.

**Files:**
- Modify:
  - `Sources/CodexBar/PreferencesProvidersPane.swift`
  - `Sources/CodexBar/PreferencesProvidersPane+Testing.swift`
  - `Sources/CodexBar/PreferencesProviderSidebarView.swift`
  - `Sources/CodexBar/PreferencesProviderDetailView.swift`
  - `Sources/CodexBar/PreferencesProviderSettingsRows.swift`
  - `Sources/CodexBar/PreferencesProviderSettingsMetrics.swift`
  - `Sources/CodexBar/PreferencesProviderErrorView.swift`
  - `Sources/CodexBar/PreferencesGeneralPane.swift`
  - `Sources/CodexBar/PreferencesDisplayPane.swift`
  - `Sources/CodexBar/PreferencesAdvancedPane.swift`
  - `Sources/CodexBar/PreferencesDebugPane.swift`
  - `Sources/CodexBar/PreferencesAboutPane.swift`
  - `Sources/CodexBar/PreferencesComponents.swift`
  - `Sources/CodexBar/PreferencesSelection.swift`
  - `Sources/CodexBar/PreferencesView.swift`
  - `Sources/CodexBar/SettingsStore.swift`
  - `Sources/CodexBar/SettingsStore+Defaults.swift`
  - `Sources/CodexBar/SettingsStore+ProviderDetection.swift`
  - `Sources/CodexBar/SettingsStore+Config.swift`
  - `Sources/CodexBar/SettingsStore+ConfigPersistence.swift`
  - `Sources/CodexBar/SettingsStore+MenuObservation.swift`
  - `Sources/CodexBar/SettingsStore+MenuPreferences.swift`
  - `Sources/CodexBar/SettingsStore+TokenAccounts.swift`
  - `Sources/CodexBar/SettingsStore+TokenCost.swift`
  - `Sources/CodexBar/Config/` 하위 (스키마 파일)
  - `Sources/CodexBar/Localization.swift`
  - `Sources/CodexBar/IconRenderer.swift`, `IconRemainingResolver.swift`
  - `Sources/CodexBar/MenuCardView.swift`, `MenuContent.swift`, `MenuDescriptor.swift`
  - `Sources/CodexBar/MenuBarDisplayText.swift`, `MenuBarDisplayMode.swift`, `MenuBarMetricWindowResolver.swift`, `MenuBarVisibilityWatcher.swift`
- Test:
  - `Tests/CodexBarTests/` — 다른 provider 테스트 파일 / 픽스처 제거
  - `Tests/CodexBarTests/Fixtures/` — Claude/Codex 외 fixture 삭제
  - `TestsLinux/` — 동일하게 정리

- [ ] **Step 1: Preferences pane provider 목록 단순화**

`PreferencesProvidersPane.swift` 와 `PreferencesProviderSidebarView.swift` 에서 표시할 provider 목록 / 정렬 / 그룹화 코드를 Claude + Codex 만으로 단순화.

Task 2 에서 `Provider` enum 자체를 두 case 로 줄였으므로, 여기서는 다음을 확인:
- `Provider.allCases` 를 그대로 쓰는 위치는 자동으로 두 개만 표시됨 → 추가 작업 불필요.
- 하드코딩된 "merge icons", "provider 그룹화" 같은 옵션 UI 가 있으면 단순화 (단일 모드만 유지).

수정 후:
```bash
swift build 2>&1 | tail -3
```

Expected: `Build complete!`

- [ ] **Step 2: SettingsStore 기본값 / 감지 로직 단순화**

`SettingsStore+Defaults.swift` → 다른 provider 기본 toggle 값 제거. 두 provider 모두 기본 ON.

`SettingsStore+ProviderDetection.swift` → 다른 provider 자동 감지 (CLI 설치 여부 / 쿠키 존재 여부 등) 로직 제거. Claude / Codex 감지만 유지.

`SettingsStore+TokenAccounts.swift`, `SettingsStore+TokenCost.swift` 도 동일한 방식.

수정 후:
```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 3: Localization 키 제거**

```bash
grep -nE "provider\.(abacus|alibaba|amp|antigravity|augment|bedrock|codebuff|commandcode|copilot|crof|cursor|deepseek|deepgram|doubao|elevenlabs|factory|gemini|grok|jetbrains|kilo|kimi|kiro|manus|mimo|minimax|mistral|moonshot|ollama|opencode|openrouter|perplexity|stepfun|synthetic|venice|vertexai|warp|windsurf|zai)" Sources/CodexBar/Localization.swift | head -30
```

매칭되는 키 / 값을 모두 제거. Claude / Codex 만 남긴다. macOS 리소스 bundle 의 `.strings` 파일이 있는지도 확인:

```bash
find Sources/CodexBar/Resources -name '*.strings' 2>/dev/null
```

있다면 동일한 방식으로 정리.

- [ ] **Step 4: Menu/Icon/Display 분기 정리**

`MenuCardView.swift`, `MenuContent.swift`, `MenuDescriptor.swift`, `IconRenderer.swift`, `IconRemainingResolver.swift`, `MenuBarDisplayText.swift`, `MenuBarDisplayMode.swift`, `MenuBarMetricWindowResolver.swift` 에서:
- `switch provider { case .xxx: ... }` 의 다른 provider 분기 제거 (이미 Task 2 에서 컴파일 에러로 사라졌을 가능성 큼)
- 다른 provider 전용 helper 함수 / 상수 제거
- 다른 provider 텍스트 / 이모지 / 아이콘 매핑 제거

수정 후:
```bash
swift build 2>&1 | tail -3
```

Expected: `Build complete!`

- [ ] **Step 5: Config 스키마 정리**

```bash
ls Sources/CodexBar/Config Sources/CodexBarCore/Config 2>/dev/null
```

해당 스키마 파일을 열어 다른 provider 필드/섹션을 제거. `~/.codexbar/config.json` 의 호환성은 우려하지 않음(개인 포크).

수정 후:
```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 6: 테스트 픽스처 정리**

```bash
ls Tests/CodexBarTests/ Tests/CodexBarTests/Fixtures/ 2>/dev/null | head -60
```

- 파일명에 Claude/Codex 외 provider 이름이 들어간 모든 테스트 파일 삭제: `rm Tests/CodexBarTests/<Provider>*Tests.swift`
- `Tests/CodexBarTests/Fixtures/` 내 다른 provider 응답 fixture 폴더/파일 삭제
- `TestsLinux/` 도 동일하게 정리 (또는 Task 4 에서 폴더째 삭제 결정 시 일단 유지)

> 의도치 않게 Claude/Codex 테스트를 삭제하지 않도록 한 폴더씩 `ls` 로 확인 후 `rm`.

- [ ] **Step 7: 빌드 + 테스트 전체 실행**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tee /tmp/codexbar-step3-test.log | tail -20
```

Expected: 빌드 통과 + 모든 테스트 PASS. 실패 시 실패 메시지를 보고 해당 파일을 수정.

> Note: macOS CI 가 헤드리스에서 `NSStatusBar`/`NSMenu` 테스트에 취약하다는 AGENTS.md 주의사항이 있다. 만약 헤드리스 테스트 실패가 환경 의존 (가령 CodexBar.app 이 이미 실행 중) 으로 보이면 `pkill -x CodexBar || true` 후 재시도.

- [ ] **Step 8: 커밋**

```bash
git status | head -40
git add -A
git commit -m "$(cat <<'EOF'
refactor: simplify UI/settings/tests for Claude+Codex only

- Strip multi-provider assumptions from Preferences panes, SettingsStore,
  MenuCard/Icon/Display layers, and Localization keys.
- Drop test fixtures and test files for removed providers.
- swift build + swift test now pass on Claude+Codex slice.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git log --oneline -4
```

---

## Task 4: 보조 타겟 + 배포·홍보 인프라 제거

**목표:** `CodexBarCLI`, `CodexBarWidget` 타겟·폴더 제거. Sparkle 자동 업데이트 제거. `appcast.xml`, `CHANGELOG.md`, 홈페이지 자산, 다른 provider docs 제거. `swift build` + `swift test` 통과.

**Files:**
- Delete (폴더):
  - `Sources/CodexBarCLI/`
  - `Sources/CodexBarWidget/`
  - `docs/logos/`
  - `docs/solutions/`
  - `docs/screenshots/`
- Delete (파일):
  - `appcast.xml`
  - `CHANGELOG.md`
  - `docs/index.html`
  - `docs/CNAME`
  - `docs/social.png` (있다면)
  - `docs/llms.txt`
  - 다른 provider docs (목록은 Step 6 에서 동적으로 결정)
- Modify:
  - `Package.swift` — `CodexBarCLI`/`CodexBarWidget` target 제거, `Sparkle`/`Commander` 의존 제거, `ENABLE_SPARKLE` 제거, `CodexBarLinuxTests` 검토
  - `Sources/CodexBar/CodexbarApp.swift` — Sparkle 초기화 / Updater 인스턴스 제거
  - `Sources/CodexBar/PreferencesAboutPane.swift` — "Check for Updates" 메뉴/버튼 제거
  - `Sources/CodexBar/UpdateChannel.swift` — 전부 삭제
  - `Sources/CodexBar/PreferencesGeneralPane.swift` — Update 관련 설정 행 제거 (있다면)
  - `Makefile` — release / appcast 관련 타겟 제거
  - `Scripts/sign-and-notarize.sh`, `Scripts/make_appcast.sh` — 삭제

- [ ] **Step 1: CLI / Widget 타겟 폴더 삭제**

```bash
cd /Users/madup/Developer/CodexBar
rm -rf Sources/CodexBarCLI Sources/CodexBarWidget
ls Sources/
```

Expected: `CodexBar`, `CodexBarClaudeWatchdog`, `CodexBarClaudeWebProbe`, `CodexBarCore`, `CodexBarMacroSupport`, `CodexBarMacros` 만 남는다.

- [ ] **Step 2: Package.swift 정리**

`Package.swift` 를 열고 다음 변경:

1. `dependencies` 에서 `Sparkle`, `Commander` 라인 제거.
2. `targets:` 클로저에서:
   - `.executableTarget(name: "CodexBarCLI", ...)` 블록 제거
   - `.executableTarget(name: "CodexBarWidget", ...)` 블록 제거
   - `.target(name: "CodexBarCore", ...)` 의 `dependencies` 그대로 (Commander 가 여기 없는지 확인; 있으면 제거)
   - `CodexBar` target 의 `dependencies` 에서 `.product(name: "Sparkle", package: "Sparkle")` 제거
   - `CodexBar` target 의 `swiftSettings` 에서 `.define("ENABLE_SPARKLE")` 제거
3. `CodexBarLinuxTests` target 의 `dependencies` 에서 `"CodexBarCLI"` 제거. CLI 의존이 빠지면 의미가 줄어드니 폴더 자체 삭제도 고려 (Step 9 에서 처리).
4. `CodexBarTests` target 의 `dependencies` 에서 `"CodexBarCLI"`, `"CodexBarWidget"` 제거.

수정 후:
```bash
swift package resolve 2>&1 | tail -10
swift build 2>&1 | tail -10
```

Expected: 의존 resolve 후 빌드 시 `Sparkle` / `SPUUpdater` / `SUUpdater` 미해결 에러가 등장 (Step 3 에서 제거).

- [ ] **Step 3: Sparkle 코드 제거**

```bash
grep -rn "import Sparkle\|SPUUpdater\|SUUpdater\|ENABLE_SPARKLE" Sources/CodexBar/ 2>&1 | head -20
```

각 매칭 위치를 열어:
- `import Sparkle` 줄 제거
- `#if ENABLE_SPARKLE ... #endif` 블록 → 블록 전체 제거 (Sparkle 비활성)
- Sparkle Updater 인스턴스 / Delegate / 호출 → 제거
- "Check for Updates" 메뉴 항목 → 제거

핵심 파일:
- `Sources/CodexBar/CodexbarApp.swift`
- `Sources/CodexBar/PreferencesAboutPane.swift`
- `Sources/CodexBar/UpdateChannel.swift` — 파일 자체 삭제: `rm Sources/CodexBar/UpdateChannel.swift`
- `Sources/CodexBar/PreferencesGeneralPane.swift` (있을 수 있음)

수정 후:
```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: 배포·홍보 자산 제거**

```bash
cd /Users/madup/Developer/CodexBar
rm -f appcast.xml CHANGELOG.md
rm -f docs/index.html docs/CNAME docs/social.png docs/llms.txt
rm -rf docs/logos docs/solutions docs/screenshots
ls docs | head -40
```

- [ ] **Step 5: 다른 provider docs 일괄 제거**

유지할 docs 목록:
- `docs/claude.md`
- `docs/codex.md`
- `docs/codex-oauth.md`
- `docs/CLAUDE.md` (claude provider 컨텍스트 문서; 시스템 reminder 에 명시)
- `docs/architecture.md`, `docs/configuration.md` — Step 9 에서 내용 보고 결정
- `docs/refactor/` 폴더 — Claude refactor 베이스라인 (유지)
- `docs/superpowers/` — 우리가 작성 중인 spec/plan 문서 (유지)
- `docs/DEVELOPMENT.md`, `docs/DEVELOPMENT_SETUP.md`, `docs/RELEASING.md`, `docs/FORK_QUICK_START.md`, `docs/FORK_ROADMAP.md`, `docs/FORK_SETUP.md`, `docs/ISSUE_LABELING.md`, `docs/KEYCHAIN_FIX.md`, `docs/QUOTIO_ANALYSIS.md`, `docs/TODO.md`, `docs/UPSTREAM_STRATEGY.md` — 포크 운영 문서, 일단 유지 (Task 5 에서 정리 결정)

삭제:
```bash
cd /Users/madup/Developer/CodexBar
for doc in abacus.md alibaba-coding-plan.md amp.md antigravity.md augment.md \
           bedrock.md codebuff.md command-code.md copilot.md crof.md \
           cursor.md deepgram.md deepseek.md doubao.md elevenlabs.md \
           factory.md gemini.md grok.md jetbrains.md kilo.md kimi-k2.md \
           kimi.md kiro.md manus.md mimo.md minimax.md moonshot.md \
           ollama.md opencode.md openai.md openrouter.md perplexity.md \
           stepfun.md venice.md vertexai.md warp.md windsurf.md zai.md \
           provider.md cli-configuration.md cli.md; do
  rm -f "docs/$doc"
done
ls docs | sort | head -40
```

> `docs/claude-comparison-since-0.18.0beta2.md` 는 Claude 관련이지만 upstream 버전 비교 문서임. 유지하되 Task 5 에서 단순화 결정.
> `docs/icon.md`, `docs/icon.png`, `docs/keychain-allow.png` 등 이미지 / 보조 문서는 유지 (앱 아이콘 변경은 별도 작업).

- [ ] **Step 6: Makefile / 릴리스 스크립트 정리**

```bash
cat Makefile
```

내용에서 release / appcast / notarize 관련 타겟 제거. CLI 빌드 타겟이 있다면 제거. `check`, `build`, `test` 만 남기는 방향.

릴리스 스크립트 제거:
```bash
rm -f Scripts/sign-and-notarize.sh Scripts/make_appcast.sh
ls Scripts | sort
```

- [ ] **Step 7: 잔존 참조 grep 으로 마지막 확인**

```bash
grep -rnE "import Sparkle|SPUUpdater|SUUpdater|ENABLE_SPARKLE|CodexBarCLI|CodexBarWidget" \
     Sources Package.swift Makefile 2>/dev/null | head -20
```

Expected: 출력 없음 (또는 주석 only). 출력이 있으면 해당 위치 수정.

```bash
grep -rnE "(?i)(appcast|sparkle|updateChannel)" Sources 2>/dev/null | head -20
```

Expected: 사실상 출력 없음.

- [ ] **Step 8: TestsLinux 처리 결정 + (선택) 삭제**

```bash
ls TestsLinux 2>/dev/null
```

존재한다면, Linux CI 를 안 쓰는 포크이므로 함께 정리:
```bash
rm -rf TestsLinux
```

그리고 `Package.swift` 의 `CodexBarLinuxTests` target 자체를 제거.

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -10
```

Expected: 빌드 + 테스트 통과.

- [ ] **Step 9: `.github/` 워크플로 검토**

```bash
ls .github 2>/dev/null
ls .github/workflows 2>/dev/null
```

`.github/workflows/*.yml` 가 있다면 release / notarize / appcast 관련 jobs 가 들어있을 가능성. CI 도 사용하지 않는 포크이므로 폴더 전체 삭제:
```bash
rm -rf .github
```

(만약 `ISSUE_TEMPLATE` 같은 유용한 자산이 있으면 선택적으로 유지 — 한 번 ls 로 확인 후 결정.)

- [ ] **Step 10: 최종 빌드 + 테스트 + 커밋**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -10
git status | head -40
git add -A
git commit -m "$(cat <<'EOF'
chore: drop CLI/Widget targets and upstream distribution assets

- Remove Sources/CodexBarCLI and Sources/CodexBarWidget targets.
- Strip Sparkle integration (dependency, ENABLE_SPARKLE, Updater code).
- Delete appcast.xml, CHANGELOG.md, docs/index.html, docs/CNAME, logos,
  solutions, screenshots, and per-provider docs for removed providers.
- Drop release/notarize scripts, Makefile release targets, .github CI.
- Remove TestsLinux target/folder if present.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git log --oneline -5
```

---

## Task 5: 문서 마무리 + 최종 검증

**목표:** README/AGENTS 를 포크 컨텍스트에 맞게 다시 쓴다. 잔존 문서 정리. 릴리스 빌드 + 테스트 최종 통과. 사용자가 `Scripts/compile_and_run.sh` 로 메뉴바 동작 1회 확인.

**Files:**
- Modify:
  - `README.md`
  - `AGENTS.md`
- Review/Delete (내용 보고 결정):
  - `docs/architecture.md`
  - `docs/configuration.md`
  - `docs/claude-comparison-since-0.18.0beta2.md`
  - `docs/FORK_QUICK_START.md`, `FORK_ROADMAP.md`, `FORK_SETUP.md`, `UPSTREAM_STRATEGY.md`, `ISSUE_LABELING.md`, `QUOTIO_ANALYSIS.md`, `TODO.md`
  - `docs/DEVELOPMENT.md`, `DEVELOPMENT_SETUP.md`, `RELEASING.md`, `KEYCHAIN_FIX.md`

- [ ] **Step 1: README.md 재작성 (포크용 최소판)**

`README.md` 전체를 아래 내용으로 교체:

```markdown
# CodexBar (Claude + Codex slim fork)

> A pared-down fork of [steipete/CodexBar](https://github.com/steipete/CodexBar) that tracks **only Claude and Codex** usage in the macOS menu bar.

## Requirements
- macOS 14+ (Sonoma)
- Swift 6 toolchain (Xcode 16+)

## Build & Run
```bash
swift build -c release
./Scripts/compile_and_run.sh   # builds, packages, relaunches CodexBar.app
```

## Configuration
- First launch → menu bar icon appears.
- Open **Preferences → Providers** and sign in to Claude and/or Codex via the source path of your choice (OAuth, CLI, browser cookies).
- See [`docs/claude.md`](docs/claude.md) and [`docs/codex.md`](docs/codex.md) for provider-specific details.

## Development
- `swift build` / `swift test` for incremental work.
- `./Scripts/compile_and_run.sh` to validate the full app bundle.
- See [`AGENTS.md`](AGENTS.md) for repo conventions.

## License
MIT — see [LICENSE](LICENSE). Upstream copyright retained.
```

> 백틱 escape 주의: 이 plan 안에서는 보존됐지만, 실제 작성 시 백틱 펜스가 그대로 나오도록 한다.

- [ ] **Step 2: AGENTS.md 갱신**

`AGENTS.md` 의 다음 부분을 포크 컨텍스트에 맞게 손본다:
- "Sources/CodexBar" 모듈 설명에 "Claude+Codex 전용 슬림 포크" 명시
- Release flow 부분 (`sign-and-notarize.sh`, `make_appcast.sh`) 제거 — Task 4 에서 스크립트 삭제됨
- "Run `./Scripts/compile_and_run.sh`" 안내 유지 (스크립트 자체는 유지)
- `pkill+open` 안내의 절대 경로 `/Users/steipete/Projects/codexbar` → 일반화 (`$(pwd)`) 또는 제거
- CLI/Widget 관련 안내 제거

수정 후 한 번 읽어보고 잔존 upstream 참조 정리.

- [ ] **Step 3: 잔존 문서 검토**

각 문서를 한 번씩 열어 다음 결정:

```bash
for f in docs/architecture.md docs/configuration.md \
         docs/claude-comparison-since-0.18.0beta2.md \
         docs/FORK_QUICK_START.md docs/FORK_ROADMAP.md docs/FORK_SETUP.md \
         docs/UPSTREAM_STRATEGY.md docs/ISSUE_LABELING.md \
         docs/QUOTIO_ANALYSIS.md docs/TODO.md docs/DEVELOPMENT.md \
         docs/DEVELOPMENT_SETUP.md docs/RELEASING.md docs/KEYCHAIN_FIX.md; do
  echo "=== $f ==="
  head -10 "$f" 2>/dev/null
done
```

기준:
- 포크 사용에 도움이 되면 **유지** (`KEYCHAIN_FIX.md`, `DEVELOPMENT.md` 등)
- 원본 릴리스/유지보수 문서면 **삭제** (`RELEASING.md`, `FORK_ROADMAP.md`, `UPSTREAM_STRATEGY.md`, `ISSUE_LABELING.md`, `QUOTIO_ANALYSIS.md`, `TODO.md`)
- 멀티-provider 가정 문서면 **삭제** (`configuration.md` 가 다른 provider 설정도 다룬다면)
- `architecture.md` — Claude/Codex 만 다루도록 **단순화** 또는 삭제

결정 후 실제 삭제:
```bash
# 예시 (실제 명령은 위 검토 결과 기반)
rm -f docs/RELEASING.md docs/FORK_ROADMAP.md docs/UPSTREAM_STRATEGY.md \
      docs/ISSUE_LABELING.md docs/QUOTIO_ANALYSIS.md docs/TODO.md \
      docs/FORK_QUICK_START.md docs/FORK_SETUP.md
```

- [ ] **Step 4: 최종 릴리스 빌드 + 테스트**

```bash
swift build -c release 2>&1 | tail -5
swift test 2>&1 | tail -10
```

Expected: 둘 다 통과. 실패 시 메시지에 따라 수정 후 재시도.

- [ ] **Step 5: 사용자에게 메뉴바 동작 확인 요청 (수동 검증 게이트)**

> 이 step 은 **사용자가 직접 수행**하는 검증이다. 에이전트는 진행하지 말고 사용자에게 안내만 한다.

안내 메시지:
```
Task 5 자동 작업이 끝났습니다. 마지막 수동 검증을 부탁드립니다.

1. ./Scripts/compile_and_run.sh 를 실행 (이미 실행 중인 CodexBar.app 을 종료하고 새로 띄움).
2. 메뉴바 아이콘 클릭 → 다음 항목 확인:
   (a) Claude 카드가 정상 표시되는가? (OAuth/CLI/web 어느 경로든 사용량/리셋 시간이 보이는가)
   (b) Codex 카드가 정상 표시되는가? (CLI dashboard 또는 OAuth 경로)
   (c) Preferences → Providers 에 Claude / Codex 두 항목만 보이는가?
   (d) 메뉴/Preferences 어디에도 다른 provider 이름이 등장하지 않는가?
3. 모두 OK 면 "확인 완료" 라고 알려주세요. 문제 있으면 어떤 메뉴/어떤 화면에서 발견했는지 알려주세요.
```

문제가 있으면 해당 위치를 디버깅해서 잔존 참조를 추가 정리. 그 후 다시 Step 4.

- [ ] **Step 6: 커밋**

```bash
git status | head -30
git add -A
git commit -m "$(cat <<'EOF'
docs: rewrite README/AGENTS for slim Claude+Codex fork

- Replace README with minimal fork-specific build/run instructions.
- Update AGENTS.md to reflect removed CLI/Widget/Sparkle and
  Claude+Codex-only scope.
- Prune fork/upstream maintenance docs that no longer apply.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git log --oneline -6
```

- [ ] **Step 7: 최종 상태 확인**

```bash
git log --oneline c822d88f..HEAD
ls Sources/
ls Sources/CodexBarCore/Providers/
swift build -c release 2>&1 | tail -3
```

Expected:
- 5 개 커밋 (Task 1~5 에 해당) 이 spec 커밋 위에 쌓여있음.
- `Sources/` 에 `CodexBar`, `CodexBarClaudeWatchdog`, `CodexBarClaudeWebProbe`, `CodexBarCore`, `CodexBarMacroSupport`, `CodexBarMacros` 만 존재.
- `Sources/CodexBarCore/Providers/` 에 `Claude/`, `Codex/`, 공통 인프라 12 `.swift` 파일만 존재.
- 릴리스 빌드 통과.

---

## 자체 검증 체크 (작성 후 셀프 리뷰)

### Spec 커버리지
- [x] §4-1 Provider 코드 삭제 → Task 1
- [x] §4-1 앱 본체 산재 파일 → Task 2 Step 1
- [x] §4-1 보조 타겟 (CLI/Widget) → Task 4 Step 1
- [x] §4-1 배포·홍보 자산 → Task 4 Step 4~6
- [x] §4-2 UI/설정 수정 → Task 3
- [x] §4-2 패키지/빌드 설정 → Task 4 Step 2
- [x] §4-2 문서 (README/AGENTS) → Task 5 Step 1~3
- [x] §4-3 유지 항목 — 변경 없음 (Task 1/2 에서 손대지 않음으로써 자동 충족)
- [x] §5 단계별 작업 계획 — Task 1~5 = Step 그룹
- [x] §6 검증 전략 — 매 Task 끝 `swift build` (`+ swift test` 는 Task 3/5), Task 5 Step 5 수동 게이트
- [x] §7 R1~R6 위험 대응 — R1 (OpenAIWeb 유지), R2 (Task 2 Step 6 루프), R3 (Task 3 Step 6), R4 (Task 4 Step 3+7 Sparkle grep), R5 (Task 4 Step 8 TestsLinux), R6 (Task 5 Step 4 명시)
- [x] §8 미해결 항목 — Task 4 Step 5/8/9 + Task 5 Step 3 에서 처리

### Placeholder / 모호함 점검
- "TBD" / "implement later" / "add appropriate error handling" 같은 키워드 없음 ✅
- "Similar to Task N" 처럼 다른 Task 를 참조한 step 없음 ✅
- 모든 삭제 / grep / 빌드 명령이 실제로 실행 가능한 형태 ✅
- Localization / Config 정리는 "파일을 열고 본 후 결정" 가이드를 명시 — 코드 제거 작업 특성상 구체적 줄 번호는 사전에 확정 불가하나, 매 Task 마다 빌드 에러를 가이드로 사용하는 방식이 명확히 명시됨 ✅

### 타입 일관성
- Task 2 에서 `Provider` enum 을 두 case 로 축소 → Task 3 에서 `Provider.allCases` 가 자동으로 두 개만 표현 (Step 1 에 명시) ✅
- Task 4 에서 Sparkle 제거 → 같은 Task Step 3 에서 `import Sparkle` / `SPUUpdater` / `SUUpdater` 모두 grep 명시 ✅
