# Companion Character Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ClCoBar(CodexBar)에 메뉴바 독립 캐릭터 슬롯을 추가한다. Claude/Codex burn rate에 따라 5단계 속도로 움직이는 4종 캐릭터(고양이/강아지 × 픽셀/라인)를 내장하고, 환경설정 → 표시 탭에서 토글한다.

**Architecture:** 순수 로직(BurnRateCalculator, CompanionPace 등)은 `CodexBarCore/Companion/`, UI/macOS 의존(NSStatusItem, NSImage 렌더링)은 `CodexBar/Companion/`. 기존 `PlanUtilizationHistoryStore` 시계열만 구독해 추가 폴링 없음. 기존 `DisplayLinkDriver`와 `StatusItemController`의 메뉴 빌더를 재활용.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Swift Testing (`@Test`, `#expect`), `@Observable`, swift build/test toolchain (Xcode 없이도 빌드 가능 — `Scripts/build_for_distribution.sh`).

**Spec:** [`docs/superpowers/specs/2026-05-26-companion-character-design.md`](../specs/2026-05-26-companion-character-design.md)

---

## File Structure

### Files to Create

**`Sources/CodexBarCore/Companion/`** (provider-independent 로직):
- `CompanionPaceStage.swift` — enum (idle/slow/normal/fast/burst) + `frameInterval`
- `CompanionStyle.swift` — enum (.pixel | .line)
- `CompanionSpecies.swift` — enum (.cat | .dog)
- `CompanionCharacter.swift` — enum (catPixel/catLine/dogPixel/dogLine) + style/species
- `BurnRateCalculator.swift` — actor, Δ%/Δt + EMA + freeze
- `CompanionPace.swift` — `classify(burn, prev, dt) → Stage` 순수 함수

**`Sources/CodexBar/Companion/`** (UI/macOS):
- `CompanionStatusItemController.swift` — NSStatusItem 라이프사이클
- `CompanionAnimationDriver.swift` — DisplayLinkDriver wrap, phase 진행
- `CompanionIconRenderer.swift` — NSImage 생성 + NSCache
- `CompanionSpriteAtlas.swift` — 공용 data types (PartKind/DrawCommand/CompanionPart)
- `CompanionSpriteAtlas+CatPixel.swift` — 고양이 픽셀 parts 정의
- `CompanionSpriteAtlas+CatLine.swift` — 고양이 라인 parts 정의
- `CompanionSpriteAtlas+DogPixel.swift` — 강아지 픽셀 parts 정의
- `CompanionSpriteAtlas+DogLine.swift` — 강아지 라인 parts 정의
- `CompanionPreviewView.swift` — 환경설정용 5초 cycle 미리보기
- `SettingsStore+Companion.swift` — extension (3 properties + observers)

**Tests** (`Tests/CodexBarTests/Companion/`):
- `CompanionPaceStageTests.swift` — frameInterval 매핑 검증
- `BurnRateCalculatorTests.swift` — Δ%/Δt + EMA + freeze
- `CompanionPaceTests.swift` — classify + hysteresis + 3s hold
- `CompanionSpriteAtlasTests.swift` — 4 character × ~8 parts 정합성
- `SettingsStoreCompanionTests.swift` — defaults/setter

### Files to Modify

- `Sources/CodexBar/SettingsStoreState.swift` — `companionEnabled`, `companionCharacterRaw`, `companionProviderRaw`, `companionFeatureSeen` 4개 필드 추가
- `Sources/CodexBar/SettingsStore.swift` — init에서 새 키 4개 로드
- `Sources/CodexBar/PreferencesDisplayPane.swift` — "캐릭터" SettingsSection 추가
- `Sources/CodexBar/CodexbarApp.swift` (또는 AppDelegate) — `CompanionStatusItemController` 인스턴스 라이프사이클
- `Sources/CodexBar/Resources/ko.lproj/Localizable.strings` — 14 entries 추가
- `Sources/CodexBar/Resources/en.lproj/Localizable.strings` — 동일 키 (영어 폴백)
- `version.env` — `1.2.2 → 1.3.0`, `BUILD_NUMBER 70 → 71`
- `docs/install-guide-ko.md` — zip 파일명 + "다음 버전 예시" 한 칸 위로
- `Scripts/install_for_team.sh` — 주석의 사용 예시

---

## Implementation Order Rationale

Phase 1 (Core) → Phase 2 (Sprite/Renderer) → Phase 3 (Driver) → Phase 4 (StatusItem) → Phase 5 (Settings/UI) → Phase 6 (엣지케이스) → Phase 7 (배포).

각 Task는 빌드 가능한 중간 상태로 끝남. 커밋 단위가 작아 review·rollback 쉬움.

---

## Task 1: Core enums (PaceStage, Style, Species, Character)

CompanionPaceStage(idle/slow/normal/fast/burst)와 보조 enum 3개를 한 번에 추가한다. 모두 작고 의존성이 없어 묶어도 review 부담 없음.

**Files:**
- Create: `Sources/CodexBarCore/Companion/CompanionPaceStage.swift`
- Create: `Sources/CodexBarCore/Companion/CompanionStyle.swift`
- Create: `Sources/CodexBarCore/Companion/CompanionSpecies.swift`
- Create: `Sources/CodexBarCore/Companion/CompanionCharacter.swift`
- Test: `Tests/CodexBarTests/Companion/CompanionPaceStageTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/Companion/CompanionPaceStageTests.swift
import CodexBarCore
import Testing

struct CompanionPaceStageTests {
    @Test
    func `frameInterval is monotonically decreasing from idle to burst`() {
        let stages: [CompanionPaceStage] = [.idle, .slow, .normal, .fast, .burst]
        let intervals = stages.map(\.frameInterval)
        for pair in zip(intervals, intervals.dropFirst()) {
            #expect(pair.0 > pair.1)
        }
    }

    @Test
    func `idle frameInterval is at least 10 seconds (slow breathing)`() {
        #expect(CompanionPaceStage.idle.frameInterval >= 10)
    }

    @Test
    func `burst frameInterval is at most 200ms`() {
        #expect(CompanionPaceStage.burst.frameInterval <= 0.2)
    }

    @Test
    func `character maps to species and style consistently`() {
        #expect(CompanionCharacter.catPixel.species == .cat)
        #expect(CompanionCharacter.catPixel.style == .pixel)
        #expect(CompanionCharacter.dogLine.species == .dog)
        #expect(CompanionCharacter.dogLine.style == .line)
    }

    @Test
    func `CompanionCharacter has exactly 4 cases`() {
        #expect(CompanionCharacter.allCases.count == 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionPaceStageTests`
Expected: FAIL with "no such module" or "no such type".

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/CodexBarCore/Companion/CompanionPaceStage.swift
import Foundation

public enum CompanionPaceStage: String, CaseIterable, Sendable, Codable {
    case idle
    case slow
    case normal
    case fast
    case burst

    /// Animation duration per cycle. Smaller = faster.
    public var frameInterval: TimeInterval {
        switch self {
        case .idle:   return 20.0   // body breathing only
        case .slow:   return 1.2
        case .normal: return 0.6
        case .fast:   return 0.3
        case .burst:  return 0.15
        }
    }
}
```

```swift
// Sources/CodexBarCore/Companion/CompanionStyle.swift
import Foundation

public enum CompanionStyle: String, Sendable, Codable, CaseIterable {
    case pixel
    case line
}
```

```swift
// Sources/CodexBarCore/Companion/CompanionSpecies.swift
import Foundation

public enum CompanionSpecies: String, Sendable, Codable, CaseIterable {
    case cat
    case dog
}
```

```swift
// Sources/CodexBarCore/Companion/CompanionCharacter.swift
import Foundation

public enum CompanionCharacter: String, CaseIterable, Sendable, Codable {
    case catPixel
    case catLine
    case dogPixel
    case dogLine

    public static let `default`: CompanionCharacter = .catPixel

    public var species: CompanionSpecies {
        switch self {
        case .catPixel, .catLine: return .cat
        case .dogPixel, .dogLine: return .dog
        }
    }

    public var style: CompanionStyle {
        switch self {
        case .catPixel, .dogPixel: return .pixel
        case .catLine, .dogLine:   return .line
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionPaceStageTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Companion/CompanionPaceStage.swift \
        Sources/CodexBarCore/Companion/CompanionStyle.swift \
        Sources/CodexBarCore/Companion/CompanionSpecies.swift \
        Sources/CodexBarCore/Companion/CompanionCharacter.swift \
        Tests/CodexBarTests/Companion/CompanionPaceStageTests.swift
git commit -m "feat(companion): core enums (PaceStage, Style, Species, Character)"
```

---

## Task 2: BurnRateCalculator

시계열 → %/min 변환 actor. EMA 적용 + freeze/resume. 음수 clamp.

**Files:**
- Create: `Sources/CodexBarCore/Companion/BurnRateCalculator.swift`
- Test: `Tests/CodexBarTests/Companion/BurnRateCalculatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/Companion/BurnRateCalculatorTests.swift
import CodexBarCore
import Testing
import Foundation

@Suite
struct BurnRateCalculatorTests {
    private func entry(_ minutesAgo: Double, percent: Double, now: Date = .init()) -> PlanUtilizationHistoryEntry {
        PlanUtilizationHistoryEntry(
            capturedAt: now.addingTimeInterval(-minutesAgo * 60),
            usedPercent: percent,
            resetsAt: nil)
    }

    @Test
    func `returns zero when fewer than 2 samples`() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 1.0)
        let now = Date()
        let burn = await calc.update(entries: [entry(0, percent: 10, now: now)], now: now)
        #expect(burn == 0)
    }

    @Test
    func `computes positive burn for usage increase`() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 1.0)
        let now = Date()
        let entries = [entry(5, percent: 10, now: now), entry(0, percent: 12, now: now)]
        let burn = await calc.update(entries: entries, now: now)
        // 2% over 5 min = 0.4 %/min
        #expect(abs(burn - 0.4) < 0.001)
    }

    @Test
    func `clamps negative burn to zero (post-reset)`() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 1.0)
        let now = Date()
        let entries = [entry(5, percent: 80, now: now), entry(0, percent: 5, now: now)]
        let burn = await calc.update(entries: entries, now: now)
        #expect(burn == 0)
    }

    @Test
    func `respects window (ignores samples older than window)`() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 1.0)
        let now = Date()
        let entries = [
            entry(20, percent: 0, now: now),   // outside 5-min window
            entry(5, percent: 10, now: now),
            entry(0, percent: 12, now: now),
        ]
        let burn = await calc.update(entries: entries, now: now)
        // Same as the 2-sample case
        #expect(abs(burn - 0.4) < 0.001)
    }

    @Test
    func `EMA smooths burn rate over successive updates`() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 0.3)
        var now = Date()
        var entries = [entry(5, percent: 10, now: now), entry(0, percent: 12, now: now)]
        let b1 = await calc.update(entries: entries, now: now)
        // First update: EMA seed = raw
        #expect(abs(b1 - 0.4) < 0.001)

        // Spike upward
        now = now.addingTimeInterval(60)
        entries = [entry(5, percent: 10, now: now), entry(0, percent: 20, now: now)]
        let b2 = await calc.update(entries: entries, now: now)
        // raw = 2.0, EMA(α=0.3) = 0.4 + 0.3*(2.0 - 0.4) = 0.88
        #expect(abs(b2 - 0.88) < 0.01)
    }

    @Test
    func `freeze preserves last value across update`() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 1.0)
        let now = Date()
        let entries = [entry(5, percent: 10, now: now), entry(0, percent: 12, now: now)]
        _ = await calc.update(entries: entries, now: now)
        await calc.freeze()
        let frozen = await calc.update(
            entries: [entry(5, percent: 10, now: now), entry(0, percent: 50, now: now)],
            now: now)
        #expect(abs(frozen - 0.4) < 0.001)  // unchanged
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BurnRateCalculatorTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/CodexBarCore/Companion/BurnRateCalculator.swift
import Foundation

public actor BurnRateCalculator {
    private let window: TimeInterval
    private let alpha: Double
    private var smoothed: Double = 0
    private var hasSeed: Bool = false
    private var frozen: Bool = false

    public init(window: TimeInterval = 300, smoothingAlpha: Double = 0.3) {
        self.window = window
        self.alpha = smoothingAlpha
    }

    /// Computes burn rate (%/min) from time-series entries and applies EMA.
    @discardableResult
    public func update(entries: [PlanUtilizationHistoryEntry], now: Date) -> Double {
        if self.frozen { return self.smoothed }

        let cutoff = now.addingTimeInterval(-self.window)
        let inWindow = entries
            .filter { $0.capturedAt >= cutoff }
            .sorted { $0.capturedAt < $1.capturedAt }

        guard inWindow.count >= 2, let first = inWindow.first, let last = inWindow.last else {
            self.smoothed = 0
            self.hasSeed = true
            return 0
        }

        let dtMinutes = last.capturedAt.timeIntervalSince(first.capturedAt) / 60.0
        guard dtMinutes > 0 else {
            return self.smoothed
        }

        let rawDelta = last.usedPercent - first.usedPercent
        let raw = max(0, rawDelta / dtMinutes)

        if self.hasSeed {
            self.smoothed = self.smoothed + self.alpha * (raw - self.smoothed)
        } else {
            self.smoothed = raw
            self.hasSeed = true
        }
        return self.smoothed
    }

    public func current() -> Double { self.smoothed }

    public func freeze() { self.frozen = true }
    public func resume() { self.frozen = false }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BurnRateCalculatorTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Companion/BurnRateCalculator.swift \
        Tests/CodexBarTests/Companion/BurnRateCalculatorTests.swift
git commit -m "feat(companion): BurnRateCalculator actor (Δ%/Δt + EMA + freeze)"
```

---

## Task 3: CompanionPace.classify (thresholds + hysteresis + 3s hold)

순수 함수. 5단계 임계값(0.01/0.1/1.0/5.0 %/min), ±20% 데드밴드, 3초 유지 룰.

**Files:**
- Create: `Sources/CodexBarCore/Companion/CompanionPace.swift`
- Test: `Tests/CodexBarTests/Companion/CompanionPaceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/Companion/CompanionPaceTests.swift
import CodexBarCore
import Testing

struct CompanionPaceTests {
    @Test
    func `classifies idle at 0`() {
        let s = CompanionPace.classify(burnRate: 0, previous: nil, timeSinceLastChange: 999)
        #expect(s == .idle)
    }

    @Test
    func `classifies burst above 5`() {
        let s = CompanionPace.classify(burnRate: 6.0, previous: nil, timeSinceLastChange: 999)
        #expect(s == .burst)
    }

    @Test
    func `classifies each band at midpoint`() {
        // idle (<0.01), slow (0.01~0.1), normal (0.1~1.0), fast (1.0~5.0), burst (>5)
        #expect(CompanionPace.classify(burnRate: 0.005, previous: nil, timeSinceLastChange: 999) == .idle)
        #expect(CompanionPace.classify(burnRate: 0.05,  previous: nil, timeSinceLastChange: 999) == .slow)
        #expect(CompanionPace.classify(burnRate: 0.5,   previous: nil, timeSinceLastChange: 999) == .normal)
        #expect(CompanionPace.classify(burnRate: 2.5,   previous: nil, timeSinceLastChange: 999) == .fast)
        #expect(CompanionPace.classify(burnRate: 8.0,   previous: nil, timeSinceLastChange: 999) == .burst)
    }

    @Test
    func `hysteresis keeps current stage in deadband`() {
        // burn = 0.09 is just below the normal-to-slow upper threshold (0.1)
        // but inside the ±20% deadband (slow upper = 0.1, deadband 0.08~0.12)
        let s = CompanionPace.classify(burnRate: 0.09, previous: .normal, timeSinceLastChange: 999)
        #expect(s == .normal)   // stays in normal due to deadband
    }

    @Test
    func `hysteresis allows transition past deadband`() {
        // burn = 0.05 — well below 0.08, so drop to slow
        let s = CompanionPace.classify(burnRate: 0.05, previous: .normal, timeSinceLastChange: 999)
        #expect(s == .slow)
    }

    @Test
    func `3s hold rule prevents rapid toggling`() {
        // Just transitioned to normal 2s ago, burn now suggests slow
        let s = CompanionPace.classify(burnRate: 0.001, previous: .normal, timeSinceLastChange: 2)
        #expect(s == .normal)  // hold
    }

    @Test
    func `3s hold rule releases after 3s`() {
        let s = CompanionPace.classify(burnRate: 0.001, previous: .normal, timeSinceLastChange: 4)
        #expect(s == .idle)
    }

    @Test
    func `previous nil treats as initial classification`() {
        let s = CompanionPace.classify(burnRate: 0.5, previous: nil, timeSinceLastChange: 0)
        #expect(s == .normal)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionPaceTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/CodexBarCore/Companion/CompanionPace.swift
import Foundation

public enum CompanionPace {
    /// Upper threshold for each stage (inclusive at lower bound).
    /// idle:  [0, 0.01)
    /// slow:  [0.01, 0.1)
    /// normal: [0.1, 1.0)
    /// fast:  [1.0, 5.0)
    /// burst: [5.0, ∞)
    private static let thresholds: [(stage: CompanionPaceStage, upper: Double)] = [
        (.idle, 0.01),
        (.slow, 0.1),
        (.normal, 1.0),
        (.fast, 5.0),
        (.burst, .infinity),
    ]

    /// ±20% deadband and 3-second hold after transition.
    private static let deadbandFactor: Double = 0.2
    private static let minHoldSeconds: TimeInterval = 3.0

    public static func classify(
        burnRate: Double,
        previous: CompanionPaceStage?,
        timeSinceLastChange: TimeInterval
    ) -> CompanionPaceStage {
        let raw = self.rawStage(for: burnRate)

        guard let previous else { return raw }

        // 3s hold: too soon to change away from previous
        if raw != previous, timeSinceLastChange < self.minHoldSeconds {
            return previous
        }

        // Hysteresis: if raw is adjacent to previous, check deadband
        if abs(self.indexOf(raw) - self.indexOf(previous)) == 1 {
            let prevUpper = self.upperThreshold(for: previous)
            let prevLower = self.lowerThreshold(for: previous)
            // Going up: must exceed upper + 20% deadband
            // Going down: must drop below lower − 20% deadband
            if self.indexOf(raw) > self.indexOf(previous) {
                if burnRate < prevUpper * (1 + self.deadbandFactor) {
                    return previous
                }
            } else {
                if burnRate >= prevLower * (1 - self.deadbandFactor) {
                    return previous
                }
            }
        }

        return raw
    }

    private static func rawStage(for burn: Double) -> CompanionPaceStage {
        for (stage, upper) in self.thresholds where burn < upper { return stage }
        return .burst
    }

    private static func indexOf(_ stage: CompanionPaceStage) -> Int {
        switch stage {
        case .idle: return 0
        case .slow: return 1
        case .normal: return 2
        case .fast: return 3
        case .burst: return 4
        }
    }

    private static func upperThreshold(for stage: CompanionPaceStage) -> Double {
        switch stage {
        case .idle:   return 0.01
        case .slow:   return 0.1
        case .normal: return 1.0
        case .fast:   return 5.0
        case .burst:  return .infinity
        }
    }

    private static func lowerThreshold(for stage: CompanionPaceStage) -> Double {
        switch stage {
        case .idle:   return 0
        case .slow:   return 0.01
        case .normal: return 0.1
        case .fast:   return 1.0
        case .burst:  return 5.0
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionPaceTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Companion/CompanionPace.swift \
        Tests/CodexBarTests/Companion/CompanionPaceTests.swift
git commit -m "feat(companion): CompanionPace classifier (thresholds + hysteresis + 3s hold)"
```

---

## Task 4: CompanionSpriteAtlas data types

Atlas part 정의 (PartKind/DrawCommand/PartAnimation/CompanionPart). 캐릭터별 데이터는 별도 파일에서 채움.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionSpriteAtlas.swift`

- [ ] **Step 1: Write the failing test placeholder (will fill in Task 5–8)**

```swift
// Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift (skeleton)
import Testing
@testable import CodexBar

@MainActor
struct CompanionSpriteAtlasTests {
    @Test
    func `data types compile`() {
        _ = CompanionPart(
            kind: .body,
            drawCommand: .pixelRect(x: 0, y: 0, width: 1, height: 1),
            animation: .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: FAIL (type not defined).

- [ ] **Step 3: Write implementation**

```swift
// Sources/CodexBar/Companion/CompanionSpriteAtlas.swift
import CodexBarCore
import CoreGraphics
import Foundation

enum CompanionPartKind: Sendable, Hashable {
    case body
    case leg(index: Int)   // 1...4
    case tail
    case ear(side: Side)
    case whisker(side: Side)

    enum Side: Sendable, Hashable { case left, right }
}

/// Coordinate space: integer grid 0..<width × 0..<height (defined per character).
/// Renderer scales to NSImage size.
enum CompanionDrawCommand: Sendable {
    /// Filled rect at integer pixel coordinates.
    case pixelRect(x: Int, y: Int, width: Int, height: Int)
    /// Stroked line between two integer points.
    case line(x1: Int, y1: Int, x2: Int, y2: Int)
    /// Stroked quadratic Bézier curve.
    case quadCurve(x1: Int, y1: Int, cx: Int, cy: Int, x2: Int, y2: Int)
    /// Filled ellipse (used for eyes/dots).
    case dot(cx: Double, cy: Double, radius: Double)
}

/// How a part animates with the master phase (0...1).
struct CompanionPartAnimation: Sendable {
    /// Phase offset applied to this part (0...1).
    let phaseOffset: Double
    /// Transform to apply at given phase.
    let transform: @Sendable (Double) -> CGAffineTransform

    init(phaseOffset: Double = 0,
         transform: @escaping @Sendable (Double) -> CGAffineTransform = { _ in .identity })
    {
        self.phaseOffset = phaseOffset
        self.transform = transform
    }

    static let none = CompanionPartAnimation()
}

struct CompanionPart: Sendable {
    let kind: CompanionPartKind
    let drawCommand: CompanionDrawCommand
    let animation: CompanionPartAnimation
}

/// Atlas: looks up parts for a character. Filled by character-specific files.
enum CompanionSpriteAtlas {
    /// Coordinate grid size for the character.
    static func gridSize(for character: CompanionCharacter) -> CGSize {
        switch character.style {
        case .pixel: return CGSize(width: 20, height: 16)
        case .line:  return CGSize(width: 22, height: 16)
        }
    }

    static func parts(for character: CompanionCharacter) -> [CompanionPart] {
        switch character {
        case .catPixel: return Self.catPixelParts
        case .catLine:  return Self.catLineParts
        case .dogPixel: return Self.dogPixelParts
        case .dogLine:  return Self.dogLineParts
        }
    }

    // Stubs — populated in subsequent tasks
    static let catPixelParts: [CompanionPart] = []
    static let catLineParts: [CompanionPart] = []
    static let dogPixelParts: [CompanionPart] = []
    static let dogLineParts: [CompanionPart] = []
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionSpriteAtlas.swift \
        Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
git commit -m "feat(companion): SpriteAtlas data types (PartKind/DrawCommand/CompanionPart)"
```

---

## Task 5: SpriteAtlas — 고양이 픽셀 parts

20×16 그리드. body + 4 legs (시간차 점프) + tail (wag) + 2 ears (rotate). 디자인 문서의 "캐릭터 스타일 v2" 시각 자료의 픽셀 고양이를 코드로 옮긴다.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionSpriteAtlas+CatPixel.swift`
- Modify: `Sources/CodexBar/Companion/CompanionSpriteAtlas.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Append to Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
@Test
func `catPixel has all required parts`() {
    let parts = CompanionSpriteAtlas.parts(for: .catPixel)
    let kinds = Set(parts.map { String(describing: $0.kind) })
    #expect(kinds.contains("body"))
    #expect(kinds.contains("tail"))
    // Two ears
    let ears = parts.filter { if case .ear = $0.kind { return true } else { return false } }
    #expect(ears.count == 2)
    // Four legs
    let legs = parts.filter { if case .leg = $0.kind { return true } else { return false } }
    #expect(legs.count == 4)
}

@Test
func `catPixel part transforms produce finite values`() {
    let parts = CompanionSpriteAtlas.parts(for: .catPixel)
    for part in parts {
        for phase in stride(from: 0.0, through: 1.0, by: 0.1) {
            let t = part.animation.transform(phase)
            #expect(t.a.isFinite && t.b.isFinite && t.c.isFinite && t.d.isFinite && t.tx.isFinite && t.ty.isFinite)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: FAIL (catPixelParts is empty).

- [ ] **Step 3: Write implementation**

```swift
// Sources/CodexBar/Companion/CompanionSpriteAtlas+CatPixel.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _catPixelParts: [CompanionPart] = {
        // Coordinate space: 20×16. Cat sits left of center, tail to the right.
        // Body bobs ±1px vertically with phase. Legs alternate up/down. Ears rotate.

        func bodyBob(phase: Double) -> CGAffineTransform {
            // Two-step (steps(2)): 0→0px, 0.5→-1px
            return CGAffineTransform(translationX: 0, y: phase < 0.5 ? 0 : -1)
        }

        func legTransform(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
            return { phase in
                let local = fmod(phase + offset, 1.0)
                // Lift the leg in the second half of the local cycle
                return CGAffineTransform(translationX: 0, y: local < 0.5 ? 0 : -2)
            }
        }

        func tailWag(phase: Double) -> CGAffineTransform {
            // Sinusoidal rotation between -15° and +20°
            let angle = (-15 + 35 * (sin(phase * 2 * .pi) * 0.5 + 0.5)) * .pi / 180
            return CGAffineTransform(rotationAngle: angle)
        }

        func earFlick(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
            return { phase in
                let local = fmod(phase + offset, 1.0)
                let angle = (local < 0.5 ? 0.0 : -15.0) * .pi / 180
                return CGAffineTransform(rotationAngle: angle)
            }
        }

        return [
            // Body (head + torso as a single rect group, drawn as several pixel rects)
            CompanionPart(
                kind: .body,
                drawCommand: .pixelRect(x: 2, y: 5, width: 5, height: 4),  // head
                animation: CompanionPartAnimation(transform: bodyBob)),
            CompanionPart(
                kind: .body,
                drawCommand: .pixelRect(x: 3, y: 9, width: 11, height: 3), // torso
                animation: CompanionPartAnimation(transform: bodyBob)),

            // Ears
            CompanionPart(
                kind: .ear(side: .left),
                drawCommand: .pixelRect(x: 2, y: 3, width: 2, height: 2),
                animation: CompanionPartAnimation(phaseOffset: 0.125,
                                                  transform: earFlick(offset: 0))),
            CompanionPart(
                kind: .ear(side: .right),
                drawCommand: .pixelRect(x: 5, y: 3, width: 2, height: 2),
                animation: CompanionPartAnimation(phaseOffset: 0.625,
                                                  transform: earFlick(offset: 0))),

            // Legs (front-left, front-right, back-left, back-right)
            CompanionPart(kind: .leg(index: 1),
                          drawCommand: .pixelRect(x: 3, y: 12, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: legTransform(offset: 0))),
            CompanionPart(kind: .leg(index: 2),
                          drawCommand: .pixelRect(x: 6, y: 12, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: legTransform(offset: 0.25))),
            CompanionPart(kind: .leg(index: 3),
                          drawCommand: .pixelRect(x: 10, y: 12, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: legTransform(offset: 0.5))),
            CompanionPart(kind: .leg(index: 4),
                          drawCommand: .pixelRect(x: 13, y: 12, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: legTransform(offset: 0.75))),

            // Tail (two pixel rects)
            CompanionPart(kind: .tail,
                          drawCommand: .pixelRect(x: 14, y: 6, width: 3, height: 1),
                          animation: CompanionPartAnimation(transform: tailWag)),
            CompanionPart(kind: .tail,
                          drawCommand: .pixelRect(x: 16, y: 7, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: tailWag)),
        ]
    }()
}
```

Now patch the main atlas file to use this:

In `Sources/CodexBar/Companion/CompanionSpriteAtlas.swift`, replace:
```swift
static let catPixelParts: [CompanionPart] = []
```
with:
```swift
static let catPixelParts: [CompanionPart] = _catPixelParts
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: PASS (3 tests now — including the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionSpriteAtlas+CatPixel.swift \
        Sources/CodexBar/Companion/CompanionSpriteAtlas.swift \
        Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
git commit -m "feat(companion): cat (pixel) sprite parts"
```

---

## Task 6: SpriteAtlas — 고양이 라인 parts

22×16 그리드. SVG line/curve 기반. 다리는 시계추 회전.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionSpriteAtlas+CatLine.swift`
- Modify: `Sources/CodexBar/Companion/CompanionSpriteAtlas.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Append to Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
@Test
func `catLine has all required parts`() {
    let parts = CompanionSpriteAtlas.parts(for: .catLine)
    let kinds = Set(parts.map { String(describing: $0.kind) })
    #expect(kinds.contains("body"))
    #expect(kinds.contains("tail"))
    let ears = parts.filter { if case .ear = $0.kind { return true } else { return false } }
    #expect(ears.count == 2)
    let legs = parts.filter { if case .leg = $0.kind { return true } else { return false } }
    #expect(legs.count == 4)
    let whiskers = parts.filter {
        if case .whisker = $0.kind { return true } else { return false }
    }
    #expect(whiskers.count == 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: FAIL.

- [ ] **Step 3: Write implementation**

```swift
// Sources/CodexBar/Companion/CompanionSpriteAtlas+CatLine.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _catLineParts: [CompanionPart] = {
        // 22×16. Line drawings (path + curve). Legs as lines that pendulum-rotate.

        func bodyBob(phase: Double) -> CGAffineTransform {
            return CGAffineTransform(translationX: 0, y: -0.5 * sin(phase * 2 * .pi))
        }

        func legSwing(offset: Double, originX: Double) -> @Sendable (Double) -> CGAffineTransform {
            return { phase in
                let local = fmod(phase + offset, 1.0)
                let angle = sin(local * 2 * .pi) * 25 * .pi / 180  // ±25°
                // Pivot at (originX, 12) — translate, rotate, translate back
                return CGAffineTransform.identity
                    .translatedBy(x: originX, y: 12)
                    .rotated(by: angle)
                    .translatedBy(x: -originX, y: -12)
            }
        }

        func tailWag(phase: Double) -> CGAffineTransform {
            let angle = (sin(phase * 2 * .pi) * 0.5 + 0.5) * 55 - 20  // -20..+35°
            return CGAffineTransform.identity
                .translatedBy(x: 18, y: 10)
                .rotated(by: angle * .pi / 180)
                .translatedBy(x: -18, y: -10)
        }

        func whiskerTwitch(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
            return { phase in
                let local = fmod(phase + offset, 1.0)
                let angle = sin(local * 2 * .pi) * 10 * .pi / 180
                return CGAffineTransform.identity
                    .translatedBy(x: 5, y: 9.5)
                    .rotated(by: angle)
                    .translatedBy(x: -5, y: -9.5)
            }
        }

        return [
            // Ears
            CompanionPart(kind: .ear(side: .left),
                          drawCommand: .line(x1: 3, y1: 6, x2: 4, y2: 3),
                          animation: CompanionPartAnimation()),
            CompanionPart(kind: .ear(side: .left),
                          drawCommand: .line(x1: 4, y1: 3, x2: 6, y2: 5),
                          animation: CompanionPartAnimation()),
            CompanionPart(kind: .ear(side: .right),
                          drawCommand: .line(x1: 9, y1: 5, x2: 9, y2: 3),
                          animation: CompanionPartAnimation()),
            CompanionPart(kind: .ear(side: .right),
                          drawCommand: .line(x1: 9, y1: 3, x2: 11, y2: 6),
                          animation: CompanionPartAnimation()),

            // Head outline (quadCurve)
            CompanionPart(kind: .body,
                          drawCommand: .quadCurve(x1: 3, y1: 6, cx: 3, cy: 9, x2: 5, y2: 10),
                          animation: CompanionPartAnimation(transform: bodyBob)),
            CompanionPart(kind: .body,
                          drawCommand: .quadCurve(x1: 5, y1: 10, cx: 11, cy: 9, x2: 11, y2: 6),
                          animation: CompanionPartAnimation(transform: bodyBob)),
            // Eye
            CompanionPart(kind: .body,
                          drawCommand: .dot(cx: 7, cy: 7, radius: 0.6),
                          animation: CompanionPartAnimation(transform: bodyBob)),
            // Torso curve
            CompanionPart(kind: .body,
                          drawCommand: .quadCurve(x1: 11, y1: 10, cx: 15, cy: 9, x2: 18, y2: 10),
                          animation: CompanionPartAnimation(transform: bodyBob)),

            // Whiskers
            CompanionPart(kind: .whisker(side: .left),
                          drawCommand: .line(x1: 5, y1: 9, x2: 2, y2: 8),
                          animation: CompanionPartAnimation(transform: whiskerTwitch(offset: 0))),
            CompanionPart(kind: .whisker(side: .right),
                          drawCommand: .line(x1: 5, y1: 10, x2: 2, y2: 11),
                          animation: CompanionPartAnimation(transform: whiskerTwitch(offset: 0.5))),

            // Tail (curve)
            CompanionPart(kind: .tail,
                          drawCommand: .quadCurve(x1: 18, y1: 10, cx: 21, cy: 8, x2: 20, y2: 5),
                          animation: CompanionPartAnimation(transform: tailWag)),

            // Legs (lines that pendulum-rotate)
            CompanionPart(kind: .leg(index: 1),
                          drawCommand: .line(x1: 7, y1: 11, x2: 7, y2: 14),
                          animation: CompanionPartAnimation(transform: legSwing(offset: 0, originX: 7))),
            CompanionPart(kind: .leg(index: 2),
                          drawCommand: .line(x1: 10, y1: 11, x2: 10, y2: 14),
                          animation: CompanionPartAnimation(transform: legSwing(offset: 0.25, originX: 10))),
            CompanionPart(kind: .leg(index: 3),
                          drawCommand: .line(x1: 13, y1: 11, x2: 13, y2: 14),
                          animation: CompanionPartAnimation(transform: legSwing(offset: 0.5, originX: 13))),
            CompanionPart(kind: .leg(index: 4),
                          drawCommand: .line(x1: 16, y1: 11, x2: 16, y2: 14),
                          animation: CompanionPartAnimation(transform: legSwing(offset: 0.75, originX: 16))),
        ]
    }()
}
```

In `CompanionSpriteAtlas.swift`, replace:
```swift
static let catLineParts: [CompanionPart] = []
```
with:
```swift
static let catLineParts: [CompanionPart] = _catLineParts
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionSpriteAtlas+CatLine.swift \
        Sources/CodexBar/Companion/CompanionSpriteAtlas.swift \
        Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
git commit -m "feat(companion): cat (line) sprite parts"
```

---

## Task 7: SpriteAtlas — 강아지 픽셀 parts

고양이 픽셀과 동일 그리드(20×16), 다른 비례 — 짧은 다리, 꼬리는 짧고 위로 뻗음, 귀는 늘어진 형태.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionSpriteAtlas+DogPixel.swift`
- Modify: `Sources/CodexBar/Companion/CompanionSpriteAtlas.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Append to Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
@Test
func `dogPixel has all required parts`() {
    let parts = CompanionSpriteAtlas.parts(for: .dogPixel)
    let ears = parts.filter { if case .ear = $0.kind { return true } else { return false } }
    let legs = parts.filter { if case .leg = $0.kind { return true } else { return false } }
    #expect(ears.count == 2)
    #expect(legs.count == 4)
    #expect(parts.contains { if case .tail = $0.kind { return true } else { return false } })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: FAIL.

- [ ] **Step 3: Write implementation**

```swift
// Sources/CodexBar/Companion/CompanionSpriteAtlas+DogPixel.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _dogPixelParts: [CompanionPart] = {
        // 20×16 grid. Dog has droopy ears, shorter legs, upright tail.

        func bodyBob(phase: Double) -> CGAffineTransform {
            CGAffineTransform(translationX: 0, y: phase < 0.5 ? 0 : -1)
        }

        func legLift(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
            return { phase in
                let local = fmod(phase + offset, 1.0)
                return CGAffineTransform(translationX: 0, y: local < 0.5 ? 0 : -2)
            }
        }

        func tailWag(phase: Double) -> CGAffineTransform {
            // Dog tail wags fast and wide (-25..+30°)
            let angle = (sin(phase * 4 * .pi) * 0.5 + 0.5) * 55 - 25
            return CGAffineTransform.identity
                .translatedBy(x: 15, y: 7)
                .rotated(by: angle * .pi / 180)
                .translatedBy(x: -15, y: -7)
        }

        func earDrop(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
            return { phase in
                let local = fmod(phase + offset, 1.0)
                return CGAffineTransform(translationX: 0, y: local < 0.5 ? 0 : 1)
            }
        }

        return [
            // Head
            CompanionPart(kind: .body,
                          drawCommand: .pixelRect(x: 2, y: 4, width: 5, height: 5),
                          animation: CompanionPartAnimation(transform: bodyBob)),
            // Snout
            CompanionPart(kind: .body,
                          drawCommand: .pixelRect(x: 0, y: 6, width: 2, height: 2),
                          animation: CompanionPartAnimation(transform: bodyBob)),
            // Torso
            CompanionPart(kind: .body,
                          drawCommand: .pixelRect(x: 3, y: 9, width: 11, height: 3),
                          animation: CompanionPartAnimation(transform: bodyBob)),

            // Droopy ears (longer, drooping down beside head)
            CompanionPart(kind: .ear(side: .left),
                          drawCommand: .pixelRect(x: 2, y: 3, width: 1, height: 3),
                          animation: CompanionPartAnimation(transform: earDrop(offset: 0))),
            CompanionPart(kind: .ear(side: .right),
                          drawCommand: .pixelRect(x: 6, y: 3, width: 1, height: 3),
                          animation: CompanionPartAnimation(transform: earDrop(offset: 0.5))),

            // Legs (slightly shorter than cat — only 2px instead of 2)
            CompanionPart(kind: .leg(index: 1),
                          drawCommand: .pixelRect(x: 4, y: 12, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: legLift(offset: 0))),
            CompanionPart(kind: .leg(index: 2),
                          drawCommand: .pixelRect(x: 6, y: 12, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: legLift(offset: 0.25))),
            CompanionPart(kind: .leg(index: 3),
                          drawCommand: .pixelRect(x: 11, y: 12, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: legLift(offset: 0.5))),
            CompanionPart(kind: .leg(index: 4),
                          drawCommand: .pixelRect(x: 13, y: 12, width: 1, height: 2),
                          animation: CompanionPartAnimation(transform: legLift(offset: 0.75))),

            // Tail (upright stub)
            CompanionPart(kind: .tail,
                          drawCommand: .pixelRect(x: 14, y: 7, width: 1, height: 3),
                          animation: CompanionPartAnimation(transform: tailWag)),
            CompanionPart(kind: .tail,
                          drawCommand: .pixelRect(x: 15, y: 6, width: 1, height: 1),
                          animation: CompanionPartAnimation(transform: tailWag)),
        ]
    }()
}
```

In `CompanionSpriteAtlas.swift`, replace `dogPixelParts` stub with `_dogPixelParts`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionSpriteAtlas+DogPixel.swift \
        Sources/CodexBar/Companion/CompanionSpriteAtlas.swift \
        Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
git commit -m "feat(companion): dog (pixel) sprite parts"
```

---

## Task 8: SpriteAtlas — 강아지 라인 parts

22×16 그리드. 라인 강아지 — 짧은 다리, 늘어진 귀, 위쪽 꼬리.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionSpriteAtlas+DogLine.swift`
- Modify: `Sources/CodexBar/Companion/CompanionSpriteAtlas.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Append to Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
@Test
func `dogLine has all required parts`() {
    let parts = CompanionSpriteAtlas.parts(for: .dogLine)
    let ears = parts.filter { if case .ear = $0.kind { return true } else { return false } }
    let legs = parts.filter { if case .leg = $0.kind { return true } else { return false } }
    #expect(ears.count == 2)
    #expect(legs.count == 4)
    #expect(parts.contains { if case .tail = $0.kind { return true } else { return false } })
}

@Test
func `all 4 characters return non-empty parts`() {
    for c in CompanionCharacter.allCases {
        #expect(!CompanionSpriteAtlas.parts(for: c).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: FAIL.

- [ ] **Step 3: Write implementation**

```swift
// Sources/CodexBar/Companion/CompanionSpriteAtlas+DogLine.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _dogLineParts: [CompanionPart] = {
        func bodyBob(phase: Double) -> CGAffineTransform {
            CGAffineTransform(translationX: 0, y: -0.5 * sin(phase * 2 * .pi))
        }

        func legSwing(offset: Double, originX: Double) -> @Sendable (Double) -> CGAffineTransform {
            return { phase in
                let local = fmod(phase + offset, 1.0)
                let angle = sin(local * 2 * .pi) * 20 * .pi / 180
                return CGAffineTransform.identity
                    .translatedBy(x: originX, y: 12)
                    .rotated(by: angle)
                    .translatedBy(x: -originX, y: -12)
            }
        }

        func tailWag(phase: Double) -> CGAffineTransform {
            let angle = sin(phase * 4 * .pi) * 45 * .pi / 180  // fast wag, ±45°
            return CGAffineTransform.identity
                .translatedBy(x: 18, y: 8)
                .rotated(by: angle)
                .translatedBy(x: -18, y: -8)
        }

        func earSway(offset: Double, originX: Double) -> @Sendable (Double) -> CGAffineTransform {
            return { phase in
                let local = fmod(phase + offset, 1.0)
                let angle = sin(local * 2 * .pi) * 12 * .pi / 180
                return CGAffineTransform.identity
                    .translatedBy(x: originX, y: 6)
                    .rotated(by: angle)
                    .translatedBy(x: -originX, y: -6)
            }
        }

        return [
            // Snout
            CompanionPart(kind: .body,
                          drawCommand: .line(x1: 0, y1: 8, x2: 3, y2: 7),
                          animation: CompanionPartAnimation(transform: bodyBob)),
            CompanionPart(kind: .body,
                          drawCommand: .line(x1: 0, y1: 8, x2: 3, y2: 9),
                          animation: CompanionPartAnimation(transform: bodyBob)),

            // Head outline
            CompanionPart(kind: .body,
                          drawCommand: .quadCurve(x1: 3, y1: 6, cx: 4, cy: 10, x2: 7, y2: 10),
                          animation: CompanionPartAnimation(transform: bodyBob)),
            CompanionPart(kind: .body,
                          drawCommand: .quadCurve(x1: 7, y1: 10, cx: 8, cy: 8, x2: 8, y2: 5),
                          animation: CompanionPartAnimation(transform: bodyBob)),

            // Eye
            CompanionPart(kind: .body,
                          drawCommand: .dot(cx: 5, cy: 7, radius: 0.6),
                          animation: CompanionPartAnimation(transform: bodyBob)),

            // Body curve
            CompanionPart(kind: .body,
                          drawCommand: .quadCurve(x1: 8, y1: 10, cx: 13, cy: 9, x2: 18, y2: 10),
                          animation: CompanionPartAnimation(transform: bodyBob)),

            // Droopy ears
            CompanionPart(kind: .ear(side: .left),
                          drawCommand: .quadCurve(x1: 4, y1: 6, cx: 3, cy: 8, x2: 4, y2: 9),
                          animation: CompanionPartAnimation(transform: earSway(offset: 0, originX: 4))),
            CompanionPart(kind: .ear(side: .right),
                          drawCommand: .quadCurve(x1: 7, y1: 6, cx: 8, cy: 8, x2: 7, y2: 9),
                          animation: CompanionPartAnimation(transform: earSway(offset: 0.5, originX: 7))),

            // Tail (upright)
            CompanionPart(kind: .tail,
                          drawCommand: .line(x1: 18, y1: 9, x2: 19, y2: 5),
                          animation: CompanionPartAnimation(transform: tailWag)),
            CompanionPart(kind: .tail,
                          drawCommand: .line(x1: 19, y1: 5, x2: 20, y2: 4),
                          animation: CompanionPartAnimation(transform: tailWag)),

            // Legs
            CompanionPart(kind: .leg(index: 1),
                          drawCommand: .line(x1: 8, y1: 11, x2: 8, y2: 14),
                          animation: CompanionPartAnimation(transform: legSwing(offset: 0, originX: 8))),
            CompanionPart(kind: .leg(index: 2),
                          drawCommand: .line(x1: 11, y1: 11, x2: 11, y2: 14),
                          animation: CompanionPartAnimation(transform: legSwing(offset: 0.25, originX: 11))),
            CompanionPart(kind: .leg(index: 3),
                          drawCommand: .line(x1: 14, y1: 11, x2: 14, y2: 14),
                          animation: CompanionPartAnimation(transform: legSwing(offset: 0.5, originX: 14))),
            CompanionPart(kind: .leg(index: 4),
                          drawCommand: .line(x1: 17, y1: 11, x2: 17, y2: 14),
                          animation: CompanionPartAnimation(transform: legSwing(offset: 0.75, originX: 17))),
        ]
    }()
}
```

In `CompanionSpriteAtlas.swift`, replace `dogLineParts` stub with `_dogLineParts`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionSpriteAtlasTests`
Expected: PASS (all 4 characters now non-empty).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionSpriteAtlas+DogLine.swift \
        Sources/CodexBar/Companion/CompanionSpriteAtlas.swift \
        Tests/CodexBarTests/Companion/CompanionSpriteAtlasTests.swift
git commit -m "feat(companion): dog (line) sprite parts"
```

---

## Task 9: CompanionIconRenderer

(character, stage, phase) → NSImage. `isTemplate = true`. NSCache로 캐싱.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionIconRenderer.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/Companion/CompanionIconRendererTests.swift
import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct CompanionIconRendererTests {
    @Test
    func `produces template image for each character/stage`() {
        for character in CompanionCharacter.allCases {
            for stage in CompanionPaceStage.allCases {
                let image = CompanionIconRenderer.render(character: character, stage: stage, phase: 0.0)
                #expect(image.isTemplate)
                #expect(image.size.width > 0)
                #expect(image.size.height > 0)
            }
        }
    }

    @Test
    func `cache returns same instance for same (character, stage, quantized phase)`() {
        CompanionIconRenderer.clearCache()
        let a = CompanionIconRenderer.render(character: .catPixel, stage: .normal, phase: 0.10)
        let b = CompanionIconRenderer.render(character: .catPixel, stage: .normal, phase: 0.10)
        #expect(a === b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionIconRendererTests`
Expected: FAIL (type not defined).

- [ ] **Step 3: Write implementation**

```swift
// Sources/CodexBar/Companion/CompanionIconRenderer.swift
import AppKit
import CodexBarCore
import CoreGraphics
import Foundation

@MainActor
enum CompanionIconRenderer {
    private static let cache = NSCache<NSString, NSImage>()
    private static let phaseQuantizationSteps = 16   // 1.0 / 16 = 0.0625
    private static let defaultSize = NSSize(width: 22, height: 18)

    static func render(
        character: CompanionCharacter,
        stage: CompanionPaceStage,
        phase: Double,
        size: NSSize = defaultSize
    ) -> NSImage {
        let quantized = Int((phase.truncatingRemainder(dividingBy: 1.0))
            * Double(self.phaseQuantizationSteps)) % self.phaseQuantizationSteps
        let key = "\(character.rawValue)|\(stage.rawValue)|\(quantized)|\(Int(size.width))x\(Int(size.height))" as NSString

        if let cached = self.cache.object(forKey: key) { return cached }

        let image = self.drawImage(
            character: character,
            phase: Double(quantized) / Double(self.phaseQuantizationSteps),
            size: size)
        image.isTemplate = true
        self.cache.setObject(image, forKey: key)
        return image
    }

    static func clearCache() {
        self.cache.removeAllObjects()
    }

    private static func drawImage(character: CompanionCharacter, phase: Double, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return image
        }

        let grid = CompanionSpriteAtlas.gridSize(for: character)
        let sx = size.width / grid.width
        let sy = size.height / grid.height
        ctx.scaleBy(x: sx, y: sy)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(character.style == .line ? 1.2 / max(sx, sy) : 0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let parts = CompanionSpriteAtlas.parts(for: character)
        for part in parts {
            ctx.saveGState()
            let t = part.animation.transform(phase)
            ctx.concatenate(t)
            self.draw(part.drawCommand, in: ctx, style: character.style)
            ctx.restoreGState()
        }
        return image
    }

    private static func draw(_ command: CompanionDrawCommand, in ctx: CGContext, style: CompanionStyle) {
        switch command {
        case .pixelRect(let x, let y, let w, let h):
            let rect = CGRect(x: x, y: y, width: w, height: h)
            ctx.fill(rect)

        case .line(let x1, let y1, let x2, let y2):
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addLine(to: CGPoint(x: x2, y: y2))
            ctx.strokePath()

        case .quadCurve(let x1, let y1, let cx, let cy, let x2, let y2):
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addQuadCurve(
                to: CGPoint(x: x2, y: y2),
                control: CGPoint(x: cx, y: cy))
            ctx.strokePath()

        case .dot(let cx, let cy, let radius):
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            ctx.fillEllipse(in: rect)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionIconRendererTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionIconRenderer.swift \
        Tests/CodexBarTests/Companion/CompanionIconRendererTests.swift
git commit -m "feat(companion): IconRenderer with NSCache + quantized phase"
```

---

## Task 10: CompanionAnimationDriver

DisplayLinkDriver wrap. stage 변경 시 fps 재설정. phase는 stage.frameInterval에 따라 누적.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionAnimationDriver.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/Companion/CompanionAnimationDriverTests.swift
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct CompanionAnimationDriverTests {
    @Test
    func `stage setter updates current stage`() {
        let driver = CompanionAnimationDriver()
        driver.stage = .fast
        #expect(driver.stage == .fast)
    }

    @Test
    func `phase advances when manually stepped (for testability)`() {
        let driver = CompanionAnimationDriver()
        driver.stage = .normal
        driver.advancePhase(deltaTime: 0.3)
        #expect(driver.phase > 0)
    }

    @Test
    func `phase wraps in [0, 1)`() {
        let driver = CompanionAnimationDriver()
        driver.stage = .burst
        // burst frameInterval = 0.15 → 1.0 full cycle takes 0.15s
        // Step by 0.2s → should wrap
        driver.advancePhase(deltaTime: 0.2)
        #expect(driver.phase >= 0 && driver.phase < 1)
    }

    @Test
    func `idle stage advances phase very slowly (body breathing)`() {
        let driver = CompanionAnimationDriver()
        driver.stage = .idle
        // idle frameInterval = 20s
        driver.advancePhase(deltaTime: 1.0)
        // 1s / 20s = 0.05
        #expect(abs(driver.phase - 0.05) < 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionAnimationDriverTests`
Expected: FAIL.

- [ ] **Step 3: Write implementation**

```swift
// Sources/CodexBar/Companion/CompanionAnimationDriver.swift
import AppKit
import CodexBarCore
import Foundation
import QuartzCore

@MainActor
@Observable
final class CompanionAnimationDriver {
    private(set) var phase: Double = 0
    var stage: CompanionPaceStage = .idle

    var onFrame: ((Double) -> Void)?

    private var displayLink: DisplayLinkDriver?
    private var lastTickTime: CFTimeInterval = 0

    init() {}

    func start() {
        guard self.displayLink == nil else { return }
        let link = DisplayLinkDriver { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let dt = self.lastTickTime == 0 ? 0 : now - self.lastTickTime
            self.lastTickTime = now
            if dt > 0 {
                self.advancePhase(deltaTime: dt)
                self.onFrame?(self.phase)
            }
        }
        // Cap at 30 FPS — sufficient for our stages.
        link.start(fps: 30)
        self.displayLink = link
    }

    func stop() {
        self.displayLink?.stop()
        self.displayLink = nil
        self.lastTickTime = 0
    }

    /// Test-only and tick-internal. Advances phase by dt seconds at current stage.
    func advancePhase(deltaTime: TimeInterval) {
        let interval = self.stage.frameInterval
        guard interval > 0 else { return }
        let delta = deltaTime / interval
        self.phase = (self.phase + delta).truncatingRemainder(dividingBy: 1.0)
        if self.phase < 0 { self.phase += 1 }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionAnimationDriverTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionAnimationDriver.swift \
        Tests/CodexBarTests/Companion/CompanionAnimationDriverTests.swift
git commit -m "feat(companion): AnimationDriver wrapping DisplayLinkDriver"
```

---

## Task 11: CompanionStatusItemController skeleton (NSStatusItem 생성/해제)

새 NSStatusItem 라이프사이클. start()에서 NSStatusItem 생성하고 idle 이미지 표시. stop()에서 release.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionStatusItemController.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/CodexBarTests/Companion/CompanionStatusItemControllerTests.swift
import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct CompanionStatusItemControllerTests {
    @Test
    func `start creates status item, stop releases it`() {
        let controller = CompanionStatusItemController(
            character: .catPixel,
            provider: .claude,
            menuProvider: { NSMenu(title: "test") })
        #expect(controller.statusItem == nil)
        controller.start()
        #expect(controller.statusItem != nil)
        controller.stop()
        #expect(controller.statusItem == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionStatusItemControllerTests`
Expected: FAIL.

- [ ] **Step 3: Write implementation**

```swift
// Sources/CodexBar/Companion/CompanionStatusItemController.swift
import AppKit
import CodexBarCore
import Foundation

@MainActor
final class CompanionStatusItemController {
    private(set) var statusItem: NSStatusItem?
    private let driver = CompanionAnimationDriver()
    private let menuProvider: () -> NSMenu

    var character: CompanionCharacter
    var provider: UsageProvider

    init(character: CompanionCharacter,
         provider: UsageProvider,
         menuProvider: @escaping () -> NSMenu)
    {
        self.character = character
        self.provider = provider
        self.menuProvider = menuProvider
    }

    func start() {
        guard self.statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.button?.image = CompanionIconRenderer.render(
            character: self.character, stage: .idle, phase: 0)
        item.button?.action = #selector(self.handleClick)
        item.button?.target = self
        item.menu = self.menuProvider()
        self.statusItem = item

        self.driver.onFrame = { [weak self] phase in
            guard let self, let item = self.statusItem else { return }
            item.button?.image = CompanionIconRenderer.render(
                character: self.character, stage: self.driver.stage, phase: phase)
        }
        self.driver.start()
    }

    func stop() {
        self.driver.stop()
        if let item = self.statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.statusItem = nil
    }

    @objc private func handleClick() {
        // Menu auto-shows because we assigned item.menu. No-op here.
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionStatusItemControllerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionStatusItemController.swift \
        Tests/CodexBarTests/Companion/CompanionStatusItemControllerTests.swift
git commit -m "feat(companion): StatusItemController skeleton (start/stop)"
```

---

## Task 12: SettingsStore — Companion fields & extension

SettingsDefaultsState에 4개 필드 추가, init에서 UserDefaults 로드, extension에서 getter/setter (copy-modify-reassign 패턴 준수).

**Files:**
- Modify: `Sources/CodexBar/SettingsStoreState.swift`
- Modify: `Sources/CodexBar/SettingsStore.swift` (init 부분)
- Create: `Sources/CodexBar/SettingsStore+Companion.swift`
- Test: `Tests/CodexBarTests/Companion/SettingsStoreCompanionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/Companion/SettingsStoreCompanionTests.swift
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreCompanionTests {
    private func freshStore() -> SettingsStore {
        let defaults = UserDefaults(suiteName: "CompanionTest-\(UUID().uuidString)")!
        return SettingsStore(userDefaults: defaults)
    }

    @Test
    func `companionEnabled defaults to false`() {
        let store = freshStore()
        #expect(store.companionEnabled == false)
    }

    @Test
    func `companionCharacter defaults to catPixel`() {
        let store = freshStore()
        #expect(store.companionCharacter == .catPixel)
    }

    @Test
    func `companionProvider defaults to claude`() {
        let store = freshStore()
        #expect(store.companionProvider == .claude)
    }

    @Test
    func `setting companionEnabled persists`() {
        let store = freshStore()
        store.companionEnabled = true
        #expect(store.companionEnabled == true)
    }

    @Test
    func `setting companionCharacter persists`() {
        let store = freshStore()
        store.companionCharacter = .dogLine
        #expect(store.companionCharacter == .dogLine)
    }

    @Test
    func `companionFeatureSeen defaults to false`() {
        let store = freshStore()
        #expect(store.companionFeatureSeen == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsStoreCompanionTests`
Expected: FAIL.

- [ ] **Step 3: Write implementation**

In `Sources/CodexBar/SettingsStoreState.swift`, append at end of `SettingsDefaultsState` struct:

```swift
    // Companion feature
    var companionEnabled: Bool
    var companionCharacterRaw: String
    var companionProviderRaw: String
    var companionFeatureSeen: Bool
```

In `Sources/CodexBar/SettingsStore.swift`, find where `defaultsState` is initialized in `init(...)` (search for `defaultsState =`) and add 4 fields with these defaults:

```swift
companionEnabled: userDefaults.bool(forKey: "companion.enabled"),
companionCharacterRaw: userDefaults.string(forKey: "companion.character") ?? CompanionCharacter.catPixel.rawValue,
companionProviderRaw: userDefaults.string(forKey: "companion.provider") ?? UsageProvider.claude.rawValue,
companionFeatureSeen: userDefaults.bool(forKey: "companion.featureSeen"),
```

> If the init uses a builder pattern where each field is set explicitly, add the 4 lines in the same style. The exact location: find the `SettingsDefaultsState(...)` literal initializer in `SettingsStore.init`.

Create `Sources/CodexBar/SettingsStore+Companion.swift`:

```swift
import CodexBarCore
import Foundation

extension SettingsStore {
    var companionEnabled: Bool {
        get { self.defaultsState.companionEnabled }
        set {
            var state = self.defaultsState
            state.companionEnabled = newValue
            self.defaultsState = state
            self.userDefaults.set(newValue, forKey: "companion.enabled")
        }
    }

    var companionCharacter: CompanionCharacter {
        get {
            CompanionCharacter(rawValue: self.defaultsState.companionCharacterRaw) ?? .catPixel
        }
        set {
            var state = self.defaultsState
            state.companionCharacterRaw = newValue.rawValue
            self.defaultsState = state
            self.userDefaults.set(newValue.rawValue, forKey: "companion.character")
        }
    }

    var companionProvider: UsageProvider {
        get {
            UsageProvider(rawValue: self.defaultsState.companionProviderRaw) ?? .claude
        }
        set {
            var state = self.defaultsState
            state.companionProviderRaw = newValue.rawValue
            self.defaultsState = state
            self.userDefaults.set(newValue.rawValue, forKey: "companion.provider")
        }
    }

    var companionFeatureSeen: Bool {
        get { self.defaultsState.companionFeatureSeen }
        set {
            var state = self.defaultsState
            state.companionFeatureSeen = newValue
            self.defaultsState = state
            self.userDefaults.set(newValue, forKey: "companion.featureSeen")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsStoreCompanionTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/SettingsStoreState.swift \
        Sources/CodexBar/SettingsStore.swift \
        Sources/CodexBar/SettingsStore+Companion.swift \
        Tests/CodexBarTests/Companion/SettingsStoreCompanionTests.swift
git commit -m "feat(companion): SettingsStore companion fields with copy-modify-reassign"
```

---

## Task 13: Wire UsageStore → BurnRateCalculator → CompanionPace → Driver

CompanionStatusItemController에 observation 추가. **중요한 발견**: `UsageStore.planUtilizationHistory(for:)` 는 1시간 sample 간격(`planUtilizationMinSampleIntervalSeconds = 3600`)이라 5분 burn rate 계산에 부적합. 그래서 Companion이 **자체 5분 ring buffer**를 유지하고, polling 시점마다 `UsageStore.snapshots[provider]`에서 현재 weekly usedPercent를 추출해 누적한다.

> **Spec 차이**: spec의 "데이터 소스 = PlanUtilizationHistoryStore 시계열" 표현은 *기존 인프라 재활용* 의도였으나, 실제 grain이 너무 거칠어 Companion 전용 ring buffer로 교체. 외부 효과(별도 폴링 없음, 429 영향 zero)는 spec과 동일하게 유지됨 — UsageStore의 기존 snapshot만 reading.

**Files:**
- Modify: `Sources/CodexBar/Companion/CompanionStatusItemController.swift`

- [ ] **Step 1: Identify the weekly usedPercent accessor**

Run: `grep -n "weeklyUsedPercent\|seven_day\|weekly.*UsedPercent\|RateWindow" Sources/CodexBarCore/CreditsModels.swift Sources/CodexBarCore/ProviderCostSnapshot.swift 2>/dev/null | head -10`

Find the property/path on `ProviderCostSnapshot` (or `RateWindow`) that exposes the *weekly* `usedPercent`. Likely paths:
- `snapshot.windows.weekly?.usedPercent`
- `snapshot.weekly?.usedPercent`

Note the exact path and use it in `currentWeeklyPercent` below. If the snapshot's weekly value is a `Double?` instead of `Double`, keep the `Double?` and skip recording when nil.

- [ ] **Step 2: Modify CompanionStatusItemController**

Replace the `init`/`start`/`stop` code with the wired-up version:

```swift
// Sources/CodexBar/Companion/CompanionStatusItemController.swift
import AppKit
import CodexBarCore
import Foundation
import Observation

@MainActor
final class CompanionStatusItemController {
    private(set) var statusItem: NSStatusItem?
    private let driver = CompanionAnimationDriver()
    private let menuProvider: () -> NSMenu
    private let usageStore: UsageStore
    private let calculator = BurnRateCalculator()
    private var observationTask: Task<Void, Never>?
    private var lastStageChangeAt: Date = .distantPast
    private var lastStage: CompanionPaceStage?

    // Companion-owned 5-minute ring buffer
    private var samples: [PlanUtilizationHistoryEntry] = []
    private let sampleWindow: TimeInterval = 300

    var character: CompanionCharacter
    var provider: UsageProvider

    init(character: CompanionCharacter,
         provider: UsageProvider,
         usageStore: UsageStore,
         menuProvider: @escaping () -> NSMenu)
    {
        self.character = character
        self.provider = provider
        self.usageStore = usageStore
        self.menuProvider = menuProvider
    }

    func start() {
        guard self.statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.button?.image = CompanionIconRenderer.render(
            character: self.character, stage: .idle, phase: 0)
        item.button?.action = #selector(self.handleClick)
        item.button?.target = self
        item.menu = self.menuProvider()
        self.statusItem = item

        self.driver.onFrame = { [weak self] phase in
            guard let self, let item = self.statusItem else { return }
            item.button?.image = CompanionIconRenderer.render(
                character: self.character, stage: self.driver.stage, phase: phase)
        }
        self.driver.start()
        self.startObservation()
    }

    func stop() {
        self.observationTask?.cancel()
        self.observationTask = nil
        self.driver.stop()
        if let item = self.statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.statusItem = nil
        self.samples.removeAll()
    }

    @objc private func handleClick() {
        // NSStatusItem.menu auto-shows.
    }

    /// Polls every 30s — append current weekly usedPercent to ring buffer, recompute stage.
    private func startObservation() {
        self.observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshStage()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func refreshStage() async {
        let now = Date()
        self.recordSampleIfPossible(at: now)
        let burn = await self.calculator.update(entries: self.samples, now: now)
        let timeSince = now.timeIntervalSince(self.lastStageChangeAt)
        let newStage = CompanionPace.classify(
            burnRate: burn,
            previous: self.lastStage,
            timeSinceLastChange: timeSince)
        if newStage != self.lastStage {
            self.lastStage = newStage
            self.lastStageChangeAt = now
            self.driver.stage = newStage
        }
    }

    /// Reads the current weekly usedPercent from UsageStore.snapshots and appends to ring buffer.
    /// Trims samples older than `sampleWindow`.
    private func recordSampleIfPossible(at now: Date) {
        guard let percent = self.currentWeeklyPercent(for: self.provider) else { return }
        self.samples.append(PlanUtilizationHistoryEntry(
            capturedAt: now,
            usedPercent: percent,
            resetsAt: nil))
        let cutoff = now.addingTimeInterval(-self.sampleWindow)
        self.samples.removeAll { $0.capturedAt < cutoff }
    }

    /// **Engineer note**: Adapt this body to the exact snapshot path found in Step 1.
    /// Example shapes (uncomment whichever matches):
    ///   return self.usageStore.snapshots[provider]?.windows.weekly?.usedPercent
    ///   return self.usageStore.snapshots[provider]?.weekly?.usedPercent
    private func currentWeeklyPercent(for provider: UsageProvider) -> Double? {
        // Adapt — placeholder returns nil so no samples accumulate until wired.
        return nil
    }
}
```

> **Engineer hand-off note**: The `weeklyEntries(for:)` body MUST be replaced with the real accessor before the feature works. Search `Sources/CodexBar/UsageStore*.swift` for `planUtilizationHistoryBuckets` and use that. Keep the function signature unchanged.

- [ ] **Step 3: Update existing test if needed**

The old test in `CompanionStatusItemControllerTests.swift` uses an init without `usageStore`. Update:

```swift
@Test
func `start creates status item, stop releases it`() {
    let store = makeTestUsageStore()
    let controller = CompanionStatusItemController(
        character: .catPixel,
        provider: .claude,
        usageStore: store,
        menuProvider: { NSMenu(title: "test") })
    #expect(controller.statusItem == nil)
    controller.start()
    #expect(controller.statusItem != nil)
    controller.stop()
    #expect(controller.statusItem == nil)
}

private func makeTestUsageStore() -> UsageStore {
    let defaults = UserDefaults(suiteName: "WireTest-\(UUID().uuidString)")!
    let settings = SettingsStore(userDefaults: defaults)
    let fetcher = UsageFetcher()
    return UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
}
```

- [ ] **Step 4: Run test**

Run: `swift test --filter CompanionStatusItemControllerTests`
Expected: PASS (existing test still works).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionStatusItemController.swift \
        Tests/CodexBarTests/Companion/CompanionStatusItemControllerTests.swift
git commit -m "feat(companion): wire UsageStore → BurnRate → Pace → Driver"
```

---

## Task 14: Tooltip + accessibility label

stage 변경 시 button.toolTip과 accessibilityLabel 갱신.

**Files:**
- Modify: `Sources/CodexBar/Companion/CompanionStatusItemController.swift`

- [ ] **Step 1: Modify implementation**

In `CompanionStatusItemController.refreshStage()`, after updating `self.driver.stage`, add:

```swift
            self.updateButtonMetadata(stage: newStage, burnRate: burn)
        }
    }

    private func updateButtonMetadata(stage: CompanionPaceStage, burnRate: Double) {
        guard let button = self.statusItem?.button else { return }
        let providerName = self.provider == .claude ? "Claude" : "Codex"
        if stage == .idle {
            let tip = String(format: NSLocalizedString("companion.tooltip.idle",
                                                       comment: ""), providerName)
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
        } else {
            let stageName = self.stageDisplayName(stage)
            let tip = String(format: NSLocalizedString("companion.tooltip.active",
                                                       comment: ""),
                             providerName, stageName, burnRate)
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
        }
    }

    private func stageDisplayName(_ s: CompanionPaceStage) -> String {
        switch s {
        case .idle:   return NSLocalizedString("companion.stage.idle", comment: "")
        case .slow:   return NSLocalizedString("companion.stage.slow", comment: "")
        case .normal: return NSLocalizedString("companion.stage.normal", comment: "")
        case .fast:   return NSLocalizedString("companion.stage.fast", comment: "")
        case .burst:  return NSLocalizedString("companion.stage.burst", comment: "")
        }
    }
```

Also call `updateButtonMetadata` once in `start()` after creating the status item so the tooltip is set immediately.

- [ ] **Step 2: Manual verification (no test — UI-only)**

Build + run:
```bash
swift build
./Scripts/compile_and_run.sh   # or build_for_distribution.sh + reinstall
```
Hover over the companion status item — tooltip should appear (using English fallback strings until Task 19 adds Korean).

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionStatusItemController.swift
git commit -m "feat(companion): tooltip + accessibility label updates"
```

---

## Task 15: AppDelegate / CodexbarApp — controller lifecycle

`AppDelegate.configure` 호출 부분에 CompanionStatusItemController 인스턴스를 생성/관리하고, settings.companionEnabled 변경에 반응해 start/stop.

**Files:**
- Modify: `Sources/CodexBar/CodexbarApp.swift` 또는 AppDelegate

- [ ] **Step 1: Find the integration point**

Run: `grep -n "StatusItemController\|configure" Sources/CodexBar/CodexbarApp.swift | head -10`
Run: `grep -n "configure\|statusController" Sources/CodexBar/AppNotifications.swift Sources/CodexBar/CodexbarApp.swift | head -10`

Find where `StatusItemController` is instantiated (likely in `AppDelegate.configure(_:)`). Add Companion controller alongside.

- [ ] **Step 2: Add controller field and observation**

In the same class that owns `StatusItemController`, add:

```swift
private var companionController: CompanionStatusItemController?
private var companionObservationTask: Task<Void, Never>?
```

In `configure(_:)`, after creating `StatusItemController`, add:

```swift
self.setupCompanionController(
    settings: configuration.settings,
    store: configuration.store,
    statusController: statusController)
```

Add helper:

```swift
@MainActor
private func setupCompanionController(
    settings: SettingsStore,
    store: UsageStore,
    statusController: StatusItemControlling)
{
    let updateController = { [weak self, weak settings, weak store, weak statusController] in
        guard let self, let settings, let store, let statusController else { return }
        if settings.companionEnabled {
            if self.companionController == nil {
                let controller = CompanionStatusItemController(
                    character: settings.companionCharacter,
                    provider: settings.companionProvider,
                    usageStore: store,
                    menuProvider: { statusController.sharedMenu() })
                controller.start()
                self.companionController = controller
            } else {
                self.companionController?.character = settings.companionCharacter
                self.companionController?.provider = settings.companionProvider
            }
        } else {
            self.companionController?.stop()
            self.companionController = nil
        }
    }
    updateController()

    self.companionObservationTask = Task { @MainActor [weak settings] in
        while !Task.isCancelled {
            _ = settings?.companionEnabled
            _ = settings?.companionCharacter
            _ = settings?.companionProvider
            try? await Task.sleep(for: .milliseconds(500))
            updateController()
        }
    }
}
```

> **Engineer note**: `StatusItemControlling.sharedMenu()` may not exist as-is. You need to expose a method on `StatusItemController` that returns the same `NSMenu` that the existing pill clicks use. If `StatusItemController+Menu.swift` builds menus via a closure, add a public method like:
>
> ```swift
> // in StatusItemController
> func sharedMenu() -> NSMenu { /* return built menu */ }
> ```
> This is the only modification to existing `StatusItemController`. Keep this method as a thin wrapper around the existing menu builder.

- [ ] **Step 3: Manual verification**

Build, run, toggle `companionEnabled` via `UserDefaults` (or wait until Task 17 to test through UI):

```bash
defaults write CodexBar companion.enabled -bool true
./Scripts/compile_and_run.sh
# Should see a new status item in menubar
defaults write CodexBar companion.enabled -bool false
# Should disappear on next polling tick (≤500ms)
```

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexBar/CodexbarApp.swift Sources/CodexBar/StatusItemController.swift
git commit -m "feat(companion): AppDelegate controller lifecycle + StatusItemController.sharedMenu()"
```

---

## Task 16: CompanionPreviewView (환경설정 미리보기)

5초 cycle로 모든 stage를 보여주는 SwiftUI 뷰. 환경설정에서 사용.

**Files:**
- Create: `Sources/CodexBar/Companion/CompanionPreviewView.swift`

- [ ] **Step 1: Write the implementation (UI — no unit test)**

```swift
// Sources/CodexBar/Companion/CompanionPreviewView.swift
import CodexBarCore
import SwiftUI

@MainActor
struct CompanionPreviewView: View {
    let character: CompanionCharacter
    @State private var phase: Double = 0
    @State private var stageIndex: Int = 0

    private let stages: [CompanionPaceStage] = [.idle, .slow, .normal, .fast, .burst]
    private let cycleDuration: TimeInterval = 5.0   // 1s per stage
    private let frameInterval: TimeInterval = 1.0 / 30.0   // 30 FPS

    var body: some View {
        TimelineView(.animation(minimumInterval: self.frameInterval)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let cyclePos = elapsed.truncatingRemainder(dividingBy: self.cycleDuration) / self.cycleDuration
            let stageIdx = Int(cyclePos * Double(self.stages.count)) % self.stages.count
            let stage = self.stages[stageIdx]
            let stagePhase = (elapsed / stage.frameInterval).truncatingRemainder(dividingBy: 1.0)
            let image = CompanionIconRenderer.render(
                character: self.character, stage: stage, phase: stagePhase,
                size: NSSize(width: 88, height: 72))
            HStack(spacing: 16) {
                Image(nsImage: image)
                VStack(alignment: .leading) {
                    Text(L("companion.preview.label"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(self.stageLabel(stage))
                        .font(.body.monospaced())
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        }
    }

    private func stageLabel(_ s: CompanionPaceStage) -> String {
        switch s {
        case .idle:   return L("companion.stage.idle")
        case .slow:   return L("companion.stage.slow")
        case .normal: return L("companion.stage.normal")
        case .fast:   return L("companion.stage.fast")
        case .burst:  return L("companion.stage.burst")
        }
    }
}
```

- [ ] **Step 2: Manual verification**

Cannot verify until Task 17 wires it into Preferences. Skip; verify there.

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionPreviewView.swift
git commit -m "feat(companion): preview view (5s cycle through stages)"
```

---

## Task 17: PreferencesDisplayPane — 캐릭터 섹션 추가

기존 표시 탭의 마지막에 SettingsSection 추가.

**Files:**
- Modify: `Sources/CodexBar/PreferencesDisplayPane.swift`

- [ ] **Step 1: Modify the view**

In `PreferencesDisplayPane.swift`, after the last `SettingsSection` in `body`, add a `Divider()` and a new section:

```swift
                Divider()

                SettingsSection(contentSpacing: 12) {
                    HStack {
                        Text(L("companion.section.title"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        if !self.settings.companionFeatureSeen {
                            Text(L("companion.new.badge"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }

                    PreferenceToggleRow(
                        title: L("companion.toggle.label"),
                        subtitle: L("companion.toggle.subtitle"),
                        binding: Binding(
                            get: { self.settings.companionEnabled },
                            set: {
                                self.settings.companionEnabled = $0
                                self.settings.companionFeatureSeen = true
                            }
                        ))

                    if self.settings.companionEnabled {
                        HStack(alignment: .top, spacing: 12) {
                            Text(L("companion.character.label"))
                                .font(.body)
                            Spacer()
                            Picker(L("companion.character.label"),
                                   selection: self.$settings.companionCharacter) {
                                ForEach(CompanionCharacter.allCases, id: \.self) { char in
                                    Text(self.characterLabel(char)).tag(char)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text(L("companion.target.label"))
                                .font(.body)
                            Spacer()
                            Picker(L("companion.target.label"),
                                   selection: self.$settings.companionProvider) {
                                Text("Claude").tag(UsageProvider.claude)
                                Text("Codex").tag(UsageProvider.codex)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        }

                        CompanionPreviewView(character: self.settings.companionCharacter)
                    }
                }
```

Add helper method to `DisplayPane`:

```swift
    private func characterLabel(_ c: CompanionCharacter) -> String {
        switch c {
        case .catPixel: return L("companion.character.catPixel")
        case .catLine:  return L("companion.character.catLine")
        case .dogPixel: return L("companion.character.dogPixel")
        case .dogLine:  return L("companion.character.dogLine")
        }
    }
```

Add Picker binding helper for SettingsStore: `companionCharacter` and `companionProvider` need `@Bindable`-friendly bindings. Since `SettingsStore` is `@Observable` already, `self.$settings.companionCharacter` should work as-is.

- [ ] **Step 2: Manual verification**

Build + run. Open Preferences → 표시 tab. Scroll to bottom. Should see "캐릭터" section with NEW badge. Toggle should reveal character picker + provider picker + preview.

```bash
./Scripts/compile_and_run.sh
# Open ClCoBar → Preferences → 표시 tab
```

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexBar/PreferencesDisplayPane.swift
git commit -m "feat(companion): PreferencesDisplayPane character section + preview"
```

---

## Task 18: Edge cases — Reduce Motion + backoff freeze + stale fallback

`refreshStage()`에 세 가지 엣지케이스를 추가:
1. **Reduce Motion**: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` true → stage = idle
2. **Backoff freeze**: UsageStore가 rate-limit backoff 상태면 calculator freeze, 마지막 stage 유지
3. **Stale fallback**: 마지막 sample이 5분 초과 → stage = idle

**Files:**
- Modify: `Sources/CodexBar/Companion/CompanionStatusItemController.swift`

- [ ] **Step 1: Find the backoff accessor on UsageStore**

CLAUDE.md에 따르면 `rateLimitBackoffUntil[provider]: Date?`가 `UsageStore`(또는 `UsageStore+Refresh.swift`)에 존재한다. 정확한 이름 확인:

```bash
grep -n "rateLimitBackoff\|backoffUntil\|isInBackoff" Sources/CodexBar/UsageStore*.swift | head -10
```

이름 후보:
- `usageStore.rateLimitBackoffUntil[provider] > Date()`
- `usageStore.isInBackoff(provider:)`

후자가 없으면 `rateLimitBackoffUntil` 사전에서 직접 비교.

- [ ] **Step 2: Modify refreshStage with all three edge cases**

Replace `refreshStage()` body:

```swift
    private func refreshStage() async {
        let now = Date()
        self.recordSampleIfPossible(at: now)

        // (1) Backoff: freeze calculator, keep last stage
        let inBackoff = self.isProviderInBackoff(provider: self.provider, now: now)
        if inBackoff {
            await self.calculator.freeze()
        } else {
            await self.calculator.resume()
        }

        let burn = await self.calculator.update(entries: self.samples, now: now)
        let timeSince = now.timeIntervalSince(self.lastStageChangeAt)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let lastSampleAge: TimeInterval = self.samples.last
            .map { now.timeIntervalSince($0.capturedAt) } ?? .greatestFiniteMagnitude
        let stale = lastSampleAge > 300

        let newStage: CompanionPaceStage
        if reduceMotion || stale {
            newStage = .idle
        } else if inBackoff {
            newStage = self.lastStage ?? .idle   // keep last
        } else {
            newStage = CompanionPace.classify(
                burnRate: burn,
                previous: self.lastStage,
                timeSinceLastChange: timeSince)
        }

        if newStage != self.lastStage {
            self.lastStage = newStage
            self.lastStageChangeAt = now
            self.driver.stage = newStage
            self.updateButtonMetadata(stage: newStage, burnRate: burn)
        }
    }

    /// **Engineer note**: Adapt to the real backoff accessor found in Step 1.
    private func isProviderInBackoff(provider: UsageProvider, now: Date) -> Bool {
        // Example: return (self.usageStore.rateLimitBackoffUntil[provider] ?? .distantPast) > now
        return false   // placeholder until wired
    }
```

- [ ] **Step 3: Manual verification**

(a) Reduce Motion: System Preferences → Accessibility → Display → "Reduce motion" ON. Character should freeze to idle.

(b) Stale: Disconnect from network and wait 5+ min. Stage should drop to idle.

(c) Backoff: Force a 429 by manually setting `rateLimitBackoffUntil` (or wait for natural occurrence). Stage should hold whatever value it had.

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexBar/Companion/CompanionStatusItemController.swift
git commit -m "feat(companion): edge cases (Reduce Motion, backoff freeze, stale fallback)"
```

---

## Task 19: 한국어 Localization

`ko.lproj/Localizable.strings`와 `en.lproj/Localizable.strings`에 모든 새 key 추가.

**Files:**
- Modify: `Sources/CodexBar/Resources/ko.lproj/Localizable.strings`
- Modify: `Sources/CodexBar/Resources/en.lproj/Localizable.strings`

- [ ] **Step 1: Locate file**

Run: `ls Sources/CodexBar/Resources/ko.lproj/`

Expect: `Localizable.strings`.

- [ ] **Step 2: Append Korean strings**

Append to `Sources/CodexBar/Resources/ko.lproj/Localizable.strings`:

```
"companion.section.title" = "캐릭터";
"companion.toggle.label" = "메뉴바에 캐릭터 표시";
"companion.toggle.subtitle" = "토큰 사용 속도에 따라 움직이는 캐릭터를 메뉴바에 추가합니다.";
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
"companion.tooltip.active" = "%1$@ · %2$@ · %3$.2f%%/분";
"companion.stage.idle" = "휴식";
"companion.stage.slow" = "느림";
"companion.stage.normal" = "보통";
"companion.stage.fast" = "빠름";
"companion.stage.burst" = "폭주";
```

Append same keys to `Sources/CodexBar/Resources/en.lproj/Localizable.strings` (English fallback):

```
"companion.section.title" = "Character";
"companion.toggle.label" = "Show character in menu bar";
"companion.toggle.subtitle" = "Adds a character to the menu bar that moves at a speed based on token burn rate.";
"companion.character.label" = "Character";
"companion.target.label" = "Target";
"companion.character.catPixel" = "Cat (pixel)";
"companion.character.catLine" = "Cat (line)";
"companion.character.dogPixel" = "Dog (pixel)";
"companion.character.dogLine" = "Dog (line)";
"companion.preview.label" = "Preview";
"companion.new.badge" = "NEW";
"companion.first.toast" = "🐱 Character added to menu bar";
"companion.tooltip.idle" = "%@ · idle";
"companion.tooltip.active" = "%1$@ · %2$@ · %3$.2f%%/min";
"companion.stage.idle" = "idle";
"companion.stage.slow" = "slow";
"companion.stage.normal" = "normal";
"companion.stage.fast" = "fast";
"companion.stage.burst" = "burst";
```

- [ ] **Step 3: Manual verification**

Run app. Open Preferences → 표시 tab. All companion strings should be in Korean.

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexBar/Resources/ko.lproj/Localizable.strings \
        Sources/CodexBar/Resources/en.lproj/Localizable.strings
git commit -m "i18n(companion): Korean + English strings"
```

---

## Task 20: First-toggle toast

캐릭터를 처음 ON으로 켰을 때 NSUserNotification 또는 in-app banner로 토스트 메시지 표시.

**Files:**
- Modify: `Sources/CodexBar/PreferencesDisplayPane.swift`

- [ ] **Step 1: Modify toggle handler**

Replace the toggle binding in PreferencesDisplayPane Companion section:

```swift
                    PreferenceToggleRow(
                        title: L("companion.toggle.label"),
                        subtitle: L("companion.toggle.subtitle"),
                        binding: Binding(
                            get: { self.settings.companionEnabled },
                            set: { newValue in
                                let wasOff = !self.settings.companionEnabled
                                let wasUnseen = !self.settings.companionFeatureSeen
                                self.settings.companionEnabled = newValue
                                self.settings.companionFeatureSeen = true
                                if newValue, wasOff, wasUnseen {
                                    Self.showFirstEnableNotification()
                                }
                            }
                        ))
```

Add static helper:

```swift
extension DisplayPane {
    static func showFirstEnableNotification() {
        let center = NSUserNotificationCenter.default
        let notification = NSUserNotification()
        notification.title = L("companion.first.toast")
        notification.subtitle = ""
        notification.soundName = nil
        center.deliver(notification)
    }
}
```

> If `NSUserNotification` is deprecated for the project's deployment target and `UNUserNotificationCenter` is preferred, use that — search for an existing `UNUserNotificationCenter` use in the project (e.g., `SessionQuotaNotifications.swift`) and copy the pattern. Either notification API is acceptable here.

- [ ] **Step 2: Manual verification**

Reset state: `defaults delete CodexBar companion.featureSeen; defaults delete CodexBar companion.enabled`. Build, run, open Preferences, toggle ON. Toast should appear once. Toggling OFF then ON again should NOT show toast.

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexBar/PreferencesDisplayPane.swift
git commit -m "feat(companion): first-enable toast notification"
```

---

## Task 21: Self-review integration test (manual + sanity)

End-to-end manual checklist + add one integration sanity test.

**Files:**
- Create: `Tests/CodexBarTests/Companion/CompanionIntegrationTests.swift`

- [ ] **Step 1: Write sanity integration test**

```swift
// Tests/CodexBarTests/Companion/CompanionIntegrationTests.swift
import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct CompanionIntegrationTests {
    @Test
    func `enabling and disabling rapidly does not crash`() async {
        let defaults = UserDefaults(suiteName: "Integration-\(UUID().uuidString)")!
        let settings = SettingsStore(userDefaults: defaults)
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        var controllers: [CompanionStatusItemController] = []
        for _ in 0..<5 {
            let c = CompanionStatusItemController(
                character: .catPixel, provider: .claude, usageStore: store,
                menuProvider: { NSMenu(title: "test") })
            c.start()
            c.stop()
            controllers.append(c)
        }
        #expect(controllers.allSatisfy { $0.statusItem == nil })
    }

    @Test
    func `all 4 characters can be rendered at each stage without throwing`() {
        for character in CompanionCharacter.allCases {
            for stage in CompanionPaceStage.allCases {
                let img = CompanionIconRenderer.render(character: character, stage: stage, phase: 0.5)
                #expect(img.size.width > 0)
            }
        }
    }
}
```

- [ ] **Step 2: Run test**

Run: `swift test --filter CompanionIntegrationTests`
Expected: PASS.

- [ ] **Step 3: Manual end-to-end checklist**

Build the full app + reinstall (CLAUDE.md flow):

```bash
./Scripts/build_for_distribution.sh
pkill -x CodexBar
rm -rf /Applications/ClCoBar.app
ditto -x -k dist/ClCoBar-1.3.0-arm64.zip /tmp/cb
mv /tmp/cb/ClCoBar.app /Applications/
xattr -dr com.apple.quarantine /Applications/ClCoBar.app
open /Applications/ClCoBar.app
```

Verify manually:
- [ ] 캐릭터 OFF (default) → 메뉴바에 캐릭터 안 보임
- [ ] Preferences → 표시 → "캐릭터" 섹션에 NEW 배지 보임
- [ ] 토글 ON → 메뉴바에 캐릭터 등장, 첫 토스트 표시
- [ ] 한 번 토글 → NEW 배지 사라짐
- [ ] 4종 캐릭터 picker로 전환 → 메뉴바 즉시 갱신
- [ ] Claude/Codex picker 전환 → 시계열 소스 교체 (Tooltip의 "Claude" → "Codex")
- [ ] 캐릭터 클릭 → 기존 ClCoBar 메뉴 표시 (Claude + Codex 카드)
- [ ] 캐릭터 호버 → tooltip 보임
- [ ] System Preferences → Reduce Motion ON → 캐릭터 idle 고정
- [ ] ⌘드래그로 캐릭터 위치 이동 → 재시작 후 위치 유지
- [ ] 캐릭터 OFF → 메뉴바에서 사라짐, 다른 ClCoBar pill은 그대로

- [ ] **Step 4: Commit**

```bash
git add Tests/CodexBarTests/Companion/CompanionIntegrationTests.swift
git commit -m "test(companion): integration sanity tests"
```

---

## Task 22: 배포 — version bump + docs + build

CLAUDE.md 버전 정책에 따라 MINOR 올림 (1.2.2 → 1.3.0).

**Files:**
- Modify: `version.env`
- Modify: `docs/install-guide-ko.md`
- Modify: `Scripts/install_for_team.sh`

- [ ] **Step 1: Bump version.env**

```bash
# Current values
cat version.env
# MARKETING_VERSION=1.2.2
# BUILD_NUMBER=70
```

Replace contents of `version.env`:

```
MARKETING_VERSION=1.3.0
BUILD_NUMBER=71
```

- [ ] **Step 2: Update install-guide-ko.md**

Open `docs/install-guide-ko.md`. Find references to the current version (e.g. `ClCoBar-1.2.2-arm64.zip`) and replace with `ClCoBar-1.3.0-arm64.zip`. Also update the "다음 버전 예시" — bump that one too (next would be 1.3.1).

Run: `grep -n "1.2.2\|1.2.1\|다음 버전" docs/install-guide-ko.md` and update each occurrence.

- [ ] **Step 3: Update install_for_team.sh**

Open `Scripts/install_for_team.sh`. Find the version in the usage comment (likely "ClCoBar-1.2.2-arm64.zip") and replace with `1.3.0`.

Run: `grep -n "1.2.2\|1.2.1" Scripts/install_for_team.sh` and update.

- [ ] **Step 4: Build distribution zip**

```bash
./Scripts/build_for_distribution.sh
ls dist/   # should see ClCoBar-1.3.0-arm64.zip
```

If `SKIP_TEST` is needed for CLI environments (no Xcode), use `SKIP_TEST=1 ./Scripts/build_for_distribution.sh`.

Expected: `dist/ClCoBar-1.3.0-arm64.zip` exists, swift tests pass (or skipped explicitly).

- [ ] **Step 5: Reinstall locally and final verification**

```bash
pkill -x CodexBar || true
rm -rf /Applications/ClCoBar.app
ditto -x -k dist/ClCoBar-1.3.0-arm64.zip /tmp/cb
mv /tmp/cb/ClCoBar.app /Applications/
xattr -dr com.apple.quarantine /Applications/ClCoBar.app
open /Applications/ClCoBar.app
```

- [ ] **Step 6: Remove previous-version zip (optional)**

```bash
rm -f dist/ClCoBar-1.2.2-arm64.zip
```

- [ ] **Step 7: Commit**

```bash
git add version.env docs/install-guide-ko.md Scripts/install_for_team.sh
git commit -m "chore(release): bump 1.2.2 → 1.3.0 (companion character feature)"
```

---

## Summary

22 tasks total. Phase grouping:

| Phase | Tasks | Output |
|---|---|---|
| 1. Core 모델 | 1-3 | `CodexBarCore/Companion/` — 6 files, fully unit-tested |
| 2. Sprite + Renderer | 4-9 | 4 characters × ~8 parts each, NSImage rendering with cache |
| 3. Animation Driver | 10 | DisplayLink wrap + phase progression |
| 4. StatusItem 통합 | 11, 13-14 | NSStatusItem lifecycle + observation wiring |
| 5. Settings + UI | 12, 15-17 | SettingsStore extension + Preferences section + preview |
| 6. 엣지케이스 | 18-20 | Reduce Motion + Localization + first-toggle toast |
| 7. 통합 + 배포 | 21-22 | Manual E2E + version bump 1.3.0 |

Each task is a self-contained commit. Total commits ≈ 22.

**Tests added:** 6 unit-test files (~30 tests) + 1 integration file.
**Files created:** 16 source files + 5 test files.
**Files modified:** 7 existing files (SettingsStoreState, SettingsStore, PreferencesDisplayPane, CodexbarApp/AppDelegate, StatusItemController, 2 Localizable.strings, version.env, install-guide, install_for_team.sh).
