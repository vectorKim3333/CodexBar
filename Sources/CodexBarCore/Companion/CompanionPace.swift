import Foundation

public enum CompanionPace {
    /// Upper threshold for each stage (inclusive at lower bound).
    /// idle:   [0, 0.01)
    /// slow:   [0.01, 0.1)
    /// normal: [0.1, 1.0)
    /// fast:   [1.0, 5.0)
    /// burst:  [5.0, ∞)
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
        case .idle:   return 0
        case .slow:   return 1
        case .normal: return 2
        case .fast:   return 3
        case .burst:  return 4
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
