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
    func returnsZeroWhenFewerThan2Samples() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 1.0)
        let now = Date()
        let burn = await calc.update(entries: [entry(0, percent: 10, now: now)], now: now)
        #expect(burn == 0)
    }

    @Test
    func computesPositiveBurnForUsageIncrease() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 1.0)
        let now = Date()
        let entries = [entry(5, percent: 10, now: now), entry(0, percent: 12, now: now)]
        let burn = await calc.update(entries: entries, now: now)
        // 2% over 5 min = 0.4 %/min
        #expect(abs(burn - 0.4) < 0.001)
    }

    @Test
    func clampsNegativeBurnToZeroPostReset() async {
        let calc = BurnRateCalculator(window: 300, smoothingAlpha: 1.0)
        let now = Date()
        let entries = [entry(5, percent: 80, now: now), entry(0, percent: 5, now: now)]
        let burn = await calc.update(entries: entries, now: now)
        #expect(burn == 0)
    }

    @Test
    func respectsWindowIgnoresSamplesOlderThanWindow() async {
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
    func EMASmoothedBurnRateOverSuccessiveUpdates() async {
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
    func freezePreservesLastValueAcrossUpdate() async {
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
