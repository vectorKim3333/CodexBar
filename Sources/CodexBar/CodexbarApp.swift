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
    /// 1.8.2: 마지막으로 관측한 디스플레이(NSScreenNumber) 집합. 디스플레이가 실제로
    /// 추가/제거됐는지 판정 — 해상도/배치만 바뀐 spurious screenParams 알림은 무시.
    private var lastDisplaySet: Set<UInt32> = []
    private var displayChangeRelaunchTask: Task<Void, Never>?
    /// 디스플레이 구성이 바뀐 뒤 macOS 가 메뉴바를 다시 배치할 시간을 주고 재시작.
    private static let displayChangeSettleDelay: TimeInterval = 2.5
    /// 재시작 loop / 도킹 중 연속 알림 폭주 방지용 최소 간격.
    private static let displayChangeRestartCooldown: TimeInterval = 15
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
        // 파일 로그는 기본 비활성 (`debugFileLoggingEnabled`, 기본 false) — SettingsStore 가
        // 설정값대로 켠다. 강제 활성화하지 않으므로 일반 사용자에겐 로그 파일이 생기지 않는다.
        // 메뉴바 진단이 다시 필요하면:
        //   defaults write com.steipete.codexbar debugFileLoggingEnabled -bool true
        // 후 앱 재시작 → 재현 → ~/Library/Logs/CodexBar/CodexBar.log 의 MENUBAR-DIAG 확인.
        AppNotifications.shared.requestAuthorizationOnStartup()
        self.ensureStatusController()
        self.setupCompanionControllerIfPossible()
        // 1.8.2: 디스플레이 구성 변경 시 메뉴바 항목 재배치를 위한 자동 재시작 감시.
        // baseline 을 현재 화면 집합으로 초기화 → 첫 실제 변경부터 감지 (launch 직후
        // 자기 자신을 재시작하는 loop 방지).
        self.lastDisplaySet = Self.currentDisplaySet()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleDisplayConfigurationChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(self.handleDisplayConfigurationChange),
            name: NSWorkspace.didWakeNotification,
            object: nil)
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
        // 1.8.10: 예전엔 여기서 무조건 `forceRecoverAllMenuBarItems()` (500ms 뒤 process
        // relaunch) 를 호출하고 `showPreferencesWindow:` 셀렉터로 설정을 열려 했다. macOS 13+
        // 에서 그 셀렉터는 `showSettingsWindow:` 로 개명돼 응답자가 없어(sendAction=false)
        // 설정이 안 떴고, 설령 떠도 500ms 뒤 relaunch 가 창을 죽였다 — 즉 "아이콘이 다 사라져
        // Finder 에서 앱을 다시 열어 설정으로 탈출" 이라는 catch-22 escape 의 목적 자체가 깨져
        // 있었다. relaunch 는 1.8.5 에서 본 TCC "다른 앱 데이터 접근" 프롬프트도 유발.
        //
        // 이제는 relaunch 없이 설정만 확실히 연다. keepalive WindowGroup 창(→ env
        // `openSettings()`)은 메뉴바 status item 과 독립적이라 아이콘이 숨겨진 상태에서도
        // 동작하므로, 설정만 열어주면 사용자가 그 안의 "메뉴바 아이콘 복구" 버튼으로 복구할 수
        // 있다 (복구 = 명시적 relaunch, 설정 진입과 분리).
        self.openSettingsFromReopen()
        return true
    }

    /// 확실하게 설정 창을 여는 단일 경로. 주 경로는 keepalive 창을 통한 SwiftUI env action
    /// (`.codexbarOpenSettings` → `HiddenWindowView`), keepalive 창이 없을 극히 드문 경우를
    /// 위해 macOS 버전에 맞는 AppKit 셀렉터를 폴백으로 시도한다.
    @MainActor
    private func openSettingsFromReopen() {
        self.preferencesSelection?.tab = .general
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .codexbarOpenSettings,
            object: nil,
            userInfo: ["tab": PreferencesTab.general.rawValue])
        // Fallback: macOS 13+ 는 showPreferencesWindow: → showSettingsWindow: 로 개명.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        // 어느 경로로 열렸든 창을 앞으로 + 화면 안으로. (keepalive 창이 살아있으면
        // HiddenWindowView 도 같은 일을 하지만, 죽은 경우까지 커버.)
        Task { @MainActor in
            for _ in 0 ..< 20 {
                if PreferencesView.presentSettingsWindowToFront() { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func runProviderLoginFlow(_ provider: UsageProvider) async {
        self.ensureStatusController()
        guard let statusController else { return }
        await statusController.runLoginFlowFromSettings(provider: provider)
    }

    /// 사용자가 "메뉴바 아이콘 복구" 버튼을 클릭했을 때 호출 (환경설정 / Provider 메뉴 /
    /// Companion 메뉴 3곳).
    /// 1.8.2: **무조건 process 재시작.** in-process recreate 는 macOS 다중 디스플레이
    /// orphan / hidden 상태를 못 푸는 게 실측으로 확정됨 — 재생성해도 `screen=nil` 로
    /// 남고, "정상으로 보이는데 숨겨진" 모드는 detection 자체가 불가능. 새 프로세스가
    /// NSStatusBar 에 깨끗이 재등록하는 것만 확실한 복구. detection 없이 항상 재시작.
    @MainActor
    func forceRecoverAllMenuBarItems() {
        AppNotifications.shared.post(
            idPrefix: "menubar-recover",
            title: L("menubar.recover.toast.title"),
            body: L("menubar.recover.toast.body"))
        CodexBarLog.logger(LogCategories.app).error("Manual menu bar recovery; relaunching process")
        // 토스트가 표시될 짧은 시간을 주고 재시작.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.relaunchApp()
        }
    }

    private static func currentDisplaySet() -> Set<UInt32> {
        Set(NSScreen.screens.compactMap {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        })
    }

    /// 1.8.2: 디스플레이가 실제로 추가/제거됐는지 판정 → 변경됐으면 정착 후 자동 재시작 예약.
    /// screenParams 는 해상도/배치 변경 등으로도 자주 발화하므로 NSScreenNumber 집합
    /// 비교로 진짜 구성 변화만 골라낸다. wake 도 같은 경로 (절전 중 외장 모니터 분리 후
    /// 깨어남 등).
    @MainActor
    @objc private func handleDisplayConfigurationChange() {
        let current = Self.currentDisplaySet()
        guard current != self.lastDisplaySet else { return }
        let previous = self.lastDisplaySet
        self.lastDisplaySet = current
        CodexBarLog.logger(LogCategories.app).error(
            "Display set changed; scheduling relaunch",
            metadata: ["from": "\(previous.count) displays", "to": "\(current.count) displays"])
        self.scheduleDisplayChangeRelaunch()
    }

    @MainActor
    private func scheduleDisplayChangeRelaunch() {
        self.displayChangeRelaunchTask?.cancel()
        self.displayChangeRelaunchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.displayChangeSettleDelay))
            guard let self, !Task.isCancelled else { return }
            self.relaunchForDisplayChangeIfSafe()
        }
    }

    @MainActor
    private func relaunchForDisplayChangeIfSafe() {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: "menubar.displayChangeRestart.lastAt")
        guard now - last > Self.displayChangeRestartCooldown else { return }

        // 1.8.5: 디스플레이가 바뀌었어도 아이콘이 실제로 사라지거나 깨지지 않았으면 재시작하지
        // 않는다. ad-hoc 서명 앱은 재시작마다 macOS TCC "다른 앱의 데이터에 접근" 프롬프트가
        // 다시 뜨므로 (자격증명 접근 + 비영구 grant), 무조건 재시작은 도킹/언도킹마다 프롬프트를
        // 유발했다 (사용자 보고). 실제로 깨진 (감지 가능한 — screen=nil / window 없음 / width=0
        // / image 깨짐) 경우에만 재시작해 프롬프트를 최소화한다. "정상으로 보이는데 숨겨진"
        // 미감지 케이스는 사용자가 '메뉴바 아이콘 복구' 버튼 (항상 재시작) 으로 해결.
        let pillBroken = (self.statusController as? StatusItemController)?
            .hasAnyBlockedEnabledStatusItem() ?? false
        let companionBroken = self.companionController?.isStuckWhileUserEnabled() ?? false
        guard pillBroken || companionBroken else {
            CodexBarLog.logger(LogCategories.app).info(
                "Display changed but menu bar items healthy; skip relaunch",
                metadata: ["pillBroken": "\(pillBroken)", "companionBroken": "\(companionBroken)"])
            return
        }

        // 메뉴 열림 / 로그인 진행 중이면 사용자를 방해하지 않도록 잠시 미룬 뒤 재시도.
        if !(self.statusController?.canSafelyRelaunch ?? true) {
            self.displayChangeRelaunchTask?.cancel()
            self.displayChangeRelaunchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.relaunchForDisplayChangeIfSafe()
            }
            return
        }
        defaults.set(now, forKey: "menubar.displayChangeRestart.lastAt")
        CodexBarLog.logger(LogCategories.app).error(
            "Menu bar item broken after display change; relaunching to re-home",
            metadata: ["pillBroken": "\(pillBroken)", "companionBroken": "\(companionBroken)"])
        self.relaunchApp()
    }

    /// 1.7.0: ClCoBar process 자체를 재시작. 새 process 가 NSStatusBar 에 다시 register
    /// 하면서 OS-level stuck 완전 해소. 자동 recovery + manual button 도 못 풀리는
    /// 최종 escape — 사용자가 alert 에서 동의해야 발화 (또는 1.7.2 부터 자동 escalation).
    @MainActor
    func relaunchApp() {
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

    /// 1.7.2: heartbeat 가 호출. 자동 process restart escalation.
    /// 조건:
    ///   - 사용량 pill 또는 Companion 중 하나라도 stuck 이 2분 이상 지속
    ///   - 이전 자동 restart 후 1시간 cooldown 경과
    /// 둘 다 만족하면 시스템 알림 post 후 즉시 process restart.
    /// 사용자가 자리 비웠다 돌아왔을 때 manual button 누를 필요 없이 자동 복구 보장.
    @MainActor
    func autoRestartIfProlongedStuck() {
        let stuckThreshold: TimeInterval = 120  // 2분
        let cooldown: TimeInterval = 3600       // 1시간

        let defaults = UserDefaults.standard
        let lastRestart = defaults.double(forKey: "menubar.autoRestart.lastAt")
        let now = Date().timeIntervalSince1970
        guard now - lastRestart > cooldown else { return }

        let statusStuck = (self.statusController as? StatusItemController)?
            .hasAnyEnabledStuckLongerThan(seconds: stuckThreshold) ?? false
        let companionStuckLong = (self.companionController?.stuckDuration() ?? 0) > stuckThreshold
        guard statusStuck || companionStuckLong else { return }

        // Restart 기록 + 사용자에게 시스템 알림.
        defaults.set(now, forKey: "menubar.autoRestart.lastAt")
        AppNotifications.shared.post(
            idPrefix: "menubar-auto-restart",
            title: L("menubar.restart.auto.title"),
            body: L("menubar.restart.auto.body"))
        // 알림이 표시될 시간 짧게 주고 restart.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.relaunchApp()
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
