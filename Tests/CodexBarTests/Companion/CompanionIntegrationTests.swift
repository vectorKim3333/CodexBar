// Tests/CodexBarTests/Companion/CompanionIntegrationTests.swift
import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CompanionIntegrationTests {
    @Test
    func `enabling and disabling rapidly does not crash`() async {
        let defaults = UserDefaults(suiteName: "Integration-\(UUID().uuidString)")!
        let settings = SettingsStore(userDefaults: defaults)
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        var controllers: [CompanionStatusItemController] = []
        for _ in 0..<5 {
            let c = CompanionStatusItemController(
                character: .catPixel, provider: .claude, usageStore: store,
                menuProvider: { NSMenu(title: "test") })
            c.start()
            c.stop()
            controllers.append(c)
        }
        #expect(controllers.allSatisfy { $0.statusItem == nil })
    }

    @Test
    func `all 4 characters can be rendered at each stage without throwing`() {
        for character in CompanionCharacter.allCases {
            for stage in CompanionPaceStage.allCases {
                let img = CompanionIconRenderer.render(character: character, stage: stage, phase: 0.5)
                #expect(img.size.width > 0)
            }
        }
    }
}
