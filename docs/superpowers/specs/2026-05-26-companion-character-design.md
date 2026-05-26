# Companion Character — Design

**Date**: 2026-05-26
**Status**: Design (awaiting implementation plan)
**Target version**: 1.3.0 (MINOR — 새 기능 토글 추가)

## 1. 개요

ClCoBar(CodexBar)에 **메뉴바 독립 캐릭터 슬롯**을 추가한다. Claude(또는 Codex) burn rate에 따라 움직이는 RunCat-style 캐릭터로, 토큰 소비 속도를 시각적 활력으로 표현한다.

### 한 줄 정의

기존 Claude/Codex pill은 그대로 두고, **새 NSStatusItem(캐릭터 슬롯)** 을 추가한다. 캐릭터는 burn rate에 매핑된 5단계 속도로 움직인다.

### 영감

- [RunCat](https://kyome.io/runcat/index.html?lang=ko) — CPU/RAM 사용량에 따라 메뉴바 고양이가 다른 속도로 달리는 macOS 앱.

## 2. MVP 범위

### 포함

- **새 디스플레이 토글**: 환경설정 → 표시 탭에 "캐릭터" 섹션 추가. 토글 ON 시 메뉴바에 별도 NSStatusItem 생성.
- **4종 캐릭터 팩 내장** (외부 리소스 없음, 코드 인코딩):
  - 고양이 — 픽셀 (기본값)
  - 고양이 — 라인 (미니멀)
  - 강아지 — 픽셀
  - 강아지 — 라인 (미니멀)
- **5단계 속도 구간**: idle / slow / normal / fast / burst — animation duration만 단계별로 변경.
- **Idle 동작**: 다리·꼬리 정지, body 0.05Hz 호흡 사이클.
- **데이터 소스**: 기존 `PlanUtilizationHistoryStore` weekly series — `Δ usedPercent / Δt` (%/min).
- **캐릭터 클릭**: 기존 ClCoBar 통합 메뉴(Claude 카드 + Codex 카드 + Overview) 그대로 띄움.
- **환경설정 옵션**:
  - 캐릭터 표시 ON/OFF
  - 캐릭터 종류 선택 (4종)
  - 대상 프로바이더 (Claude/Codex, 기본 Claude)
  - 미리보기 (5초 cycle로 모든 stage 시연)

### 제외 (Out of scope)

- 사용자 정의 캐릭터 import (RunCat 스타일 폴더)
- 알림/경고 (기존 `SessionQuotaNotifications` 영역; CLAUDE.md "제거된 기능 부활 금지"인 `quotaWarningNotificationsEnabled`도 부활 안 함)
- Claude CLI 로그 file watcher
- 캐릭터 클릭으로 별도 미니 팝오버 (기존 메뉴 공유)
- 키보드 단축키 (1차에는 없음)

### 성공 기준

1. 캐릭터 ON 상태에서 Claude 사용 중에는 캐릭터가 빠르게, 휴식 중에는 멈춤.
2. 5단계 구간 전환이 시각적으로 분명히 구별됨.
3. 다크/라이트 모드 모두 자연스럽게 보임 (`NSImage.isTemplate = true`).
4. 기존 Anthropic OAuth rate limit/backoff 동작에 영향 없음.
5. 캐릭터 OFF 상태에서는 기존 ClCoBar 동작이 그대로 유지됨.
6. 캐릭터 status item을 사용자가 ⌘드래그로 위치 이동 가능 (macOS 기본 동작).

## 3. 아키텍처

### 모듈 분리

```
CodexBarCore/Companion/            ← 순수 로직 (provider-independent)
  ├─ BurnRateCalculator.swift        시계열 → tokens/min (% per minute)
  ├─ CompanionPace.swift             burn rate → 5단계 분류 (순수 함수)
  ├─ CompanionPaceStage.swift        enum
  ├─ CompanionCharacter.swift        enum + style/species 메타
  ├─ CompanionStyle.swift            .pixel | .line
  └─ CompanionSpecies.swift          .cat | .dog

CodexBar/Companion/                ← UI/macOS 의존
  ├─ CompanionStatusItemController.swift   새 NSStatusItem 컨트롤러
  ├─ CompanionAnimationDriver.swift        DisplayLink wrap, frame phase
  ├─ CompanionIconRenderer.swift           NSImage 생성 + NSCache
  └─ CompanionSpriteAtlas.swift            4 캐릭터 × ~8 parts 정적 데이터

CodexBar/ (기존 파일에 추가/확장)
  ├─ SettingsStore+Companion.swift   설정 키 3개 (enabled/character/provider)
  ├─ PreferencesDisplayPane.swift    "캐릭터" 섹션 추가
  └─ CodexbarApp.swift               CompanionStatusItemController 라이프사이클
```

### 컴포넌트 관계도

```
                ┌──────────────────────────────────┐
                │  ClCoBar 앱 (CodexbarApp)         │
                └─────────────┬─────────────────────┘
                              │ owns
            ┌─────────────────┼──────────────────────┐
            ▼                 ▼                      ▼
   ┌───────────────┐  ┌──────────────────┐  ┌──────────────────┐
   │ StatusItem    │  │ Companion        │  │ SettingsStore    │
   │ Controller    │  │ StatusItem       │  │ +Companion       │
   │ (기존 pill)   │  │ Controller (NEW) │  │ (NEW keys)       │
   └───────┬───────┘  └────────┬─────────┘  └────────┬─────────┘
           │                   │                     │
           │                   ▼                     │
           │          ┌────────────────────┐         │
           │          │ Animation Driver   │◀────────┘ 관찰
           │          │ (DisplayLink, fps  │  (character/enabled/provider)
           │          │  per stage)        │
           │          └────────┬───────────┘
           │                   │ frame phase
           │                   ▼
           │          ┌────────────────────┐
           │          │ IconRenderer +     │
           │          │ SpriteAtlas        │
           │          │ (4 캐릭터 × 5단계) │
           │          └────────────────────┘
           │                   ▲
           │                   │ stage
           │          ┌────────┴───────────┐
           │          │ CompanionPace      │
           │          │ (burn rate → 단계) │
           │          └────────▲───────────┘
           │                   │ burn rate
           │          ┌────────┴───────────┐
           ▼          │ BurnRate           │
   ┌───────────────┐  │ Calculator (actor) │
   │ UsageStore    │◀─┤ Δ%/Δt 추정         │
   │ snapshots[]   │  └────────────────────┘
   └───────────────┘

  (캐릭터 status item 클릭 → 기존 StatusItemController의 메뉴 빌더 공유)
```

### 핵심 결정

1. **새 NSStatusItem은 독립 컨트롤러**로 — 기존 Claude/Codex pill 컨트롤러를 침범하지 않음.
2. **DisplayLink는 기존 `Sources/CodexBar/DisplayLink.swift` 재활용** — 새 driver는 fps만 stage별로 바꿔서 호출.
3. **Burn rate 시계열은 기존 PlanUtilizationHistoryStore 의존** — 별도 폴링 없음 → Anthropic 429 rate limit 영향 zero.
4. **CompanionPace는 순수 함수** — 입력(burn rate, prev stage, dt) → 출력(stage). `UsagePace`와 같은 레이어.
5. **메뉴 공유** — 캐릭터 status item 클릭 시 기존 `StatusItemController`의 menu builder 호출.
6. **스레딩**: `BurnRateCalculator`는 actor, 나머지 UI는 `@MainActor`.

### 기존 코드 영향 (변경 최소화)

- `UsageStore`, `IconRenderer`, `StatusItemController` 자체 코드는 **수정 없음**. observation만 추가.
- `CodexbarApp`에 `CompanionStatusItemController` 생성/소멸 코드만 추가.
- `PreferencesDisplayPane`에 새 섹션 1개 추가.
- `SettingsStore`에 setter/observer 추가 (CLAUDE.md의 copy-modify-reassign 패턴 준수).

## 4. 데이터 플로우 & Burn Rate 계산

### 시계열 소스

`Sources/CodexBar/PlanUtilizationHistoryStore.swift`의 weekly series 사용. entries는 시간 정렬:

```swift
struct PlanUtilizationHistoryEntry {
    let capturedAt: Date
    let usedPercent: Double
    let resetsAt: Date?
}
```

### Burn Rate 정의

단위: **% per minute** (Δ usedPercent / Δ minutes).

- 토큰 절대값 아닌 percent로 통일 → plan 한도와 무관하게 5단계 분류가 일관됨.
- 윈도우: 최근 **5분** (CodexBar 폴링 주기가 30~60s라 5분에 5~10 sample 확보).
- EMA 적용 (α=0.3) — chattering 완화.
- 음수 → 0 clamp (week reset 직후 보정).

```
window: 최근 5분
samples ≥ 2 → burn = (latest.usedPercent − oldest.usedPercent) / Δminutes
samples < 2 → burn = nil  (→ idle 처리)
burn < 0   → burn = 0    (리셋 직후)
final = EMA(prev, burn, α=0.3)
```

### 5단계 임계값 (1차 기본값)

기준선: weekly limit 168h 평균 페이스 ≈ 0.01%/min.

| Stage | Burn rate (%/min) | 의미 | Frame interval |
|---|---|---|---|
| **idle** | < 0.01 | 손 떼고 있음 | 정지 + body 20s 호흡 |
| **slow** | 0.01 ~ 0.1 | 가벼운 활동 | 1.2s/cycle |
| **normal** | 0.1 ~ 1.0 | 활발한 코딩 | 0.6s/cycle |
| **fast** | 1.0 ~ 5.0 | 무거운 작업 (큰 컨텍스트) | 0.3s/cycle |
| **burst** | > 5.0 | 극단적 소비 | 0.15s/cycle |

임계값은 **1차에서는 코드 상수**로 고정. 사용자 노출은 후속 작업.

### Stage 전환 안정화 (히스테리시스)

각 경계마다 ±20% 데드밴드 + stage 변경 후 최소 **3초간 유지** 룰.

```
현재 normal일 때
  → fast로 올라가려면 burn ≥ 1.0
  → slow로 내려가려면 burn < 0.08   (0.1 − 20%)

stage 변경 직후 3초 동안은 새 stage 유지 (rapid toggle 방지).
```

### 종단 데이터 플로우

```
[UsageStore] ──polling (30~60s)──▶ [Anthropic OAuth]
     │
     │ snapshots 변경
     ▼
[PlanUtilizationHistoryStore]
   ├─ entries[].usedPercent
   └─ entries[].capturedAt
     │
     │ observe (@Observable)
     ▼
[BurnRateCalculator] (actor)
   ├─ window = last 5min
   ├─ Δ% / Δt
   └─ EMA smoothing (α=0.3)
     │ burnRate: Double
     ▼
[CompanionPace.classify(burn, prev, dt)]
   └─ hysteresis + 3s 유지 룰
     │ stage: CompanionPaceStage
     ▼
[CompanionAnimationDriver]
   ├─ frameInterval = stage.frameInterval
   └─ DisplayLink tick에서 phase 진행
     │ (character, stage, phase)
     ▼
[CompanionIconRenderer + SpriteAtlas]
   └─ NSImage (template, 22×18, isTemplate=true)
     │
     ▼
[CompanionStatusItem.button.image]
```

### Edge Cases

| 상황 | 동작 |
|---|---|
| 시계열 entry < 2개 (앱 첫 실행) | stage = idle |
| Anthropic 429 backoff 중 | 마지막 stage 유지, EMA freeze |
| 사용량 리셋 (week boundary) | 음수 → 0 clamp → idle 진입 |
| 폴링 실패 5분 이상 | stage = idle |
| 멀티 계정 | 선택된 provider의 `preferredAccountKey` 시계열만 사용 |
| 캐릭터 OFF로 전환 | NSStatusItem 제거, DisplayLink 정지, calculator 정지 |
| 시스템 절전 / 화면 잠금 | DisplayLink 자동 일시정지 (macOS 기본 동작) |
| Settings 마이그레이션 (기존 1.x 사용자) | 새 키 default 사용 (`companionEnabled = false`) |

## 5. 컴포넌트 인터페이스

### CompanionPaceStage *(enum, CodexBarCore)*

```swift
public enum CompanionPaceStage: String, CaseIterable, Sendable {
    case idle, slow, normal, fast, burst

    public var frameInterval: TimeInterval {
        switch self {
        case .idle:   return 20.0
        case .slow:   return 1.2
        case .normal: return 0.6
        case .fast:   return 0.3
        case .burst:  return 0.15
        }
    }
}
```

### CompanionCharacter *(enum, CodexBarCore)*

```swift
public enum CompanionCharacter: String, CaseIterable, Sendable, Codable {
    case catPixel    // 기본
    case catLine
    case dogPixel
    case dogLine

    public var displayName: String { /* ko 로컬라이즈 */ }
    public var style: CompanionStyle { /* .pixel | .line */ }
    public var species: CompanionSpecies { /* .cat | .dog */ }
}
```

### BurnRateCalculator *(actor, CodexBarCore)*

```swift
public actor BurnRateCalculator {
    public init(window: TimeInterval = 300, smoothingAlpha: Double = 0.3)

    /// 새 시계열 entry가 들어왔을 때 호출. 즉시 burn rate 갱신.
    public func update(entries: [PlanUtilizationHistoryEntry], now: Date) -> Double

    /// 마지막 계산값. EMA smoothed.
    public func current() -> Double

    /// 폴링 실패/backoff 진입 시 호출. EMA freeze.
    public func freeze()

    public func resume()
}
```

### CompanionPace *(struct, CodexBarCore)*

```swift
public struct CompanionPace {
    public static func classify(
        burnRate: Double,
        previous: CompanionPaceStage?,
        timeSinceLastChange: TimeInterval
    ) -> CompanionPaceStage
}
```

순수 함수. 임계값과 히스테리시스, 3s 유지 룰은 내부 상수.

### CompanionSpriteAtlas *(struct, CodexBar 앱)*

```swift
struct CompanionSpriteAtlas {
    static func parts(for character: CompanionCharacter) -> [CompanionPart]
}

struct CompanionPart {
    let kind: PartKind            // body / leg(1..4) / tail / ear / whisker
    let drawCommand: DrawCommand  // pixel rects | line paths
    let animation: PartAnimation  // phase offset, transform fn
}
```

4 캐릭터 × ~8 parts = 32개 정적 데이터. 외부 리소스 없이 코드 인코딩.

### CompanionIconRenderer *(struct, CodexBar 앱)*

```swift
struct CompanionIconRenderer {
    static func render(
        character: CompanionCharacter,
        stage: CompanionPaceStage,
        phase: Double,            // 0.0 ... 1.0
        size: NSSize = .init(width: 22, height: 18)
    ) -> NSImage

    static func clearCache()
}
```

`NSImage.isTemplate = true` 설정. NSCache로 (character, stage, quantized phase) → NSImage 캐시.

### CompanionAnimationDriver *(class, @MainActor, CodexBar 앱)*

```swift
@MainActor
final class CompanionAnimationDriver {
    init(displayLink: DisplayLink)

    var stage: CompanionPaceStage { get set }
    var onFrame: ((Double) -> Void)?

    func start()
    func stop()
}
```

stage 변경 시 frameInterval 자동 변경. idle stage에서는 body 호흡만 매우 느리게.

### CompanionStatusItemController *(class, @MainActor, CodexBar 앱)*

```swift
@MainActor
final class CompanionStatusItemController {
    init(
        settings: SettingsStore,
        usageStore: UsageStore,
        sharedMenuProvider: () -> NSMenu
    )

    func start()
    func stop()
}
```

내부 보유: 자체 `NSStatusItem`, `BurnRateCalculator`, `CompanionAnimationDriver`, observation cancellables.

### SettingsStore+Companion *(확장, CodexBar 앱)*

```swift
extension SettingsStore {
    var companionEnabled: Bool { get set }
    var companionCharacter: CompanionCharacter { get set }
    var companionProvider: UsageProvider { get set }
}
```

CLAUDE.md의 copy-modify-reassign 패턴 준수:

```swift
var companionEnabled: Bool {
    get { defaultsState.companionEnabled }
    set {
        var state = defaultsState
        state.companionEnabled = newValue
        defaultsState = state
    }
}
```

UserDefaults 키: `companion.enabled`, `companion.character`, `companion.provider`.

## 6. UI/UX

### 환경설정 통합 위치

표시 탭의 **마지막 섹션**으로 추가 (별도 탭 만들지 않음).

```
┌─ 환경설정 → 표시 ───────────────────────────────┐
│ 메뉴바에 표시할 항목                            │
│  ☑ 아이콘                                       │
│  ☐ 퍼센트                                       │
│  ☑ 배터리                                       │
│  ☑ 시간          [정확 ▾]                      │
│                                                  │
│ ──────────────────────────────────────────────  │
│                                                  │
│ 캐릭터                                NEW       │
│  ☐ 메뉴바에 캐릭터 표시                         │
│                                                  │
│  캐릭터:  [▾ 고양이 (픽셀)            ]        │
│  대상:    ◉ Claude   ○ Codex                    │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │ [미리보기 — 5초 cycle로 모든 stage 시연] │  │
│  └──────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

### 캐릭터 status item 동작

| 동작 | 결과 |
|---|---|
| **좌클릭** | 기존 ClCoBar 통합 메뉴 (Claude 카드 + Codex 카드 + Overview) — `StatusItemController` 메뉴 빌더 재사용 |
| **우클릭** | 좌클릭과 동일 |
| **호버** | `NSStatusItem.button.toolTip`에 현재 stage·burn rate 표시. 예: `"Claude · normal · 0.32%/분"` |
| **메뉴 열림** | NSStatusItem highlighted state |
| **⌘드래그** | macOS 기본 동작 |
| **숨김(OFF)** | NSStatusItem 자체 release |

### 미리보기

환경설정의 캐릭터 섹션 내 미리보기 박스:
- 5초 cycle: idle → slow → normal → fast → burst → idle
- 캐릭터 종류 변경 시 즉시 교체
- 실제 burn rate가 아닌 demo cycle

### macOS Reduce Motion 대응

`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` 이 true:
- 캐릭터는 보이지만 stage = idle 고정 (body 호흡만)
- 환경설정 토글은 그대로 사용 가능

### 라이트/다크 모드

`NSImage.isTemplate = true` — macOS 자동 컬러링. 픽셀 캐릭터의 눈 같은 "구멍" 표현은 `NSCompositingOperation.destinationOut`로 처리.

### 첫 사용 UX

- 기본값 OFF — 기존 사용자의 메뉴바를 임의로 점유하지 않음.
- 표시 탭의 "캐릭터" 섹션 헤더에 **NEW 배지** — 사용자가 토글을 한 번 만지면 사라짐 (`companionFeatureSeen` 플래그).
- 첫 토글 ON 시 작은 토스트: `"🐱 캐릭터가 메뉴바에 추가되었습니다 (드래그로 위치 이동 가능)"`.

### 다국어

한국어 전용 (CLAUDE.md 규칙). `ko.lproj/Localizable.strings`에 추가:

```
"companion.section.title" = "캐릭터";
"companion.toggle.label" = "메뉴바에 캐릭터 표시";
"companion.character.label" = "캐릭터";
"companion.target.label" = "대상";
"companion.character.catPixel" = "고양이 (픽셀)";
"companion.character.catLine" = "고양이 (라인)";
"companion.character.dogPixel" = "강아지 (픽셀)";
"companion.character.dogLine" = "강아지 (라인)";
"companion.preview.label" = "미리보기";
"companion.new.badge" = "NEW";
"companion.first.toast" = "🐱 캐릭터가 메뉴바에 추가되었습니다";
"companion.tooltip.idle" = "%@ · 휴식 중";
"companion.tooltip.active" = "%@ · %@ · %.2f%%/분";
```

영어로 유지: `Claude`, `Codex`, `ClCoBar`.

### Accessibility

- `NSStatusItem.button.accessibilityLabel`을 stage 변경 시 갱신. 예: `"ClCoBar 캐릭터 - Claude burn rate normal"`.

## 7. 테스트 전략

`Tests/CodexBarTests/Companion/` 에 추가.

### 단위 테스트

```
✓ BurnRateCalculatorTests.swift
  - empty/single sample → nil (idle 처리)
  - 정상 ramp-up → 기대값
  - 음수 → 0 clamp
  - freeze/resume 동작
  - EMA 수렴 (다양한 α 값)

✓ CompanionPaceTests.swift   ← 가장 중요. 순수 함수.
  - 5단계 경계 분류 (정확한 임계값 진입)
  - 히스테리시스 (경계 ±20% 데드밴드)
  - 3s 유지 룰
  - previous=nil → 초기 분류

✓ CompanionSpriteAtlasTests.swift
  - 4 캐릭터 × 8 parts 모두 정의되어 있는지
  - 각 part의 keyframe phase가 [0, 1) 범위인지
```

### Snapshot 테스트 (선택)

`swift-snapshot-testing` 도입 여부는 implementation plan 단계에서 결정.

```
✓ CompanionIconRendererSnapshotTests.swift  (선택)
  - 4 캐릭터 × 5 stage × 4 phase = 80개 NSImage 스냅샷
  - 라이트/다크 둘 다 (template 검증)
```

### 수동 검증

- StatusItemController 라이프사이클 (start/stop/restart)
- Settings 토글 → 메뉴바 status item 즉시 추가/제거
- Provider 전환 → 시계열 소스 즉시 교체
- Reduce Motion 토글 → idle 고정
- ⌘드래그 위치 이동 → 재시작 후 위치 유지

CodexBar 기존 패턴(`swift test`로 실행, `SKIP_TEST=1`로 우회 가능)을 그대로 따름.

## 8. 구현 단계

7단계로 분리. 각 단계 끝나면 빌드 가능한 중간 상태.

### Phase 1. Core 모델 *(CodexBarCore)*

- `CompanionPaceStage` / `CompanionCharacter` / `CompanionStyle` / `CompanionSpecies`
- `BurnRateCalculator` (actor + 단위 테스트)
- `CompanionPace.classify` (순수 함수 + 단위 테스트)

### Phase 2. Sprite + Renderer *(CodexBar)*

- `CompanionSpriteAtlas`: 4 캐릭터 데이터 입력 (가장 시간 소요).
- `CompanionIconRenderer`: NSImage 생성 + 캐시.
- Renderer 단독 디버그 뷰로 4×5×N 매트릭스 확인.

Phase 2가 가장 큼. 캐릭터별로 sub-commit 권장 (2a: 고양이 픽셀, 2b: 고양이 라인, 2c: 강아지 픽셀, 2d: 강아지 라인).

### Phase 3. Animation Driver *(CodexBar)*

- DisplayLink 재활용 wire-up.
- stage별 frameInterval 적용.
- phase callback.

### Phase 4. StatusItem 통합 *(CodexBar)*

- `CompanionStatusItemController`.
- UsageStore observation → BurnRateCalculator → CompanionPace → driver.
- 클릭 시 기존 메뉴 공유.

### Phase 5. Settings + Preferences UI *(CodexBar)*

- `SettingsStore+Companion` (copy-modify-reassign 패턴).
- `PreferencesDisplayPane`에 "캐릭터" 섹션.
- 미리보기 뷰.

### Phase 6. 엣지케이스 마감

- Reduce Motion 대응.
- NEW 배지 + 첫 토글 토스트.
- 한국어 문자열 추가.
- Accessibility 라벨.

### Phase 7. 배포

- `version.env`: `MARKETING_VERSION 1.2.0 → 1.3.0` (MINOR), `BUILD_NUMBER +1`.
- `docs/install-guide-ko.md` 갱신 (zip 파일명 + 다음 버전 예시).
- `Scripts/install_for_team.sh` 주석 갱신.
- `./Scripts/build_for_distribution.sh` → `dist/ClCoBar-1.3.0-arm64.zip`.
- 본인 환경 재설치 검증.

## 9. 후속 작업 (Out of MVP)

- 캐릭터 팩 추가 (햄스터, 공룡, 거북이…).
- 사용자 정의 캐릭터 import (RunCat 스타일 폴더).
- 캐릭터 토글 키보드 단축키.
- 일별 burn rate 평균 차트 (Menu 안에).
- 캐릭터 클릭 시 "현재 활동량 상세" 미니 팝오버.
- 임계값 사용자 노출 (Advanced 탭).
- 알림 통합 (burn rate 급변 시).

## 10. 알려진 함정 / 주의사항

CLAUDE.md에서 강조한 함정들:

- **`@Observable` nested-struct setter 버그** — `SettingsStore.defaultsState.X = newValue` 직접 변형 금지. **반드시** copy-modify-reassign:
  ```swift
  var state = self.defaultsState
  state.X = newValue
  self.defaultsState = state
  ```
- **Anthropic OAuth 429** — Companion은 자체 폴링하지 않음으로 회피. `UsageStore`의 backoff 상태를 observation해서 freeze 모드 진입.
- **PreviewsMacros 툴체인** — 신규 SwiftUI `#Preview` 매크로 추가 시 `build_for_distribution.sh`의 패치 함수 확장 필요.
- **내부명 `CodexBar` 유지** — 새 파일 추가 시에도 module name은 `CodexBar`/`CodexBarCore`. UserDefaults suite, Keychain entry 변경 금지.
- **한국어 전용 UI** — 모든 새 UI 문자열은 `Localization.swift`에 등록.
- **제거된 기능 부활 금지** — `quotaWarningNotificationsEnabled`, `randomBlinkEnabled`, `statusChecksEnabled` 등.

## 11. References

- `Sources/CodexBar/PlanUtilizationHistoryStore.swift` — 시계열 데이터 소스.
- `Sources/CodexBar/UsageStore.swift` + `UsageStore+Refresh.swift` — 사용량 폴링.
- `Sources/CodexBar/DisplayLink.swift` — 재활용할 frame ticker.
- `Sources/CodexBar/StatusItemController.swift` + `+Menu.swift` — 메뉴 빌더 공유.
- `Sources/CodexBar/IconRenderer.swift` — 기존 아이콘 렌더링 패턴 참고.
- `Sources/CodexBarCore/UsagePace.swift` — `CompanionPace`의 패턴 참고.
- `Sources/CodexBar/PreferencesDisplayPane.swift` — UI 추가 위치.
- `Sources/CodexBar/SettingsStore.swift` + `+Defaults.swift` — 설정 키 추가 패턴.
- `CLAUDE.md` — 알려진 함정 / 빌드 규칙 / 버전 정책.
- `docs/superpowers/specs/2026-05-18-codexbar-slim-claude-codex-design.md` — 이전 spec 작성 패턴 참고.
- [RunCat](https://kyome.io/runcat/index.html?lang=ko) — 원본 영감.
