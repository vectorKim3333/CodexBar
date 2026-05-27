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
