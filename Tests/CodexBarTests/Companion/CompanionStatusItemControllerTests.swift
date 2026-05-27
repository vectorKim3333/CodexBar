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
            character: .catPixel,
            provider: .claude,
            usageStore: store,
            menuProvider: { NSMenu(title: "test") })
        #expect(controller.statusItem == nil)
        controller.start()
        #expect(controller.statusItem != nil)
        controller.stop()
        #expect(controller.statusItem == nil)
    }

    private static func makeTestUsageStore() -> UsageStore {
        let defaults = UserDefaults(suiteName: "WireTest-\(UUID().uuidString)")!
        let settings = SettingsStore(userDefaults: defaults)
        let fetcher = UsageFetcher()
        return UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
    }
}
