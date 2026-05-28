import AppKit
import CodexBarCore
import Observation
import QuartzCore

// MARK: - Status item controller (AppKit-hosted icons, SwiftUI popovers)

@MainActor
protocol StatusItemControlling: AnyObject {
    func openMenuFromShortcut()
    func runLoginFlowFromSettings(provider: UsageProvider) async
    func celebrationOriginPoint(for provider: UsageProvider?) -> CGPoint?
    func sharedMenu() -> NSMenu
}

extension StatusItemControlling {
    func celebrationOriginPoint(for provider: UsageProvider?) -> CGPoint? {
        nil
    }
    func sharedMenu() -> NSMenu { NSMenu() }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, StatusItemControlling {
    // Disable SwiftUI menu cards + menu refresh work in tests to avoid swiftpm-testing-helper crashes.
    static var menuCardRenderingEnabled = !SettingsStore.isRunningTests
    private static let defaultMenuRefreshEnabled = !SettingsStore.isRunningTests
    private(set) static var menuRefreshEnabled = !SettingsStore.isRunningTests
    static let quotaWarningFlashDuration: TimeInterval = 60
    #if DEBUG
    static func setMenuRefreshEnabledForTesting(_ enabled: Bool) {
        self.menuRefreshEnabled = enabled
    }

    static func resetMenuRefreshEnabledForTesting() {
        self.menuRefreshEnabled = self.defaultMenuRefreshEnabled
    }
    #endif
    typealias Factory = @MainActor (
        UsageStore,
        SettingsStore,
        AccountInfo,
        PreferencesSelection,
        ManagedCodexAccountCoordinator,
        CodexAccountPromotionCoordinator)
        -> StatusItemControlling
    // swiftlint:disable:next function_parameter_count
    static func makeDefaultController(
        store: UsageStore,
        settings: SettingsStore,
        account: AccountInfo,
        selection: PreferencesSelection,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator,
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator)
        -> StatusItemControlling
    {
        StatusItemController(
            store: store,
            settings: settings,
            account: account,
            preferencesSelection: selection,
            managedCodexAccountCoordinator: managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: codexAccountPromotionCoordinator)
    }

    static let defaultFactory: Factory = StatusItemController.makeDefaultController

    static var factory: Factory = StatusItemController.defaultFactory

    let store: UsageStore
    let settings: SettingsStore
    let account: AccountInfo
    let managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
    let codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    private let statusBar: NSStatusBar
    var statusItem: NSStatusItem
    var statusItems: [UsageProvider: NSStatusItem] = [:]
    var lastMenuProvider: UsageProvider?
    var menuProviders: [ObjectIdentifier: UsageProvider] = [:]
    var menuContentVersion: Int = 0
    var menuVersions: [ObjectIdentifier: Int] = [:]
    var mergedMenu: NSMenu?
    var providerMenus: [UsageProvider: NSMenu] = [:]
    var fallbackMenu: NSMenu?
    var openMenus: [ObjectIdentifier: NSMenu] = [:]
    var menuRefreshTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    #if DEBUG
    var onDelayedMenuRefreshAttemptForTesting: (() -> Void)?
    var isReleasedForTesting = false
    var _test_openMenuRefreshYieldOverride: (@MainActor () async -> Void)?
    var _test_openMenuRebuildObserver: (@MainActor (NSMenu) -> Void)?
    var _test_codexAmbientLoginRunnerOverride: (@MainActor (TimeInterval) async -> CodexLoginRunner.Result)?
    #endif
    var blinkTask: Task<Void, Never>?
    var loginTask: Task<Void, Never>? {
        didSet { self.refreshMenusForLoginStateChange() }
    }

    var activeLoginProvider: UsageProvider? {
        didSet {
            if oldValue != self.activeLoginProvider {
                self.refreshMenusForLoginStateChange()
            }
        }
    }

    var blinkStates: [UsageProvider: BlinkState] = [:]
    var blinkAmounts: [UsageProvider: CGFloat] = [:]
    var wiggleAmounts: [UsageProvider: CGFloat] = [:]
    var tiltAmounts: [UsageProvider: CGFloat] = [:]
    var quotaWarningFlashUntil: [UsageProvider: Date] = [:]
    var quotaWarningFlashTasks: [UsageProvider: Task<Void, Never>] = [:]
    var blinkForceUntil: Date?
    var loginPhase: LoginPhase = .idle {
        didSet {
            if oldValue != self.loginPhase {
                self.refreshMenusForLoginStateChange()
            }
        }
    }

    let preferencesSelection: PreferencesSelection
    var animationDriver: DisplayLinkDriver?
    var animationPhase: Double = 0
    var animationPattern: LoadingPattern = .knightRider
    var animationStartedAt: Date?
    private var lastConfigRevision: Int
    private var lastProviderOrder: [UsageProvider]
    /// 직전에 메뉴바에 노출되어 있던 provider 집합. handleSettingsChange 가 호출될 때
    /// 새로 enabled 된 provider 를 찾아 즉시 refresh 를 트리거하기 위해 사용한다.
    private var lastDisplayedProviders: Set<UsageProvider> = []
    private var lastMergeIcons: Bool
    private var lastSwitcherShowsIcons: Bool
    private var lastObservedUsageBarsShowUsed: Bool
    /// Tracks which `usageBarsShowUsed` mode the provider switcher was built with.
    /// Used to decide whether we can "smart update" menu content without rebuilding the switcher.
    var lastSwitcherUsageBarsShowUsed: Bool
    /// Tracks whether the merged-menu switcher was built with the Overview tab visible.
    /// Used to force switcher rebuilds when Overview availability toggles.
    var lastSwitcherIncludesOverview: Bool = false
    /// Tracks which providers the merged menu's switcher was built with, to detect when it needs full rebuild.
    var lastSwitcherProviders: [UsageProvider] = []
    /// Tracks which switcher tab state was used for the current merged-menu switcher instance.
    var lastMergedSwitcherSelection: ProviderSwitcherSelection?
    /// Tracks the visible Codex account switcher contents for merged-menu smart updates.
    var lastCodexAccountMenuDisplay: CodexAccountMenuDisplay?
    /// Tracks the visible token account switcher contents for merged-menu smart updates.
    var lastTokenAccountMenuDisplay: TokenAccountMenuDisplay?
    /// Monotonic token used to ignore stale deferred provider-switcher menu rebuilds.
    var providerSwitcherUpdateToken = 0
    var lastAppliedMergedIconRenderSignature: String?
    var lastAppliedProviderIconRenderSignatures: [UsageProvider: String] = [:]
    var lastKnownScreenCount: Int
    var pendingScreenChangePreviousCount: Int?
    var screenChangeVisibilityTask: Task<Void, Never>?
    var iconHeartbeatTask: Task<Void, Never>?
    let loginLogger = CodexBarLog.logger(LogCategories.login)
    let menuLogger = CodexBarLog.logger(LogCategories.app)
    var selectedMenuProvider: UsageProvider? {
        get { self.settings.selectedMenuProvider }
        set { self.settings.selectedMenuProvider = newValue }
    }

    private static func makeStatusItem(statusBar: NSStatusBar) -> NSStatusItem {
        let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        // Ensure the icon is rendered at 1:1 without resampling (crisper edges for template images).
        item.button?.imageScaling = .scaleNone
        return item
    }

    struct BlinkState {
        var nextBlink: Date
        var blinkStart: Date?
        var pendingSecondStart: Date?
        var effect: MotionEffect = .blink

        static func randomDelay() -> TimeInterval {
            Double.random(in: 3...12)
        }
    }

    enum MotionEffect {
        case blink
        case wiggle
        case tilt
    }

    enum LoginPhase {
        case idle
        case requesting
        case waitingBrowser
    }

    func menuBarMetricWindow(for provider: UsageProvider, snapshot: UsageSnapshot?) -> RateWindow? {
        if provider == .codex {
            return self.codexMenuBarMetricWindow(snapshot: snapshot)
        }
        return MenuBarMetricWindowResolver.rateWindow(
            preference: self.settings.menuBarMetricPreference(for: provider, snapshot: snapshot),
            provider: provider,
            snapshot: snapshot,
            supportsAverage: self.settings.menuBarMetricSupportsAverage(for: provider))
    }

    private func codexMenuBarMetricWindow(snapshot: UsageSnapshot?) -> RateWindow? {
        guard let snapshot else { return nil }
        let projection = CodexConsumerProjection.make(
            surface: .menuBar,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: self.store.credits,
                rawCreditsError: self.store.lastCreditsError,
                liveDashboard: self.store.openAIDashboard,
                rawDashboardError: self.store.lastOpenAIDashboardError,
                dashboardAttachmentAuthorized: self.store.openAIDashboardAttachmentAuthorized,
                dashboardRequiresLogin: self.store.openAIDashboardRequiresLogin,
                now: snapshot.updatedAt))
        let lanes = projection.visibleRateLanes
        let first = lanes.first.flatMap { projection.rateWindow(for: $0) }
        let second = lanes.dropFirst().first.flatMap { projection.rateWindow(for: $0) }
        let preference = self.settings.menuBarMetricPreference(for: .codex, snapshot: snapshot)

        switch preference {
        case .secondary, .tertiary:
            return second ?? first
        case .extraUsage:
            return first
        case .average:
            guard self.settings.menuBarMetricSupportsAverage(for: .codex),
                  let primary = first,
                  let secondary = second
            else {
                return first
            }
            let usedPercent = (primary.usedPercent + secondary.usedPercent) / 2
            return RateWindow(usedPercent: usedPercent, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        case .automatic, .primary:
            return first
        }
    }

    init(
        store: UsageStore,
        settings: SettingsStore,
        account: AccountInfo,
        preferencesSelection: PreferencesSelection,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator = ManagedCodexAccountCoordinator(),
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator? = nil,
        statusBar: NSStatusBar = .system,
        observeProviderConfigNotifications: Bool = !SettingsStore.isRunningTests)
    {
        if SettingsStore.isRunningTests {
            _ = NSApplication.shared
        }
        self.store = store
        self.settings = settings
        self.account = account
        self.preferencesSelection = preferencesSelection
        self.managedCodexAccountCoordinator = managedCodexAccountCoordinator
        self.codexAccountPromotionCoordinator = codexAccountPromotionCoordinator
            ?? CodexAccountPromotionCoordinator(
                settingsStore: settings,
                usageStore: store,
                managedAccountCoordinator: managedCodexAccountCoordinator)
        self.lastConfigRevision = settings.configRevision
        self.lastProviderOrder = settings.providerOrder
        self.lastMergeIcons = settings.mergeIcons
        self.lastSwitcherShowsIcons = settings.switcherShowsIcons
        self.lastObservedUsageBarsShowUsed = settings.usageBarsShowUsed
        self.lastSwitcherUsageBarsShowUsed = settings.usageBarsShowUsed
        self.statusBar = statusBar
        self.statusItem = Self.makeStatusItem(statusBar: statusBar)
        self.lastKnownScreenCount = NSScreen.screens.count
        // Status items for individual providers are now created lazily in updateVisibility()
        super.init()
        self.wireBindings()
        self.updateVisibility()
        self.updateIcons()
        self.scheduleStartupStatusItemVisibilityCheck()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleDebugReplayNotification(_:)),
            name: .codexbarDebugReplayAllAnimations,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleDebugBlinkNotification),
            name: .codexbarDebugBlinkNow,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleQuotaWarningPosted(_:)),
            name: .codexbarQuotaWarningDidPost,
            object: nil)
        if observeProviderConfigNotifications {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleProviderConfigDidChange),
                name: .codexbarProviderConfigDidChange,
                object: nil)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleScreenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        // 시스템이 슬립에서 깨어났을 때 진행 중이던 fetch 가 네트워크 단절로
        // 끊긴 채 isRefreshing / refreshingProviders 가드가 풀리지 못해
        // "Not fetched yet" 에 갇히는 경우가 있다. wake notification 으로
        // 가드를 정리하고 강제 refresh 를 트리거해서 자연스럽게 복구한다.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(self.handleSystemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil)
        // 사용자가 다른 앱에 있다가 ClCoBar 메뉴바를 클릭하려고 돌아온 순간,
        // 또는 macOS 가 status item window 를 evict 한 채로 시간이 흐른 뒤
        // 다시 active 가 된 경우 → 가장 자연스러운 복구 타이밍. wake notification
        // 의 1.5s one-shot 만으로는 long-uptime eviction 을 놓치기 때문에
        // active 복귀와 screen wake 시점에서도 강제로 visibility 를 검증한다.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleApplicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(self.handleScreensDidWake(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil)
    }

    @objc private func handleApplicationDidBecomeActive(_: Notification) {
        Task { @MainActor [weak self] in
            self?.recoverInvisibleOrBlockedStatusItemsIfNeeded(reason: "app-active")
        }
    }

    @objc private func handleScreensDidWake(_: Notification) {
        Task { @MainActor [weak self] in
            // 디스플레이가 슬립에서 깨어났을 때 evict 상태인 경우가 잦음.
            // wake 직후 AppKit 이 메뉴바를 다시 그릴 시간을 주고 검증.
            try? await Task.sleep(for: .seconds(MenuBarVisibilityWatcher.wakeCheckDelay))
            self?.recoverInvisibleOrBlockedStatusItemsIfNeeded(reason: "screens-wake")
        }
    }

    @objc private func handleSystemDidWake(_: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 슬립 중에 멈춘 task 의 가드가 풀리지 못한 채 남아 있으면 후속 refresh 가
            // 모두 막힌다. 깨어난 시점에 가드를 강제 정리하고 visibility 까지 다시
            // 그려서 메뉴바 상태 / fetch 상태 / 캐시가 한꺼번에 동기화되도록 한다.
            self.store.isRefreshing = false
            self.store.refreshingProviders.removeAll()
            self.updateVisibility()
            // macOS 가 장시간 deep sleep 중 NSStatusItem 의 window 를 evict 하는 경우,
            // updateVisibility() 의 isVisible 토글만으론 안 보이는 메뉴바를 복구하지 못한다.
            // 1.5.2 부터 cascade: 1.5s + 5s + 15s 세 번 검증 — 장시간 sleep 후 wake
            // 시점에 macOS 가 status bar 재배치하는 시간이 길어 단발 1.5초 체크만으론
            // 못 잡는 케이스 있었음.
            self.scheduleWakeStatusItemVisibilityCheck()
            self.scheduleCascadeWakeRecovery()
            await self.store.refresh()
        }
    }

    /// 장시간 deep sleep 후 wake 에서 1.5s 단발 검증으론 NSStatusItem evict 가 못 잡히는
    /// 케이스 대응. 5초 / 15초 시점에 한 번씩 더 visibility recovery 발화.
    /// `recoverInvisibleOrBlockedStatusItemsIfNeeded` 는 idempotent 라 중복 호출 안전.
    private func scheduleCascadeWakeRecovery() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.recoverInvisibleOrBlockedStatusItemsIfNeeded(reason: "wake-cascade-5s")
            try? await Task.sleep(for: .seconds(10))
            self?.recoverInvisibleOrBlockedStatusItemsIfNeeded(reason: "wake-cascade-15s")
        }
    }

    convenience init(
        store: UsageStore,
        settings: SettingsStore,
        account: AccountInfo,
        preferencesSelection: PreferencesSelection,
        statusBar: NSStatusBar = .system,
        observeProviderConfigNotifications: Bool = !SettingsStore.isRunningTests)
    {
        self.init(
            store: store,
            settings: settings,
            account: account,
            preferencesSelection: preferencesSelection,
            managedCodexAccountCoordinator: ManagedCodexAccountCoordinator(),
            codexAccountPromotionCoordinator: nil,
            statusBar: statusBar,
            observeProviderConfigNotifications: observeProviderConfigNotifications)
    }

    private func wireBindings() {
        self.observeStoreChanges()
        self.observeStoreIconChanges()
        self.observeDebugForceAnimation()
        self.observeSettingsChanges()
        self.observeManagedCodexCoordinatorChanges()
        self.startIconHeartbeat()
    }

    /// Periodic icon re-evaluation so the menu-bar pill's countdown text
    /// (e.g. "1h 45m" → "1h 44m") ticks even when no fetch is firing.
    /// Re-runs `updateIcons()` once a minute; each provider's
    /// `shouldSkipProviderIconRender` guard means an actual redraw only
    /// happens when the resolved `resetText` (now part of the signature)
    /// actually changes.
    ///
    /// 추가로 매 주기마다 `recoverInvisibleOrBlockedStatusItemsIfNeeded` 를
    /// 호출해 사용자가 켜둔 provider 의 NSStatusItem 이 evict 됐거나 사라진
    /// 상태인지 확인하고 자동 복구한다. wake notification 의 1.5s one-shot 만
    /// 으로는 long-uptime / display-only sleep / Tahoe allow-list 변경 등의
    /// 케이스를 못 잡기 때문에 항시적 watchdog 이 필요.
    private func startIconHeartbeat() {
        self.iconHeartbeatTask?.cancel()
        self.iconHeartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.updateIcons()
                self.recoverStaleProviders()
                self.recoverInvisibleOrBlockedStatusItemsIfNeeded(reason: "heartbeat")
            }
        }
    }

    /// 사용자가 켜둔 provider 의 NSStatusItem 이 다음 셋 중 하나에 해당하면 복구:
    ///
    ///  1. statusItems[provider] 가 nil → `updateVisibility()` 로 lazy 생성
    ///  2. isVisible == false 인데 사용자가 켜둠 → `isVisible = true` 강제
    ///  3. isVisible == true 인데 button.window / screen 이 nil (macOS 가 evict)
    ///     → `recreateStatusItemsForVisibilityRecovery()` 로 statusBar 에서
    ///     통째로 재등록
    ///
    /// 메뉴가 열려 있는 동안 status item 을 재생성하면 메뉴가 닫히고 깜빡이므로
    /// `openMenus.isEmpty` 일 때만 destructive 복구를 수행. 가벼운 isVisible
    /// 토글 / 누락 보충은 메뉴 열림 여부와 무관하게 안전하다.
    func recoverInvisibleOrBlockedStatusItemsIfNeeded(reason: String) {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        guard !SettingsStore.isRunningTests else { return }

        let enabledForDisplay = Set(self.store.enabledProvidersForDisplay())

        // (1)+(2) 누락 / 비가시 보충 — 메뉴 열림과 무관, 항상 즉시 처리.
        var missingProviders: [UsageProvider] = []
        var hiddenProviders: [UsageProvider] = []
        for provider in enabledForDisplay {
            if self.statusItems[provider] == nil {
                missingProviders.append(provider)
            } else if let item = self.statusItems[provider], !item.isVisible {
                hiddenProviders.append(provider)
            }
        }
        if !missingProviders.isEmpty || !hiddenProviders.isEmpty {
            self.menuLogger.error(
                "Status item missing or hidden; restoring",
                metadata: [
                    "reason": reason,
                    "missing": missingProviders.map(\.rawValue).joined(separator: ","),
                    "hidden": hiddenProviders.map(\.rawValue).joined(separator: ","),
                ])
            self.updateVisibility()
            self.updateIcons()
        }

        // (3) blocked snapshot 감지 — 1.5.7 부터 **단일 provider 만** recreate 로 변경.
        // 이전 `recreateStatusItemsForVisibilityRecovery` 는 모든 provider statusItem 통째
        // wipe → 깜빡임 + 다른 status item cross-effect 위험 있었음. 정말 blocked 인 provider
        // 만 골라서 본인 instance 만 재생성. 다른 provider 영향 0.
        guard self.openMenus.isEmpty else { return }
        var blockedProviders: [UsageProvider] = []
        for (provider, item) in self.statusItems {
            let snapshot = MenuBarVisibilityWatcher.visibilitySnapshot(item)
            if MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot) {
                blockedProviders.append(provider)
            }
        }
        guard !blockedProviders.isEmpty else { return }
        self.menuLogger.error(
            "Provider status items blocked; recreating individually",
            metadata: [
                "reason": reason,
                "blocked": blockedProviders.map(\.rawValue).joined(separator: ","),
            ])
        for provider in blockedProviders {
            self.recreateProviderStatusItem(for: provider)
        }
    }

    /// 단일 provider 의 NSStatusItem 만 통째 재생성. 다른 provider 영향 없음.
    /// 1.5.7: `recreateStatusItemsForVisibilityRecovery` 의 전체 wipe 대신 evict 된
    /// provider 만 골라 처리. cross-effect 위험 최소화.
    private func recreateProviderStatusItem(for provider: UsageProvider) {
        // 기존 instance 제거 (dictionary + statusBar 양쪽).
        if let menu = self.providerMenus.removeValue(forKey: provider) {
            let menuID = ObjectIdentifier(menu)
            self.menuProviders.removeValue(forKey: menuID)
            self.menuVersions.removeValue(forKey: menuID)
            self.openMenus.removeValue(forKey: menuID)
            self.menuRefreshTasks.removeValue(forKey: menuID)?.cancel()
        }
        if let item = self.statusItems.removeValue(forKey: provider) {
            item.menu = nil
            self.statusBar.removeStatusItem(item)
        }
        self.lastAppliedProviderIconRenderSignatures.removeValue(forKey: provider)
        // 새 instance 생성 (lazyStatusItem) + visibility + icon + menu 다시 부착.
        let newItem = self.lazyStatusItem(for: provider)
        let enabledForDisplay = Set(self.store.enabledProvidersForDisplay())
        newItem.isVisible = enabledForDisplay.contains(provider)
        self.updateIcons()
        self.attachMenus(fallback: nil)
    }


    /// "Not fetched yet" 자가 회복. enabled 인데 snapshot 도 errors 도 없고 in-flight
    /// 도 아닌 provider 가 있으면 → 마지막 자동 refresh 가 어떤 이유로 결과를 남기지
    /// 못한 채 사라진 것. heartbeat 주기에 한 번씩 refresh 를 다시 트리거해 시간이
    /// 지나도 자연스럽게 복구되도록 한다. fetch 결과가 snapshot 또는 errors 에 들어가면
    /// 다음 주기엔 자동으로 trigger 안 됨 (조건 불만족) → 무한 retry 방지.
    private func recoverStaleProviders() {
        for provider in self.store.enabledProvidersForDisplay() {
            guard self.store.snapshot(for: provider) == nil,
                  self.store.errors[provider] == nil,
                  !self.store.refreshingProviders.contains(provider),
                  self.store.rateLimitBackoffUntil[provider].map({ $0 <= Date() }) ?? true
            else { continue }
            Task { @MainActor [weak self] in
                await self?.store.refreshProvider(provider)
            }
        }
    }

    private func observeStoreChanges() {
        withObservationTracking {
            _ = self.store.menuObservationToken
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeStoreChanges()
                self.invalidateMenus()
            }
        }
    }

    private func observeStoreIconChanges() {
        withObservationTracking {
            _ = self.store.iconObservationToken
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeStoreIconChanges()
                self.updateIcons()
            }
        }
    }

    private func observeDebugForceAnimation() {
        withObservationTracking {
            _ = self.store.debugForceAnimation
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeDebugForceAnimation()
                self.updateVisibility()
                self.updateBlinkingState()
            }
        }
    }

    private func observeSettingsChanges() {
        withObservationTracking {
            _ = self.settings.menuObservationToken
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeSettingsChanges()
                self.handleSettingsChange(reason: "observation")
            }
        }
    }

    func handleProviderConfigChange(reason: String) {
        self.handleSettingsChange(reason: "config:\(reason)")
    }

    @objc private func handleProviderConfigDidChange(_ notification: Notification) {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        let reason = notification.userInfo?["reason"] as? String ?? "unknown"
        if let source = notification.object as? SettingsStore,
           source !== self.settings
        {
            if let config = notification.userInfo?["config"] as? CodexBarConfig {
                self.settings.applyExternalConfig(config, reason: "external-\(reason)")
            } else {
                self.settings.reloadConfig(reason: "external-\(reason)")
            }
        }
        self.handleProviderConfigChange(reason: "notification:\(reason)")
    }

    @objc private func handleQuotaWarningPosted(_ notification: Notification) {
        guard let event = notification.object as? QuotaWarningPostedEvent else { return }
        self.startQuotaWarningFlash(provider: event.provider, postedAt: event.postedAt)
    }

    func startQuotaWarningFlash(provider: UsageProvider, postedAt: Date = Date()) {
        let until = postedAt.addingTimeInterval(Self.quotaWarningFlashDuration)
        self.quotaWarningFlashUntil[provider] = until
        self.quotaWarningFlashTasks[provider]?.cancel()
        self.updateIcons()
        self.quotaWarningFlashTasks[provider] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.quotaWarningFlashDuration))
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let currentUntil = self.quotaWarningFlashUntil[provider],
                   currentUntil <= Date()
                {
                    self.quotaWarningFlashUntil.removeValue(forKey: provider)
                    self.quotaWarningFlashTasks.removeValue(forKey: provider)
                    self.updateIcons()
                }
            }
        }
    }

    private func observeManagedCodexCoordinatorChanges() {
        withObservationTracking {
            _ = self.managedCodexAccountCoordinator.isAuthenticatingManagedAccount
            _ = self.managedCodexAccountCoordinator.authenticatingManagedAccountID
            _ = self.managedCodexAccountCoordinator.isRemovingManagedAccount
            _ = self.managedCodexAccountCoordinator.removingManagedAccountID
            _ = self.codexAccountPromotionCoordinator.isAuthenticatingLiveAccount
            _ = self.codexAccountPromotionCoordinator.isPromotingSystemAccount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeManagedCodexCoordinatorChanges()
                self.refreshMenusForLoginStateChange()
            }
        }
    }

    func invalidateMenus(refreshOpenMenus: Bool = false) {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        self.menuContentVersion &+= 1
        guard Self.menuRefreshEnabled else { return }
        if !self.openMenus.isEmpty {
            guard refreshOpenMenus else { return }
            self.refreshOpenMenusAllowingParentRebuild()
            Task { @MainActor [weak self] in
                guard let self else { return }
                // AppKit can ignore menu mutations while tracking; retry on the next run loop.
                await Task.yield()
                self.refreshOpenMenusAllowingParentRebuild()
            }
            return
        }
        self.refreshOpenMenusIfNeeded()
        Task { @MainActor [weak self] in
            guard let self else { return }
            // AppKit can ignore menu mutations while tracking; retry on the next run loop.
            await Task.yield()
            guard self.openMenus.isEmpty else { return }
            self.refreshOpenMenusIfNeeded()
        }
    }

    private func shouldRefreshOpenMenusForProviderSwitcher() -> Bool {
        var shouldRefresh = false
        let revision = self.settings.configRevision
        if revision != self.lastConfigRevision {
            self.lastConfigRevision = revision
            shouldRefresh = true
        }
        let order = self.settings.providerOrder
        if order != self.lastProviderOrder {
            self.lastProviderOrder = order
            shouldRefresh = true
        }
        let mergeIcons = self.settings.mergeIcons
        if mergeIcons != self.lastMergeIcons {
            self.lastMergeIcons = mergeIcons
            shouldRefresh = true
        }
        let showsIcons = self.settings.switcherShowsIcons
        if showsIcons != self.lastSwitcherShowsIcons {
            self.lastSwitcherShowsIcons = showsIcons
            shouldRefresh = true
        }
        let usageBarsShowUsed = self.settings.usageBarsShowUsed
        if usageBarsShowUsed != self.lastObservedUsageBarsShowUsed {
            self.lastObservedUsageBarsShowUsed = usageBarsShowUsed
            shouldRefresh = true
        }
        return shouldRefresh
    }

    private func handleSettingsChange(reason: String) {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        let configChanged = self.settings.configRevision != self.lastConfigRevision
        let orderChanged = self.settings.providerOrder != self.lastProviderOrder
        let shouldRefreshOpenMenus = self.shouldRefreshOpenMenusForProviderSwitcher()
        self.invalidateMenus()
        if orderChanged || configChanged {
            self.rebuildProviderStatusItems()
        }
        self.updateVisibility()
        self.updateIcons()
        if shouldRefreshOpenMenus {
            self.refreshOpenMenusForStructureChange()
        }
        self.refreshNewlyEnabledProvidersIfNeeded()
        // 1.5.4: 1.5.3 에서 추가했던 self.requestVisibilityRecovery 호출 제거.
        // 토글마다 destructive cascade 발화시켜 다른 status item 까지 영향 주는
        // cross-effect 가 사용자가 보고한 "토글 후 사용량 안 나옴" 의 root cause 였음.
        // settings 변경 자체는 evict 일으키지 않으므로 recovery 불필요. 진짜 evict 는
        // wake observer + 30초 heartbeat 가 잡음.
    }

    /// 토글 OFF → ON 으로 새로 enabled 된 provider 가 있으면 즉시 fetch 를 트리거한다.
    /// `handleSettingsChange` 가 UI 만 갱신해서 "Not fetched yet" 이 다음 자동 refresh
    /// 주기까지 유지되는 문제 방지. enabled 차집합으로 판정해서 무한 trigger 회피.
    ///
    /// 추가로 이전 토글 cycle 에서 in-flight 가 hang 한 채로 `refreshingProviders` 에
    /// stuck 된 상태를 강제 클리어 — 빠른 OFF/ON 시퀀스에서 fetch task 가 hang 하면
    /// `recoverStaleProviders` 의 `!refreshingProviders.contains` 가드 때문에
    /// heartbeat retry 도 영원히 skip 되는 stuck 상태가 발생할 수 있어서.
    private func refreshNewlyEnabledProvidersIfNeeded() {
        let current = Set(self.store.enabledProvidersForDisplay())
        let newlyEnabled = current.subtracting(self.lastDisplayedProviders)
        self.lastDisplayedProviders = current
        guard !newlyEnabled.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for provider in newlyEnabled {
                // Stuck in-flight 강제 클리어 (이전 cycle 의 hang 한 fetch 흔적 제거).
                self.store.refreshingProviders.remove(provider)
                await self.store.refreshProvider(provider)
            }
        }
    }

    private func updateIcons() {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        // Avoid flicker: when an animation driver is active, store updates can call `updateIcons()` and
        // briefly overwrite the animated frame with the static (phase=nil) icon.
        let phase: Double? = self.needsMenuBarIconAnimation() ? self.animationPhase : nil
        if self.shouldMergeIcons {
            let skippedMergedRender = self.applyIcon(phase: phase)
            if skippedMergedRender,
               let mergedMenu = self.mergedMenu,
               self.statusItem.menu === mergedMenu
            {
                return
            }
            guard !self.isMergedMenuOpen else {
                self.updateAnimationState()
                self.updateBlinkingState()
                return
            }
            self.attachMenus()
        } else {
            UsageProvider.allCases.forEach { self.applyIcon(for: $0, phase: phase) }
            self.attachMenus(fallback: self.fallbackProvider)
        }
        self.updateAnimationState()
        self.updateBlinkingState()
    }

    var isMergedMenuOpen: Bool {
        guard let mergedMenu else { return false }
        return self.openMenus[ObjectIdentifier(mergedMenu)] != nil
    }

    /// Lazily retrieves or creates a status item for the given provider
    func lazyStatusItem(for provider: UsageProvider) -> NSStatusItem {
        if let existing = self.statusItems[provider] {
            return existing
        }
        let item = Self.makeStatusItem(statusBar: self.statusBar)
        self.statusItems[provider] = item
        return item
    }

    func recreateStatusItemsForVisibilityRecovery() {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        self.statusItem.menu = nil
        self.statusBar.removeStatusItem(self.statusItem)
        self.statusItem = Self.makeStatusItem(statusBar: self.statusBar)
        for provider in Array(self.statusItems.keys) {
            self.removeProviderStatusItem(for: provider)
        }
        self.lastAppliedMergedIconRenderSignature = nil
        self.lastAppliedProviderIconRenderSignatures.removeAll()
        self.updateVisibility()
        self.updateIcons()
    }

    private func updateVisibility() {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        let force = self.store.debugForceAnimation
        let enabledForDisplay = Set(self.store.enabledProvidersForDisplay())
        // Menu-bar items strictly mirror the Provider toggles — no fallback,
        // no availability filter. If both providers are unchecked, nothing
        // shows. The legacy single-status-item path (`self.statusItem`) is
        // unused (merge mode is removed) so we keep it permanently hidden.
        self.statusItem.isVisible = false
        // 1.5.5: NSStatusItem 인스턴스의 lifetime 을 앱 lifetime 과 동일하게 유지.
        // 토글 OFF 시 `statusBar.removeStatusItem` 으로 인스턴스를 통째로 제거하던 이전
        // 패턴은 macOS status bar 의 짧은 시간 add → remove → add race 를 일으켜 다른
        // status item (특히 Companion) 의 visibility 까지 깨뜨리는 cross-effect 의
        // root cause 였음. `isVisible` 토글만 하면 macOS 가 status bar 재배치 없이
        // 인스턴스의 hide/show 만 처리해서 cross-effect 발생 안 함 — Apple 권장 패턴.
        for provider in self.settings.orderedProviders() {
            let shouldBeVisible = enabledForDisplay.contains(provider) || force
            let item = self.lazyStatusItem(for: provider)
            item.isVisible = shouldBeVisible
        }
        self.attachMenus(fallback: nil)
        self.updateAnimationState()
        self.updateBlinkingState()
    }

    /// Returned `nil` permanently — fallback codex display was confusing
    /// users who turned everything off. Kept as a property because a few
    /// call sites still reference it; remove later if/when those go.
    var fallbackProvider: UsageProvider? { nil }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        self.store.isEnabled(provider)
    }

    private func refreshMenusForLoginStateChange() {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        self.invalidateMenus()
        if self.shouldMergeIcons {
            guard !self.isMergedMenuOpen else { return }
            self.attachMenus()
        } else {
            self.attachMenus(fallback: self.fallbackProvider)
        }
    }

    private func attachMenus() {
        if self.mergedMenu == nil {
            self.mergedMenu = self.makeMenu()
        }
        if self.statusItem.menu !== self.mergedMenu {
            self.statusItem.menu = self.mergedMenu
        }
    }

    private func attachMenus(fallback: UsageProvider? = nil) {
        _ = fallback // kept for ABI; fallback display is removed.
        // Each enabled provider's status item gets its own NSMenu instance
        // registered in `menuProviders[menu] = provider` so `menuWillOpen`
        // snaps the unified-menu switcher to the clicked pill's provider.
        // Source of truth is the toggle (enabledProvidersForDisplay), NOT the
        // availability-filtered isEnabled — what's checked is what shows.
        let enabledForDisplay = Set(self.store.enabledProvidersForDisplay())
        for provider in UsageProvider.allCases {
            if enabledForDisplay.contains(provider) {
                let item = self.lazyStatusItem(for: provider)
                if self.providerMenus[provider] == nil {
                    self.providerMenus[provider] = self.makeMenu(for: provider)
                }
                let menu = self.providerMenus[provider]
                if item.menu !== menu {
                    item.menu = menu
                }
            } else if let item = self.statusItems[provider] {
                item.menu = nil
            }
        }
    }

    private func rebuildProviderStatusItems() {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        let ordered = self.settings.orderedProviders()
        let desired = Set(ordered)
        for provider in Array(self.statusItems.keys) where !desired.contains(provider) {
            self.removeProviderStatusItem(for: provider)
        }

        guard !self.shouldMergeIcons else { return }
        let fallback = self.fallbackProvider
        let force = self.store.debugForceAnimation
        for provider in ordered where self.isEnabled(provider) || fallback == provider || force {
            _ = self.lazyStatusItem(for: provider)
        }
    }

    private func removeProviderStatusItem(for provider: UsageProvider) {
        if let menu = self.providerMenus.removeValue(forKey: provider) {
            let menuID = ObjectIdentifier(menu)
            self.menuProviders.removeValue(forKey: menuID)
            self.menuVersions.removeValue(forKey: menuID)
            self.openMenus.removeValue(forKey: menuID)
            self.menuRefreshTasks.removeValue(forKey: menuID)?.cancel()
        }

        guard let item = self.statusItems.removeValue(forKey: provider) else { return }
        item.menu = nil
        self.lastAppliedProviderIconRenderSignatures.removeValue(forKey: provider)
        self.statusBar.removeStatusItem(item)
    }

    func isVisible(_ provider: UsageProvider) -> Bool {
        self.store.debugForceAnimation || self.isEnabled(provider) || self.fallbackProvider == provider
    }

    var shouldMergeIcons: Bool {
        // Merge mode is removed in this fork. The menu bar always shows one
        // status item per enabled provider. Each item's click surfaces the
        // unified menu (Claude card + Codex card + Overview switcher) via
        // `shouldShowUnifiedMenu`.
        false
    }

    /// True when the unified merged-style menu (provider switcher across
    /// Claude / Codex / Overview) should be shown, regardless of whether the
    /// menu bar itself is in merged or split icon mode.
    var shouldShowUnifiedMenu: Bool {
        self.store.enabledProvidersForDisplay().count > 1
    }

    func switchAccountSubtitle(for target: UsageProvider) -> String? {
        guard self.loginTask != nil, let provider = self.activeLoginProvider, provider == target else { return nil }
        let base: String
        switch self.loginPhase {
        case .idle: return nil
        case .requesting: base = "Requesting login…"
        case .waitingBrowser: base = "Waiting in browser…"
        }
        let prefix = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        return "\(prefix): \(base)"
    }

    #if DEBUG
    func releaseStatusItemsForTesting() {
        guard !self.isReleasedForTesting else { return }
        self.isReleasedForTesting = true
        self.blinkTask?.cancel()
        self.loginTask?.cancel()
        self.screenChangeVisibilityTask?.cancel()
        self.pendingScreenChangePreviousCount = nil
        self.animationDriver?.stop()
        self.animationDriver = nil
        self.animationPhase = 0
        self.blinkForceUntil = nil
        self.blinkStates.removeAll(keepingCapacity: false)
        self.blinkAmounts.removeAll(keepingCapacity: false)
        self.wiggleAmounts.removeAll(keepingCapacity: false)
        self.tiltAmounts.removeAll(keepingCapacity: false)

        for task in self.menuRefreshTasks.values {
            task.cancel()
        }
        self.menuRefreshTasks.removeAll(keepingCapacity: false)
        self.openMenus.removeAll(keepingCapacity: false)
        self.menuProviders.removeAll(keepingCapacity: false)
        self.menuVersions.removeAll(keepingCapacity: false)
        self.providerMenus.removeAll(keepingCapacity: false)
        self.mergedMenu = nil
        self.fallbackMenu = nil

        self.statusItem.menu = nil
        self.statusBar.removeStatusItem(self.statusItem)

        for item in self.statusItems.values {
            item.menu = nil
            self.statusBar.removeStatusItem(item)
        }
        self.statusItems.removeAll(keepingCapacity: false)
        self.lastAppliedProviderIconRenderSignatures.removeAll(keepingCapacity: false)
    }
    #endif

    deinit {
        let animationDriver = self.animationDriver
        Task { @MainActor in
            animationDriver?.stop()
        }
        self.blinkTask?.cancel()
        self.loginTask?.cancel()
        self.screenChangeVisibilityTask?.cancel()
        self.iconHeartbeatTask?.cancel()
        self.pendingScreenChangePreviousCount = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
