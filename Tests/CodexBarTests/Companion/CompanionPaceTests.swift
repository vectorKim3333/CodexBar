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
