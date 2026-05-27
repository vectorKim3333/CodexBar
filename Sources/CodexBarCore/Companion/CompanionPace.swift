import Foundation

public enum CompanionPace {
    /// 임계값은 시간당 % 기준으로 정의하고 내부 단위인 %/분으로 변환.
    /// 사용자가 직관적으로 이해하는 단위(시간당 %)에 맞춰 두는 게 향후 조정 용이.
    ///
    /// 5시간 세션 윈도우 기준이라 시간당 X% = "이 페이스 유지 시 (100/X)시간 만에 세션 100% 소진".
    ///
    /// idle:   [0,        0.6%/hr) — 사실상 정지 (기존 그대로)
    /// slow:   [0.6%/hr,  10%/hr)  — 1시간에 10% 미만, 가벼운 활동
    /// normal: [10%/hr,   20%/hr)  — 5시간에 50%~100% 페이스, 일상
    /// fast:   [20%/hr,   30%/hr)  — 5시간 안에 한도 도달 위험 구간
    /// burst:  [30%/hr,   ∞)       — 3시간 20분 내 한도 소진 페이스
    private static func perMin(perHour: Double) -> Double { perHour / 60.0 }

    private static let thresholds: [(stage: CompanionPaceStage, upper: Double)] = [
        (.idle,   Self.perMin(perHour: 0.6)),
        (.slow,   Self.perMin(perHour: 10.0)),
        (.normal, Self.perMin(perHour: 20.0)),
        (.fast,   Self.perMin(perHour: 30.0)),
        (.burst,  .infinity),
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
        case .idle:   return Self.perMin(perHour: 0.6)
        case .slow:   return Self.perMin(perHour: 10.0)
        case .normal: return Self.perMin(perHour: 20.0)
        case .fast:   return Self.perMin(perHour: 30.0)
        case .burst:  return .infinity
        }
    }

    private static func lowerThreshold(for stage: CompanionPaceStage) -> Double {
        switch stage {
        case .idle:   return 0
        case .slow:   return Self.perMin(perHour: 0.6)
        case .normal: return Self.perMin(perHour: 10.0)
        case .fast:   return Self.perMin(perHour: 20.0)
        case .burst:  return Self.perMin(perHour: 30.0)
        }
    }
}
