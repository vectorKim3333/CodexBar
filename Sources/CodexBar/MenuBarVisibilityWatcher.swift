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

    /// 1.8.1 진단: NSStatusItem 의 전체 geometry 를 한 줄로. notch overflow 가설 검증용 —
    /// window/button frame 의 x 위치, 소속 screen, notch safe-area / aux area 까지 찍어서
    /// "isVisible=true 인데 실제론 안 보이는" 케이스가 폭 부족(overflow) 인지 evict 인지
    /// 파일 로그로 사후 판별 가능하게 한다.
    @MainActor
    static func diagnosticDescription(_ item: NSStatusItem) -> String {
        let button = item.button
        let window = button?.window
        let screen = window?.screen
        let image = button?.image
        func r(_ rect: CGRect?) -> String {
            guard let rect else { return "nil" }
            return String(
                format: "(x%.0f y%.0f w%.0f h%.0f)",
                rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
        }
        var notch = "screen=nil"
        if let screen {
            var aux = ""
            if #available(macOS 12.0, *) {
                aux = " auxTL=\(r(screen.auxiliaryTopLeftArea)) auxTR=\(r(screen.auxiliaryTopRightArea))"
                aux += " safeTop=\(String(format: "%.0f", screen.safeAreaInsets.top))"
            }
            notch = "screen=\(screen.localizedName) frame=\(r(screen.frame))\(aux)"
        }
        return "visible=\(item.isVisible) btn=\(button != nil) win=\(window != nil)"
            + " winFrame=\(r(window?.frame)) btnFrame=\(r(button?.frame))"
            + " img=\(image.map { String(format: "%.0fx%.0f", $0.size.width, $0.size.height) } ?? "nil")"
            + " \(notch)"
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
        // 1.5.4: `buttonWidth <= 0` 단독 조건은 신생 status item 의 width=0 정상 상태를
        // false-positive 로 잡는 문제가 있었음.
        // 1.5.7: `hasImage` 추가 — image nil/zero-size 인 경우 macOS 가 hide.
        // 1.5.10: `hasImage && buttonWidth <= 0` 조합 추가 — image 가 정상 set 됐는데도
        // button width 가 0 이면 macOS 가 status bar overflow / Tahoe allow-list 로 hide
        // 한 상태 (외장 모니터 분리 후 내장 모니터 폭 부족 등). fallback image chain
        // (1.5.6) 보장으로 image 가 있는데 width=0 은 명백히 OS-level hide 신호.
        if !snapshot.hasWindow || !snapshot.hasScreen || !snapshot.isOnCurrentScreen {
            return true
        }
        if !snapshot.hasImage {
            return true
        }
        if snapshot.hasImage, snapshot.buttonWidth <= 0 {
            return true
        }
        return false
    }

    /// 1.8.0: 복구 행동 결정. `isBlockedSnapshot` 의 단일 boolean 을 4단계로 분리한다.
    ///
    /// 핵심 통찰: `button.window / screen` 이 살아있는데 width=0 / image 깨짐인 경우는
    /// macOS 의 overflow-hide / redraw 누락이지 진짜 evict 가 아니다. 이건 `removeStatusItem`
    /// 없이 **image 재설정 + isVisible 재확정** 만으로 풀린다 (비파괴). 진짜 evict
    /// (`window / screen == nil`) 만 인스턴스 recreate 가 불가피하다.
    ///
    /// 1.5.5~1.7.2 의 root cause 는 모든 복구 경로가 overflow-hide 케이스에까지
    /// `removeStatusItem` + 재생성을 썼고, 두 컨트롤러 (사용량 pill + Companion) 가 같은
    /// 타이밍에 그걸 동시에 실행해 macOS status bar 의 add→remove→add race 를 매 wake /
    /// screen-change 마다 일으킨 것. 그 race 가 한 status item 을 invisible 로 떨궜다.
    /// recreate 를 진짜 evict 로 한정하고 나머지를 비파괴로 돌리면 race 트리거 자체가 사라진다.
    enum RecoveryAction: Equatable {
        /// 정상. 아무것도 안 함.
        case none
        /// `isVisible == false` 인데 사용자가 켜둠 (macOS 가 hide). 같은 인스턴스의
        /// `isVisible = true` 토글만으로 복구 — add/remove race 없음.
        case reassertVisible
        /// `window` 는 살아있는데 width=0 / image 깨짐 (overflow-hide / redraw 누락).
        /// image 재설정 + isVisible 재확정으로 비파괴 복구. `removeStatusItem` 금지.
        case redraw
        /// `window / screen / button` 자체가 nil = 진짜 evict. 인스턴스 recreate 불가피.
        case recreate
    }

    /// 단일 status item snapshot 에 대한 복구 행동. caller 는 사용자가 켜둔
    /// (enabled / userEnabled) provider 에 대해서만 호출해야 한다 — `.reassertVisible`
    /// 은 "사용자가 켰는데 안 보임" 을 전제로 한다.
    static func recoveryAction(snapshot: StatusItemVisibilitySnapshot) -> RecoveryAction {
        guard snapshot.isVisible else { return .reassertVisible }
        guard snapshot.hasButton else { return .recreate }
        // window / screen 자체가 사라짐 = 진짜 evict. isVisible 토글 / redraw 로 못 풂.
        if !snapshot.hasWindow || !snapshot.hasScreen || !snapshot.isOnCurrentScreen {
            return .recreate
        }
        // window 는 살아있는데 image 깨짐 / width=0 = overflow-hide / redraw 누락. 비파괴.
        if !snapshot.hasImage || snapshot.buttonWidth <= 0 {
            return .redraw
        }
        return .none
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
        self.pendingScreenChangePreviousCount = nil
        self.lastKnownScreenCount = currentScreenCount
        _ = previousScreenCount
        // 1.5.9: 외장 모니터 연결/해제 시점에 macOS 가 status bar overflow 처리하면서 일부
        // status item 을 hide 한 채 다시 안 돌려놓는 케이스 (사용자 보고: 32" 모니터 ↔ 맥북
        // 내장 모니터 전환). image cache 즉시 invalidate — 복구 패스의 updateIcons 가 새
        // image 강제 그림.
        self.lastAppliedMergedIconRenderSignature = nil
        self.lastAppliedProviderIconRenderSignatures.removeAll()
        self.logMenuBarDiagnostics(reason: "screen-change@event")
        // 1.8.0: 무조건 강제 recreate (1.5.10) 대신 coalesced 비파괴-우선 복구. overflow-hide
        // (window 살아있고 width=0) 는 image redraw 로 풀리고, 진짜 evict 만 recreate.
        // Companion 은 자체적으로 더 늦은 1.4s 에 복구해 동시 removeStatusItem 을 피한다.
        self.requestStatusItemRecovery(reason: "screen-change", delay: 0.75)
    }

    var startupVisibilityStatusItems: [NSStatusItem] {
        [self.statusItem] + Array(self.statusItems.values)
    }
}
