// Sources/CodexBar/Companion/CompanionStatusItemController.swift
import AppKit
import CodexBarCore
import Foundation

@MainActor
final class CompanionStatusItemController {
    private(set) var statusItem: NSStatusItem?
    private let driver = CompanionAnimationDriver()
    private let menuProvider: () -> NSMenu

    var character: CompanionCharacter
    var provider: UsageProvider

    init(character: CompanionCharacter,
         provider: UsageProvider,
         menuProvider: @escaping () -> NSMenu)
    {
        self.character = character
        self.provider = provider
        self.menuProvider = menuProvider
    }

    func start() {
        guard self.statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.button?.image = CompanionIconRenderer.render(
            character: self.character, stage: .idle, phase: 0)
        item.button?.action = #selector(self.handleClick)
        item.button?.target = self
        item.menu = self.menuProvider()
        self.statusItem = item

        self.driver.onFrame = { [weak self] phase in
            guard let self, let item = self.statusItem else { return }
            item.button?.image = CompanionIconRenderer.render(
                character: self.character, stage: self.driver.stage, phase: phase)
        }
        self.driver.start()
    }

    func stop() {
        self.driver.stop()
        if let item = self.statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.statusItem = nil
    }

    @objc private func handleClick() {
        // Menu auto-shows because we assigned item.menu. No-op here.
    }
}
