import Foundation
import Testing
@testable import CodexBar

struct MenuBarVisibilityWatcherTests {
    @Test
    func `does not flag intentionally hidden status item`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 0)

        #expect(!MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func `flags visible item without attached window`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func `flags visible item without button`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: false,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 0)

        #expect(MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func `flags visible item with zero width`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 0)

        #expect(MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func `allows visible item attached to a screen with width`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func `flags visible item attached to a detached screen`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    // MARK: - RecoveryAction (1.8.0)

    @Test
    func `recovery action is none for healthy visible item`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true, hasButton: true, hasWindow: true, hasScreen: true, buttonWidth: 18)
        #expect(MenuBarVisibilityWatcher.recoveryAction(snapshot: snapshot) == .none)
    }

    @Test
    func `recovery action reasserts visibility for hidden item`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: false, hasButton: true, hasWindow: true, hasScreen: true, buttonWidth: 18)
        #expect(MenuBarVisibilityWatcher.recoveryAction(snapshot: snapshot) == .reassertVisible)
    }

    @Test
    func `recovery action is non-destructive redraw for overflow-hidden item`() {
        // window 살아있음 + width=0 = overflow-hide. recreate 가 아니라 비파괴 redraw 여야 한다.
        // 이게 1.5.5~1.7.2 race 의 핵심 수정: 이 케이스에 removeStatusItem 을 쓰지 않는다.
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true, hasButton: true, hasWindow: true, hasScreen: true, buttonWidth: 0)
        #expect(MenuBarVisibilityWatcher.recoveryAction(snapshot: snapshot) == .redraw)
    }

    @Test
    func `recovery action is redraw for visible item with broken image`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true, hasButton: true, hasWindow: true, hasScreen: true,
            buttonWidth: 18, hasImage: false)
        #expect(MenuBarVisibilityWatcher.recoveryAction(snapshot: snapshot) == .redraw)
    }

    @Test
    func `recovery action recreates evicted item without window`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true, hasButton: true, hasWindow: false, hasScreen: false, buttonWidth: 18)
        #expect(MenuBarVisibilityWatcher.recoveryAction(snapshot: snapshot) == .recreate)
    }

    @Test
    func `recovery action recreates evicted item on detached screen`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true, hasButton: true, hasWindow: true, hasScreen: true,
            isOnCurrentScreen: false, buttonWidth: 18)
        #expect(MenuBarVisibilityWatcher.recoveryAction(snapshot: snapshot) == .recreate)
    }

    @Test
    func `recovery action recreates item without button`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true, hasButton: false, hasWindow: false, hasScreen: false, buttonWidth: 0)
        #expect(MenuBarVisibilityWatcher.recoveryAction(snapshot: snapshot) == .recreate)
    }

    @Test
    func `guidance shows once then repeats after a day`() throws {
        let defaults = try #require(UserDefaults(suiteName: "MenuBarVisibilityWatcherTests"))
        defaults.removePersistentDomain(forName: "MenuBarVisibilityWatcherTests")
        let now = Date(timeIntervalSince1970: 1000)

        #expect(MenuBarVisibilityWatcher.shouldShowGuidance(defaults: defaults, now: now))

        MenuBarVisibilityWatcher.markGuidanceShown(defaults: defaults, now: now)

        #expect(!MenuBarVisibilityWatcher.shouldShowGuidance(
            defaults: defaults,
            now: now.addingTimeInterval(MenuBarVisibilityWatcher.guidanceRepeatInterval - 1)))
        #expect(MenuBarVisibilityWatcher.shouldShowGuidance(
            defaults: defaults,
            now: now.addingTimeInterval(MenuBarVisibilityWatcher.guidanceRepeatInterval)))
    }

    @Test
    func `startup recovery triggers for blocked visible snapshot`() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [blocked]))
    }

    @Test
    func `startup recovery triggers when one split status item is blocked`() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let healthy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [healthy, blocked]))
    }

    @Test
    func `startup recovery ignores stale checks`() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(MenuBarVisibilityWatcher.startupFreshnessInterval + 1),
            snapshots: [blocked]))
    }

    @Test
    func `startup recovery ignores healthy visible snapshot`() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let healthy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [healthy]))
    }

    @Test
    func `screen change recovery triggers when a display is removed with visible status item`() {
        let healthy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldAttemptScreenChangeRecovery(
            previousScreenCount: 2,
            currentScreenCount: 1,
            snapshots: [healthy]))
    }

    @Test
    func `screen change recovery ignores display removal when no status item is visible`() {
        let hidden = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptScreenChangeRecovery(
            previousScreenCount: 2,
            currentScreenCount: 1,
            snapshots: [hidden]))
    }

    @Test
    func `screen change recovery triggers for blocked status item without display count change`() {
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldAttemptScreenChangeRecovery(
            previousScreenCount: 1,
            currentScreenCount: 1,
            snapshots: [blocked]))
    }

    @Test
    func `screen change recovery ignores healthy item when display count does not shrink`() {
        let healthy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptScreenChangeRecovery(
            previousScreenCount: 1,
            currentScreenCount: 2,
            snapshots: [healthy]))
    }
}
