// Sources/CodexBar/Companion/CompanionMenuBuilder.swift
import AppKit
import CodexBarCore
import Foundation

@MainActor
final class CompanionMenuBuilder: NSObject, NSMenuDelegate {
    private weak var controller: CompanionStatusItemController?
    private let settings: SettingsStore

    init(controller: CompanionStatusItemController, settings: SettingsStore) {
        self.controller = controller
        self.settings = settings
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Companion")
        menu.autoenablesItems = false
        menu.delegate = self
        self.populate(menu)
        return menu
    }

    @MainActor func menuNeedsUpdate(_ menu: NSMenu) {
        self.populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let controller = self.controller else { return }

        // Header
        let providerName = controller.provider == .claude ? "Claude" : "Codex"
        let header = NSMenuItem(title: "🐱 \(providerName) Companion", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // State + burn rate
        let stage = controller.currentStage
        let stageStr = self.stageName(stage)
        let burnStr: String
        if stage == .idle {
            burnStr = L("companion.menu.idle")
        } else {
            burnStr = String(format: "%@ · %.2f %%/분", stageStr, controller.currentBurnRate)
        }
        let stateItem = NSMenuItem(title: burnStr, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        // Last sample time
        let timeStr: String
        if let lastAt = controller.lastSampleAt {
            timeStr = self.formatElapsed(Date().timeIntervalSince(lastAt))
        } else {
            timeStr = L("companion.menu.no_sample")
        }
        let timeItem = NSMenuItem(
            title: "기준시간: \(timeStr)",
            action: nil,
            keyEquivalent: "")
        timeItem.isEnabled = false
        menu.addItem(timeItem)

        menu.addItem(NSMenuItem.separator())

        // Character picker
        let charHeader = NSMenuItem(
            title: L("companion.menu.character_section"),
            action: nil,
            keyEquivalent: "")
        charHeader.isEnabled = false
        menu.addItem(charHeader)
        for character in CompanionCharacter.allCases {
            let label = self.characterLabel(character)
            let item = NSMenuItem(
                title: label,
                action: #selector(self.selectCharacter(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = character
            item.state = (self.settings.companionCharacter == character) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Provider picker
        let provHeader = NSMenuItem(
            title: L("companion.menu.provider_section"),
            action: nil,
            keyEquivalent: "")
        provHeader.isEnabled = false
        menu.addItem(provHeader)
        for prov in [UsageProvider.claude, .codex] {
            let item = NSMenuItem(
                title: prov == .claude ? "Claude" : "Codex",
                action: #selector(self.selectProvider(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = prov
            item.state = (self.settings.companionProvider == prov) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefs = NSMenuItem(
            title: L("companion.menu.preferences"),
            action: #selector(self.openPreferences),
            keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        // Quit
        let quit = NSMenuItem(
            title: L("companion.menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let character = sender.representedObject as? CompanionCharacter else { return }
        self.settings.companionCharacter = character
        // Apply immediately to live controller (settings observation has ~500ms lag)
        self.controller?.character = character
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let prov = sender.representedObject as? UsageProvider else { return }
        self.settings.companionProvider = prov
        self.controller?.provider = prov
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .codexbarOpenSettings,
            object: nil,
            userInfo: ["tab": PreferencesTab.display.rawValue])
    }

    private func characterLabel(_ c: CompanionCharacter) -> String {
        switch c {
        case .catPixel: return L("companion.character.catPixel")
        case .catLine:  return L("companion.character.catLine")
        case .dogPixel: return L("companion.character.dogPixel")
        case .dogLine:  return L("companion.character.dogLine")
        }
    }

    private func stageName(_ s: CompanionPaceStage) -> String {
        switch s {
        case .idle:   return L("companion.stage.idle")
        case .slow:   return L("companion.stage.slow")
        case .normal: return L("companion.stage.normal")
        case .fast:   return L("companion.stage.fast")
        case .burst:  return L("companion.stage.burst")
        }
    }

    /// Returns Korean relative time: "방금 전", "N초 전", "N분 전", "N시간 전".
    private func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 30 { return L("companion.menu.just_now") }
        if seconds < 60 { return L("companion.menu.seconds_ago", Int(seconds)) }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return L("companion.menu.minutes_ago", minutes) }
        let hours = minutes / 60
        return L("companion.menu.hours_ago", hours)
    }
}
