import AppKit
import CodexBarCore
import KeyboardShortcuts
import Observation
import QuartzCore
import Security
import SwiftUI

@main
struct CodexBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var store: UsageStore
    @State private var managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
    @State private var codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    private let preferencesSelection: PreferencesSelection
    private let account: AccountInfo

    init() {
        let env = ProcessInfo.processInfo.environment
        let storedLevel = CodexBarLog.parseLevel(UserDefaults.standard.string(forKey: "debugLogLevel")) ?? .verbose
        let level = CodexBarLog.parseLevel(env["CODEXBAR_LOG_LEVEL"]) ?? storedLevel
        CodexBarLog.bootstrapIfNeeded(.init(
            destination: .oslog(subsystem: "com.steipete.codexbar"),
            level: level,
            json: false))

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let gitCommit = Bundle.main.object(forInfoDictionaryKey: "CodexGitCommit") as? String ?? "unknown"
        let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "CodexBuildTimestamp") as? String ?? "unknown"
        CodexBarLog.logger(LogCategories.app).info(
            "CodexBar starting",
            metadata: [
                "version": version,
                "build": build,
                "git": gitCommit,
                "built": buildTimestamp,
            ])

        KeychainAccessGate.isDisabled = UserDefaults.standard.bool(forKey: "debugDisableKeychainAccess")
        KeychainPromptCoordinator.install()

        let preferencesSelection = PreferencesSelection()
        let settings = SettingsStore()
        Self.applyLanguagePreference(from: settings)
        let managedCodexAccountCoordinator = ManagedCodexAccountCoordinator()
        managedCodexAccountCoordinator.onManagedAccountsDidChange = {
            _ = settings.persistResolvedCodexActiveSourceCorrectionIfNeeded()
        }
        _ = settings.persistResolvedCodexActiveSourceCorrectionIfNeeded()
        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: BrowserDetection.defaultCacheTTL)
        let account = fetcher.loadAccountInfo()
        let store = UsageStore(fetcher: fetcher, browserDetection: browserDetection, settings: settings)
        let codexAccountPromotionCoordinator = CodexAccountPromotionCoordinator(
            settingsStore: settings,
            usageStore: store,
            managedAccountCoordinator: managedCodexAccountCoordinator)
        self.preferencesSelection = preferencesSelection
        _settings = State(wrappedValue: settings)
        _store = State(wrappedValue: store)
        _managedCodexAccountCoordinator = State(wrappedValue: managedCodexAccountCoordinator)
        _codexAccountPromotionCoordinator = State(wrappedValue: codexAccountPromotionCoordinator)
        self.account = account
        CodexBarLog.setLogLevel(settings.debugLogLevel)
        self.appDelegate.configure(.init(
            store: store,
            settings: settings,
            account: account,
            selection: preferencesSelection,
            managedCodexAccountCoordinator: managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: codexAccountPromotionCoordinator))
    }

    @SceneBuilder
    var body: some Scene {
        // Hidden 1×1 window to keep SwiftUI's lifecycle alive so `Settings` scene
        // shows the native toolbar tabs even though the UI is AppKit-based.
        WindowGroup("CodexBarLifecycleKeepalive") {
            HiddenWindowView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            PreferencesView(
                settings: self.settings,
                store: self.store,
                selection: self.preferencesSelection,
                managedCodexAccountCoordinator: self.managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator: self.codexAccountPromotionCoordinator,
                runProviderLoginFlow: { provider in
                    await self.appDelegate.runProviderLoginFlow(provider)
                })
        }
        .defaultSize(width: PreferencesTab.general.preferredWidth, height: PreferencesTab.general.preferredHeight)
        .windowResizability(.contentSize)
    }

    private func openSettings(tab: PreferencesTab) {
        self.preferencesSelection.tab = tab
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    private static func applyLanguagePreference(from settings: SettingsStore) {
        // ClCoBar is Korean-only. Force the AppleLanguages preference so any
        // system-localized APIs (formatters, etc.) also speak Korean.
        _ = settings
        UserDefaults.standard.set(["ko"], forKey: "AppleLanguages")
    }
}


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    struct Dependencies {
        let store: UsageStore
        let settings: SettingsStore
        let account: AccountInfo
        let selection: PreferencesSelection
        let managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
        let codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    }

    private var statusController: StatusItemControlling?
    private var companionController: CompanionStatusItemController?
    private var companionMenuBuilder: CompanionMenuBuilder?
    private var companionObservationTask: Task<Void, Never>?
    private var store: UsageStore?
    private var settings: SettingsStore?
    private var account: AccountInfo?
    private var preferencesSelection: PreferencesSelection?
    private var managedCodexAccountCoordinator: ManagedCodexAccountCoordinator?
    private var codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator?
    func configure(_ dependencies: Dependencies) {
        self.store = dependencies.store
        self.settings = dependencies.settings
        self.account = dependencies.account
        self.preferencesSelection = dependencies.selection
        self.managedCodexAccountCoordinator = dependencies.managedCodexAccountCoordinator
        self.codexAccountPromotionCoordinator = dependencies.codexAccountPromotionCoordinator
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        self.configureAppIconForMacOSVersion()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppNotifications.shared.requestAuthorizationOnStartup()
        self.ensureStatusController()
        self.setupCompanionControllerIfPossible()
        UpdateChecker.shared.start()
        KeyboardShortcuts.onKeyUp(for: .openMenu) { [weak self] in
            Task { @MainActor [weak self] in
                self?.statusController?.openMenuFromShortcut()
            }
        }
        // 1.5.4: 1.5.3 의 `.codexbarProviderConfigDidChange` cross-broker observer 제거.
        // 두 status item 의 동작은 독립적이어야 한다는 사용자 요구사항.
    }

    func applicationWillTerminate(_ notification: Notification) {
        TTYCommandRunner.terminateActiveProcessesForAppShutdown()
    }

    /// 1.6.1: 사용자가 이미 실행 중인 ClCoBar 를 Finder/Spotlight/Launchpad 에서 다시
    /// 열려고 시도하는 시점. catch-22 escape — 메뉴바 아이콘이 모두 사라진 상태에서
    /// 사용자가 메뉴 / ⌘, 도 못 쓸 때의 최종 수단. 환경설정 자동 표시 + status item 강제
    /// 복구. ClCoBar 는 LSUIElement 라 Dock 아이콘 없지만 macOS 가 이 콜백을 발화함.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        self.forceRecoverAllMenuBarItems()
        self.preferencesSelection?.tab = .general
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        return true
    }

    func runProviderLoginFlow(_ provider: UsageProvider) async {
        self.ensureStatusController()
        guard let statusController else { return }
        await statusController.runLoginFlowFromSettings(provider: provider)
    }

    /// 1.6.0: 사용자가 환경설정 / 메뉴의 "메뉴바 아이콘 복구" 버튼을 클릭했을 때 호출.
    /// 1.7.0: 1초 후 health check 추가 — 단일 recreate 로 못 풀리는 OS-level stuck 케이스
    /// 에 사용자에게 process restart 옵션 제공. 우리 코드가 새 NSStatusItem 만들어도
    /// macOS 가 거부하는 상태는 process 재시작이 NSStatusBar 의 registration 을
    /// 완전히 reset 하므로 가장 확실한 escape.
    @MainActor
    func forceRecoverAllMenuBarItems() {
        if let controller = self.statusController as? StatusItemController {
            controller.forceRecreateAllEnabledProviders(reason: "user-manual-recover")
        }
        self.companionController?.forceRecreateIfEnabled()
        AppNotifications.shared.post(
            idPrefix: "menubar-recover",
            title: L("menubar.recover.toast.title"),
            body: L("menubar.recover.toast.body"))
        // Escalation: 1초 후 still unhealthy 면 process restart alert.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.promptRestartIfRecoveryFailed()
        }
    }

    @MainActor
    private func promptRestartIfRecoveryFailed() {
        guard let controller = self.statusController as? StatusItemController else { return }
        guard controller.hasAnyBlockedEnabledStatusItem() else { return }
        let alert = NSAlert()
        alert.messageText = L("menubar.recover.restart.title")
        alert.informativeText = L("menubar.recover.restart.body")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("menubar.recover.restart.confirm"))
        alert.addButton(withTitle: L("menubar.recover.restart.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            self.relaunchApp()
        }
    }

    /// 1.7.0: ClCoBar process 자체를 재시작. 새 process 가 NSStatusBar 에 다시 register
    /// 하면서 OS-level stuck 완전 해소. 자동 recovery + manual button 도 못 풀리는
    /// 최종 escape — 사용자가 alert 에서 동의해야 발화.
    @MainActor
    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", "-a", bundleURL.path]
        try? task.run()
        // 새 process 가 launch 할 시간을 200ms 정도 주고 종료.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exit(0)
        }
    }

    /// Use the classic (non-Liquid Glass) app icon on macOS versions before 26.
    private func configureAppIconForMacOSVersion() {
        if #unavailable(macOS 26) {
            self.applyClassicAppIcon()
        }
    }

    private func applyClassicAppIcon() {
        guard let classicIcon = Self.loadClassicIcon() else { return }
        NSApp.applicationIconImage = classicIcon
    }

    private static func loadClassicIcon() -> NSImage? {
        guard let url = self.classicIconURL(),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        return image
    }

    private static func classicIconURL() -> URL? {
        Bundle.main.url(forResource: "Icon-classic", withExtension: "icns")
    }

    private func ensureStatusController() {
        if self.statusController != nil { return }

        if let store,
           let settings,
           let account,
           let selection = self.preferencesSelection,
           let managedCodexAccountCoordinator,
           let codexAccountPromotionCoordinator
        {
            self.statusController = StatusItemController.factory(
                store,
                settings,
                account,
                selection,
                managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator)
            return
        }

        // Defensive fallback: this should not be hit in normal app lifecycle.
        CodexBarLog.logger(LogCategories.app)
            .error("StatusItemController fallback path used; settings/store mismatch likely.")
        assertionFailure("StatusItemController fallback path used; check app lifecycle wiring.")
        let fallbackSettings = SettingsStore()
        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: BrowserDetection.defaultCacheTTL)
        let fallbackAccount = fetcher.loadAccountInfo()
        let fallbackStore = UsageStore(fetcher: fetcher, browserDetection: browserDetection, settings: fallbackSettings)
        let fallbackManagedCodexAccountCoordinator = ManagedCodexAccountCoordinator()
        let fallbackCodexAccountPromotionCoordinator = CodexAccountPromotionCoordinator(
            settingsStore: fallbackSettings,
            usageStore: fallbackStore,
            managedAccountCoordinator: fallbackManagedCodexAccountCoordinator)
        self.statusController = StatusItemController.factory(
            fallbackStore,
            fallbackSettings,
            fallbackAccount,
            PreferencesSelection(),
            fallbackManagedCodexAccountCoordinator,
            fallbackCodexAccountPromotionCoordinator)
    }

    private func setupCompanionControllerIfPossible() {
        guard
            let settings = self.settings,
            let store = self.store,
            let statusController = self.statusController
        else {
            return
        }
        self.setupCompanionController(settings: settings, store: store, statusController: statusController)
    }

    private func setupCompanionController(
        settings: SettingsStore,
        store: UsageStore,
        statusController: StatusItemControlling)
    {
        // 1.5.5: companionController instance 는 앱 lifetime 동안 한 번만 생성하고
        // 절대 stop+nil 처리하지 않음. 사용자 OFF 는 `setVisible(false)` 로 표현 —
        // NSStatusItem 인스턴스는 그대로 살려두고 isVisible 만 토글. macOS status bar 의
        // add/remove race 가 cross-effect (사용량 pill ↔ Companion) 의 root cause 였음.
        // observation task / wake observer / animation driver 는 그대로 계속 동작.
        // CPU 부담 미미 (30초 tick).
        let updateController: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            if self.companionController == nil {
                // Two-step setup: controller must exist before menuBuilder can reference it.
                var builderRef: CompanionMenuBuilder?
                let controller = CompanionStatusItemController(
                    character: settings.companionCharacter,
                    provider: settings.companionProvider,
                    usageStore: store,
                    menuProvider: { builderRef?.makeMenu() ?? NSMenu() })
                builderRef = CompanionMenuBuilder(
                    controller: controller,
                    settings: settings,
                    usageStore: store)
                controller.start()
                self.companionController = controller
                self.companionMenuBuilder = builderRef
            }
            self.companionController?.character = settings.companionCharacter
            self.companionController?.provider = settings.companionProvider
            // 사용자 토글 반영 — isVisible 토글만, instance lifetime 영구.
            self.companionController?.setVisible(settings.companionEnabled)
        }
        updateController()

        self.companionObservationTask?.cancel()
        self.companionObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                _ = settings.companionEnabled
                _ = settings.companionCharacter
                _ = settings.companionProvider
                try? await Task.sleep(for: .milliseconds(500))
                guard self != nil else { return }
                updateController()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // companionObservationTask is @MainActor-isolated and cannot be accessed here;
        // the task holds only a weak self reference and will terminate naturally on dealloc.
    }
}
