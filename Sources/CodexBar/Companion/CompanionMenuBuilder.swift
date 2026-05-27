// Sources/CodexBar/Companion/CompanionMenuBuilder.swift
import AppKit
import CodexBarCore
import Foundation

@MainActor
final class CompanionMenuBuilder: NSObject, NSMenuDelegate {
    private weak var controller: CompanionStatusItemController?
    private let settings: SettingsStore
    private let usageStore: UsageStore

    init(controller: CompanionStatusItemController,
         settings: SettingsStore,
         usageStore: UsageStore)
    {
        self.controller = controller
        self.settings = settings
        self.usageStore = usageStore
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

        let providerName = controller.provider == .claude ? "Claude" : "Codex"

        // 1) Header
        let headerText = "🐱 \(providerName) Companion"
        let header = NSMenuItem(title: headerText, action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: headerText,
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
            ])
        menu.addItem(header)

        // 2) State line (stage + hourly %)
        let stateLine = self.composeStateLine(
            stage: controller.currentStage,
            burnPerMinute: controller.currentBurnRate)
        let stateItem = NSMenuItem(title: stateLine, action: nil, keyEquivalent: "")
        menu.addItem(stateItem)

        // 3) 기준시간 — based on UsageStore snapshot freshness, not our local poll
        let snapshot = self.usageStore.snapshots[controller.provider]
        let timeStr: String
        if let updatedAt = snapshot?.updatedAt {
            timeStr = self.formatSnapshotTime(updatedAt)
        } else {
            timeStr = L("companion.menu.no_sample")
        }
        let timeItem = NSMenuItem(title: "기준시간: \(timeStr)", action: nil, keyEquivalent: "")
        menu.addItem(timeItem)

        // 4) Detail block (session % / weekly / today tokens / top model)
        let tokenSnapshot = self.usageStore.tokenSnapshots[controller.provider]
        let detailLines = self.composeDetailLines(snapshot: snapshot, tokenSnapshot: tokenSnapshot)
        if !detailLines.isEmpty {
            menu.addItem(.separator())
            for line in detailLines {
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // 5) Character picker
        let charHeader = NSMenuItem.sectionHeader(title: L("companion.menu.character_section"))
        menu.addItem(charHeader)
        for character in CompanionCharacter.allCases {
            let item = NSMenuItem(title: self.characterLabel(character),
                                  action: #selector(self.selectCharacter(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = character
            item.state = (self.settings.companionCharacter == character) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // 6) Provider picker
        let provHeader = NSMenuItem.sectionHeader(title: L("companion.menu.provider_section"))
        menu.addItem(provHeader)
        for prov in [UsageProvider.claude, .codex] {
            let item = NSMenuItem(title: prov == .claude ? "Claude" : "Codex",
                                  action: #selector(self.selectProvider(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = prov
            item.state = (self.settings.companionProvider == prov) ? .on : .off
            menu.addItem(item)
        }

        // Update available — shown only when a newer version is on main branch
        if UpdateChecker.shared.hasUpdate, let latest = UpdateChecker.shared.latestVersion {
            menu.addItem(.separator())
            let text = String(format: L("companion.menu.update_available"), latest)
            let updateItem = NSMenuItem(
                title: text,
                action: #selector(UpdateChecker.shared.openInstallGuide),
                keyEquivalent: "")
            updateItem.target = UpdateChecker.shared
            updateItem.attributedTitle = NSAttributedString(
                string: text,
                attributes: [
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                ])
            menu.addItem(updateItem)
        }

        menu.addItem(.separator())

        // 7) Preferences + Quit
        let prefs = NSMenuItem(title: L("companion.menu.preferences"),
                               action: #selector(self.openPreferences),
                               keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let quit = NSMenuItem(title: L("companion.menu.quit"),
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func composeStateLine(stage: CompanionPaceStage,
                                  burnPerMinute: Double) -> String {
        if stage == .idle {
            return L("companion.menu.idle")
        }
        let stageStr = self.stageName(stage)
        let hourly = burnPerMinute * 60.0
        let parts: [String] = [stageStr, String(format: L("companion.menu.hourly_pct"), hourly)]
        return parts.joined(separator: " · ")
    }

    private func composeDetailLines(snapshot: UsageSnapshot?,
                                    tokenSnapshot: CostUsageTokenSnapshot?) -> [String] {
        var lines: [String] = []

        // Session (primary) — 5h window
        if let primary = snapshot?.primary {
            let pct = Int(primary.usedPercent.rounded())
            if let resetsAt = primary.resetsAt {
                let remaining = resetsAt.timeIntervalSince(Date())
                let resetStr = Self.formatDuration(remaining)
                lines.append(String(format: L("companion.menu.session_with_reset"), pct, resetStr))
            } else {
                lines.append(String(format: L("companion.menu.session_pct"), pct))
            }
        }

        // Weekly (secondary)
        if let secondary = snapshot?.secondary {
            let pct = Int(secondary.usedPercent.rounded())
            lines.append(String(format: L("companion.menu.weekly_pct"), pct))
        }

        // Today's tokens + cost
        if let token = tokenSnapshot, let tokens = token.sessionTokens, tokens > 0 {
            if let cost = token.sessionCostUSD {
                lines.append(String(format: L("companion.menu.today_tokens_cost"),
                                    Self.formatTokens(Double(tokens)), cost))
            } else {
                lines.append(String(format: L("companion.menu.today_tokens"),
                                    Self.formatTokens(Double(tokens))))
            }
        }

        // Top model (from today's daily entry)
        if let topModel = Self.topModelName(from: tokenSnapshot) {
            lines.append(String(format: L("companion.menu.top_model"),
                                Self.shortModelName(topModel)))
        }

        return lines
    }

    private static func topModelName(from snapshot: CostUsageTokenSnapshot?) -> String? {
        guard let entries = snapshot?.daily, let today = entries.first else { return nil }
        guard let models = today.modelBreakdowns, !models.isEmpty else { return nil }
        let top = models.max { (a, b) in (a.costUSD ?? 0) < (b.costUSD ?? 0) }
        return top?.modelName
    }

    /// Returns "32k" / "1.2M" / "123" — Korean-friendly compact format.
    private static func formatTokens(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fk", value / 1_000) }
        return String(format: "%.0f", value)
    }

    /// "1h 23m" / "45m" / "1d" — used for reset countdown.
    private static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 0 { return "0m" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (24 * 60)
        if days >= 1 { return "\(days)d" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 1 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Shortens a Claude model ID to a human-readable name.
    /// e.g. "claude-opus-4-7" -> "Opus 4.7"
    ///      "claude-sonnet-4-6" -> "Sonnet 4.6"
    ///      "claude-haiku-4-5-20251001" -> "Haiku 4.5"
    private static func shortModelName(_ raw: String) -> String {
        let lower = raw.lowercased()
        let families: [(needle: String, pretty: String)] = [
            ("opus", "Opus"),
            ("sonnet", "Sonnet"),
            ("haiku", "Haiku"),
        ]
        for (needle, pretty) in families {
            guard lower.contains(needle) else { continue }
            let tokens = lower.split(separator: "-").map(String.init)
            guard let idx = tokens.firstIndex(of: needle) else { continue }
            var versionParts: [String] = []
            var i = idx + 1
            while i < tokens.count, let _ = Int(tokens[i]) {
                versionParts.append(tokens[i])
                i += 1
            }
            if versionParts.isEmpty {
                return pretty
            }
            let trimmed = Array(versionParts.prefix(2))
            return "\(pretty) \(trimmed.joined(separator: "."))"
        }
        return raw
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

    /// "HH:mm · X분 전" or "HH:mm · X일 전" for older.
    /// Uses system locale for time format (so user's 24h/12h preference is respected).
    private func formatSnapshotTime(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        let absoluteStr = Self.snapshotTimeFormatter.string(from: date)
        let relativeStr = self.formatElapsed(elapsed)
        return "\(absoluteStr) · \(relativeStr)"
    }

    private static let snapshotTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        f.locale = Locale.autoupdatingCurrent
        return f
    }()

    /// Returns relative time: "방금 전", "N초 전", "N분 전", "N시간 전", "N일 전".
    private func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 30 { return L("companion.menu.just_now") }
        if seconds < 60 { return L("companion.menu.seconds_ago", Int(seconds)) }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return L("companion.menu.minutes_ago", minutes) }
        let hours = minutes / 60
        if hours < 24 { return L("companion.menu.hours_ago", hours) }
        let days = hours / 24
        return L("companion.menu.days_ago", days)
    }
}
