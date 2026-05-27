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
