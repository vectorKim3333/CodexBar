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
    func `configure sets frame count`() {
        let driver = CompanionAnimationDriver()
        driver.configure(frameCount: 5)
        // frameCount 자체는 private 이지만, idle 상태에선 frame 0 으로 reset 되는 게
        // applyStageChange 의 인variant 이므로 외부 관찰 가능.
        driver.stage = .idle
        #expect(driver.frameIndex == 0)
    }

    @Test
    func `idle stage keeps frame index at 0`() {
        let driver = CompanionAnimationDriver()
        driver.configure(frameCount: 5)
        driver.stage = .idle
        driver.start()
        #expect(driver.frameIndex == 0)
    }
}
