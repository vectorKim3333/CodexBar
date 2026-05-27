import CodexBarCore
import Testing

struct CompanionPaceTests {
    /// 새 임계값 (시간당 %) — 테스트에서는 %/min 으로 환산해서 사용.
    /// idle:   [0,     0.6/60)  ≒ [0,     0.01)
    /// slow:   [0.6/60, 10/60)  ≒ [0.01,  0.1667)
    /// normal: [10/60,  20/60)  ≒ [0.1667, 0.3333)
    /// fast:   [20/60,  30/60)  ≒ [0.3333, 0.5)
    /// burst:  [30/60,  ∞)      ≒ [0.5,    ∞)
    private static func perMin(_ perHour: Double) -> Double { perHour / 60.0 }

    @Test
    func `classifies idle at 0`() {
        let s = CompanionPace.classify(burnRate: 0, previous: nil, timeSinceLastChange: 999)
        #expect(s == .idle)
    }

    @Test
    func `classifies burst above 30 per hour`() {
        let s = CompanionPace.classify(burnRate: Self.perMin(40), previous: nil, timeSinceLastChange: 999)
        #expect(s == .burst)
    }

    @Test
    func `classifies each band at midpoint`() {
        // idle (<0.6%/hr), slow (0.6~10%/hr), normal (10~20%/hr), fast (20~30%/hr), burst (≥30%/hr)
        #expect(CompanionPace.classify(burnRate: Self.perMin(0.3), previous: nil, timeSinceLastChange: 999) == .idle)
        #expect(CompanionPace.classify(burnRate: Self.perMin(5),   previous: nil, timeSinceLastChange: 999) == .slow)
        #expect(CompanionPace.classify(burnRate: Self.perMin(15),  previous: nil, timeSinceLastChange: 999) == .normal)
        #expect(CompanionPace.classify(burnRate: Self.perMin(25),  previous: nil, timeSinceLastChange: 999) == .fast)
        #expect(CompanionPace.classify(burnRate: Self.perMin(40),  previous: nil, timeSinceLastChange: 999) == .burst)
    }

    @Test
    func `hysteresis keeps current stage in deadband`() {
        // normal upper = 20%/hr. ±20% deadband = 16~24%/hr.
        // 19%/hr 은 upper 보다 살짝 아래지만 deadband 안 → normal 유지.
        let s = CompanionPace.classify(
            burnRate: Self.perMin(19), previous: .normal, timeSinceLastChange: 999)
        #expect(s == .normal)
    }

    @Test
    func `hysteresis allows transition past deadband`() {
        // 5%/hr 은 slow 영역 (deadband 밖) → slow 로 떨어짐.
        let s = CompanionPace.classify(
            burnRate: Self.perMin(5), previous: .normal, timeSinceLastChange: 999)
        #expect(s == .slow)
    }

    @Test
    func `3s hold rule prevents rapid toggling`() {
        // 직전에 normal 이었고 burn 이 idle 영역. timeSinceLastChange 2초라 hold.
        let s = CompanionPace.classify(
            burnRate: Self.perMin(0.05), previous: .normal, timeSinceLastChange: 2)
        #expect(s == .normal)
    }

    @Test
    func `3s hold rule releases after 3s`() {
        let s = CompanionPace.classify(
            burnRate: Self.perMin(0.05), previous: .normal, timeSinceLastChange: 4)
        #expect(s == .idle)
    }

    @Test
    func `previous nil treats as initial classification`() {
        let s = CompanionPace.classify(
            burnRate: Self.perMin(15), previous: nil, timeSinceLastChange: 0)
        #expect(s == .normal)
    }
}
