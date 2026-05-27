// Tests/CodexBarTests/Companion/CompanionStatusItemControllerTests.swift
import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct CompanionStatusItemControllerTests {
    @Test
    func `start creates status item, stop releases it`() {
        let controller = CompanionStatusItemController(
            character: .catPixel,
            provider: .claude,
            menuProvider: { NSMenu(title: "test") })
        #expect(controller.statusItem == nil)
        controller.start()
        #expect(controller.statusItem != nil)
        controller.stop()
        #expect(controller.statusItem == nil)
    }
}
