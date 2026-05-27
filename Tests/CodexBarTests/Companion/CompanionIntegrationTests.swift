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
                character: .dog, provider: .claude, usageStore: store,
                menuProvider: { NSMenu(title: "test") })
            c.start()
            c.stop()
            controllers.append(c)
        }
        #expect(controllers.allSatisfy { $0.statusItem == nil })
    }

    @Test
    func `all characters can be rendered at all frames without throwing`() {
        for character in CompanionCharacter.allCases {
            let frameCount = CompanionSpriteFrameRenderer.frameCount(for: character)
            #expect(frameCount > 0)
            for frameIndex in 0..<frameCount {
                let img = CompanionSpriteFrameRenderer.render(
                    character: character, frameIndex: frameIndex)
                #expect(img.size.width > 0)
            }
        }
    }
}
