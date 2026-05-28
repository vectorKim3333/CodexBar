import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CompanionStatusItemControllerTests {
    @Test
    func `start creates status item, stop releases it`() {
        let store = Self.makeTestUsageStore()
        let controller = CompanionStatusItemController(
            character: .dog,
            provider: .claude,
            usageStore: store,
            menuProvider: { NSMenu(title: "test") })
        #expect(controller.statusItem == nil)
        controller.start()
        #expect(controller.statusItem != nil)
        controller.stop()
        #expect(controller.statusItem == nil)
    }

    /// 1.5.5: setVisible 은 instance lifecycle 안 건드림. isVisible 만 토글해서
    /// macOS status bar 의 add/remove race 회피.
    @Test
    func `setVisible toggles isVisible without destroying status item instance`() {
        let store = Self.makeTestUsageStore()
        let controller = CompanionStatusItemController(
            character: .dog,
            provider: .claude,
            usageStore: store,
            menuProvider: { NSMenu(title: "test") })
        controller.start()
        let originalItem = controller.statusItem
        #expect(originalItem != nil)

        controller.setVisible(false)
        #expect(controller.statusItem === originalItem)        // 같은 instance
        #expect(controller.statusItem?.isVisible == false)

        controller.setVisible(true)
        #expect(controller.statusItem === originalItem)        // 여전히 같은 instance
        #expect(controller.statusItem?.isVisible == true)

        controller.stop()
    }

    private static func makeTestUsageStore() -> UsageStore {
        let defaults = UserDefaults(suiteName: "WireTest-\(UUID().uuidString)")!
        let settings = SettingsStore(userDefaults: defaults)
        let fetcher = UsageFetcher()
        return UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
    }
}
