import AppKit
import Foundation

struct StatusItemVisibilitySnapshot: Equatable {
    let isVisible: Bool
    let hasButton: Bool
    let hasWindow: Bool
    let hasScreen: Bool
    let isOnCurrentScreen: Bool
    let buttonWidth: CGFloat
    /// 1.5.7: button.image 가 non-nil + zero-size 아닌지. macOS 가 image 가 깨진
    /// 상태의 NSStatusItem 을 자동 hide 시키는 케이스 (사용자 보고: 절전 없이 갑자기
    /// 사라짐) 감지용.
    let hasImage: Bool

    init(
        isVisible: Bool,
        hasButton: Bool,
        hasWindow: Bool,
        hasScreen: Bool,
        isOnCurrentScreen: Bool = true,
        buttonWidth: CGFloat,
        hasImage: Bool = true)
    {
        self.isVisible = isVisible
        self.hasButton = hasButton
        self.hasWindow = hasWindow
        self.hasScreen = hasScreen
        self.isOnCurrentScreen = isOnCurrentScreen
        self.buttonWidth = buttonWidth
        self.hasImage = hasImage
    }
}

extension StatusItemVisibilitySnapshot: CustomStringConvertible {
    var description: String {
        "visible=\(self.isVisible),button=\(self.hasButton),window=\(self.hasWindow),"
            + "screen=\(self.hasScreen),currentScreen=\(self.isOnCurrentScreen),"
            + "width=\(String(format: "%.1f", Double(self.buttonWidth)))"
    }
}

@MainActor
func isStatusItemBlocked(_ item: NSStatusItem) -> Bool {
    MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: MenuBarVisibilityWatcher.visibilitySnapshot(item))
}

enum MenuBarVisibilityWatcher {
    static let guidanceShownKey = "hasShownTahoeAllowListGuidance"
    static let guidanceLastShownAtKey = "tahoeAllowListGuidanceLastShownAt"
    static let guidanceRepeatInterval: TimeInterval = 24 * 60 * 60
    static let startupFreshnessInterval: TimeInterval = 10
    static let startupCheckDelay: TimeInterval = 2
    /// wake 직후 AppKit / WindowServer 가 메뉴바를 다시 그릴 시간을 준 뒤 blocked 감지.
    /// 너무 짧으면 false-positive(아직 미복원), 너무 길면 사용자가 빈 메뉴바를 오래 봄.
    static let wakeCheckDelay: TimeInterval = 1.5
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.MenuBarSettings")!

    @MainActor
    static func visibilitySnapshot(_ item: NSStatusItem) -> StatusItemVisibilitySnapshot {
        let screen = item.button?.window?.screen
        let image = item.button?.image
        let hasImage = image != nil && (image?.size.width ?? 0) > 0 && (image?.size.height ?? 0) > 0
        return StatusItemVisibilitySnapshot(
            isVisible: item.isVisible,
            hasButton: item.button != nil,
            hasWindow: item.button?.window != nil,
            hasScreen: screen != nil,
            isOnCurrentScreen: screen.map(self.isCurrentScreen) ?? false,
            buttonWidth: item.button?.frame.size.width ?? 0,
            hasImage: hasImage)
    }

    @MainActor
    private static func isCurrentScreen(_ screen: NSScreen) -> Bool {
        let screenNumber = self.screenNumber(screen)
        return NSScreen.screens.contains { candidate in
            if let screenNumber, let candidateNumber = self.screenNumber(candidate) {
                return candidateNumber == screenNumber
            }
            return candidate === screen
        }
    }

    private static func screenNumber(_ screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    static func isBlockedSnapshot(snapshot: StatusItemVisibilitySnapshot) -> Bool {
        guard snapshot.isVisible else { return false }
        guard snapshot.hasButton else { return true }
        // 1.5.4: `buttonWidth <= 0` false-positive 제거 (신생 status item 의 width=0 정상 상태).
        // 1.5.7: `hasImage` 추가 — macOS 가 button.image 가 nil/zero-size 인 status item 을
        // 자동 hide 시켜 사용량 pill 이 사라지는 케이스 (절전 없이 갑자기 사라짐) 감지.
        return !snapshot.hasWindow || !snapshot.hasScreen
            || !snapshot.isOnCurrentScreen || !snapshot.hasImage
    }

    static func hasBlockedVisibleSnapshots(_ snapshots: [StatusItemVisibilitySnapshot]) -> Bool {
        let visibleItems = snapshots.filter(\.isVisible)
        guard !visibleItems.isEmpty else { return false }
        return visibleItems.allSatisfy { snapshot in
            self.isBlockedSnapshot(snapshot: snapshot)
        }
    }

    static func hasAnyBlockedVisibleSnapshot(_ snapshots: [StatusItemVisibilitySnapshot]) -> Bool {
        snapshots.contains { snapshot in
            snapshot.isVisible && self.isBlockedSnapshot(snapshot: snapshot)
        }
    }

    @MainActor
    static func visibilitySnapshots(_ items: [NSStatusItem]) -> [StatusItemVisibilitySnapshot] {
        items.map { item in
            self.visibilitySnapshot(item)
        }
    }

    @MainActor
    static func hasBlockedVisibleStatusItems(_ items: [NSStatusItem]) -> Bool {
        self.hasBlockedVisibleSnapshots(self.visibilitySnapshots(items))
    }

    static func shouldAttemptStartupRecovery(
        appLaunchedAt: Date,
        now: Date = Date(),
        snapshots: [StatusItemVisibilitySnapshot])
        -> Bool
    {
        guard now.timeIntervalSince(appLaunchedAt) <= self.startupFreshnessInterval else { return false }
        return self.hasAnyBlockedVisibleSnapshot(snapshots)
    }

    static func shouldAttemptScreenChangeRecovery(
        previousScreenCount: Int,
        currentScreenCount: Int,
        snapshots: [StatusItemVisibilitySnapshot])
        -> Bool
    {
        if self.hasAnyBlockedVisibleSnapshot(snapshots) {
            return true
        }
        guard currentScreenCount < previousScreenCount else { return false }
        return snapshots.contains { snapshot in
            snapshot.isVisible
        }
    }

    static func shouldShowGuidance(defaults: UserDefaults, now: Date = Date()) -> Bool {
        guard defaults.bool(forKey: self.guidanceShownKey) else { return true }
        let lastShownAt = defaults.double(forKey: self.guidanceLastShownAtKey)
        guard lastShownAt > 0 else { return false }
        return now.timeIntervalSince1970 - lastShownAt >= self.guidanceRepeatInterval
    }

    static func markGuidanceShown(defaults: UserDefaults, now: Date = Date()) {
        defaults.set(true, forKey: self.guidanceShownKey)
        defaults.set(now.timeIntervalSince1970, forKey: self.guidanceLastShownAtKey)
    }

    @MainActor
    static func presentGuidance(
        defaults: UserDefaults,
        now: Date = Date(),
        openURL: (URL) -> Void = { NSWorkspace.shared.open($0) })
    {
        self.markGuidanceShown(defaults: defaults, now: now)

        let alert = NSAlert()
        alert.messageText = L("CodexBar can't show its menu bar icon")
        alert.informativeText = L(
            "macOS Tahoe can block menu bar apps in System Settings → Menu Bar → Allow in the Menu Bar. "
                + "CodexBar is running, but macOS may be hiding its icon. Open Menu Bar settings and turn CodexBar on.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Open Menu Bar Settings"))
        alert.addButton(withTitle: L("Dismiss"))

        if alert.runModal() == .alertFirstButtonReturn {
            openURL(self.settingsURL)
        }
    }
}

extension StatusItemController {
    func scheduleStartupStatusItemVisibilityCheck(appLaunchedAt: Date = Date()) {
        guard !SettingsStore.isRunningTests else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + MenuBarVisibilityWatcher.startupCheckDelay) { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkStartupStatusItemVisibility(appLaunchedAt: appLaunchedAt)
            }
        }
    }

    private func checkStartupStatusItemVisibility(appLaunchedAt: Date, now: Date = Date()) {
        let snapshots = MenuBarVisibilityWatcher.visibilitySnapshots(self.startupVisibilityStatusItems)
        guard MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: appLaunchedAt,
            now: now,
            snapshots: snapshots)
        else {
            return
        }

        self.menuLogger.error(
            "Status item failed to materialize; recreating status items",
            metadata: ["snapshots": snapshots.map(\.description).joined(separator: " | ")])
        self.recreateStatusItemsForVisibilityRecovery()

        let recoveredSnapshots = MenuBarVisibilityWatcher.visibilitySnapshots(self.startupVisibilityStatusItems)
        guard MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: appLaunchedAt,
            now: now,
            snapshots: recoveredSnapshots)
        else {
            self.menuLogger.info(
                "Status item materialized after recreation",
                metadata: ["snapshots": recoveredSnapshots.map(\.description).joined(separator: " | ")])
            return
        }

        self.menuLogger.error(
            "Status item still failed to materialize after recreation",
            metadata: ["snapshots": recoveredSnapshots.map(\.description).joined(separator: " | ")])
        guard #available(macOS 26.0, *),
              MenuBarVisibilityWatcher.shouldShowGuidance(defaults: self.settings.userDefaults, now: now)
        else {
            return
        }
        MenuBarVisibilityWatcher.presentGuidance(defaults: self.settings.userDefaults, now: now)
    }

    @objc func handleScreenParametersDidChange(_: Notification) {
        let previousScreenCount = max(
            self.pendingScreenChangePreviousCount ?? self.lastKnownScreenCount,
            self.lastKnownScreenCount)
        let currentScreenCount = NSScreen.screens.count
        self.pendingScreenChangePreviousCount = previousScreenCount
        self.lastKnownScreenCount = currentScreenCount
        self.scheduleScreenChangeStatusItemVisibilityCheck(
            previousScreenCount: previousScreenCount,
            currentScreenCount: currentScreenCount)
    }

    private func scheduleScreenChangeStatusItemVisibilityCheck(
        previousScreenCount: Int,
        currentScreenCount: Int)
    {
        guard !SettingsStore.isRunningTests else { return }
        self.screenChangeVisibilityTask?.cancel()
        self.screenChangeVisibilityTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(750))
            } catch {
                return
            }
            self?.checkScreenChangeStatusItemVisibility(
                previousScreenCount: previousScreenCount,
                currentScreenCount: currentScreenCount)
        }
    }

    private func checkScreenChangeStatusItemVisibility(previousScreenCount: Int, currentScreenCount: Int) {
        self.pendingScreenChangePreviousCount = nil
        let snapshots = MenuBarVisibilityWatcher.visibilitySnapshots(self.startupVisibilityStatusItems)
        guard MenuBarVisibilityWatcher.shouldAttemptScreenChangeRecovery(
            previousScreenCount: previousScreenCount,
            currentScreenCount: currentScreenCount,
            snapshots: snapshots)
        else {
            return
        }

        self.menuLogger.error(
            "Display configuration changed; recreating status items",
            metadata: [
                "previousScreenCount": "\(previousScreenCount)",
                "currentScreenCount": "\(currentScreenCount)",
                "snapshots": snapshots.map(\.description).joined(separator: " | "),
            ])
        self.recreateStatusItemsForVisibilityRecovery()
    }

    var startupVisibilityStatusItems: [NSStatusItem] {
        [self.statusItem] + Array(self.statusItems.values)
    }

    /// macOS 가 장시간 deep sleep 중 NSStatusItem 의 window/screen 을 evict 하면
    /// 깨어난 시점에 `isVisible=true` 인데 `button.window / screen` 이 nil 인 blocked
    /// 상태가 된다. `updateVisibility()` 는 `isVisible` 토글만 해서 이걸 못 고친다.
    /// startup check 는 launch 후 10초까지만 유효(`startupFreshnessInterval`),
    /// `screenParametersDidChange` 는 lid-only wake 에선 안 터지는 경우가 있어
    /// wake 전용 복구 경로가 필요하다. AppKit 이 메뉴바를 다시 그릴 시간을 준 뒤
    /// blocked 면 `recreateStatusItemsForVisibilityRecovery()` 로 statusBar 에서
    /// 통째로 재등록.
    func scheduleWakeStatusItemVisibilityCheck() {
        guard !SettingsStore.isRunningTests else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(MenuBarVisibilityWatcher.wakeCheckDelay))
            self?.checkWakeStatusItemVisibility()
        }
    }

    private func checkWakeStatusItemVisibility() {
        let items = self.startupVisibilityStatusItems
        let snapshots = MenuBarVisibilityWatcher.visibilitySnapshots(items)
        guard MenuBarVisibilityWatcher.hasAnyBlockedVisibleSnapshot(snapshots) else { return }
        self.menuLogger.error(
            "Status items blocked after system wake; recreating",
            metadata: ["snapshots": snapshots.map(\.description).joined(separator: " | ")])
        self.recreateStatusItemsForVisibilityRecovery()
    }
}
