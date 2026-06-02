// Sources/CodexBar/Companion/CompanionStatusItemController.swift
import AppKit
import CodexBarCore
import Foundation
import Observation

@MainActor
final class CompanionStatusItemController {
    private(set) var statusItem: NSStatusItem?
    private let driver = CompanionAnimationDriver()
    private let menuProvider: () -> NSMenu
    private let usageStore: UsageStore
    private let calculator = BurnRateCalculator()
    private var observationTask: Task<Void, Never>?
    private var lastStageChangeAt: Date = .distantPast
    private var lastStage: CompanionPaceStage?
    private var wakeObserver: NSObjectProtocol?
    private var screensWakeObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var screenParamsObserver: NSObjectProtocol?
    private static let wakeCheckDelay: TimeInterval = 1.5

    /// 사용자가 명시적으로 OFF 한 상태인지. watchdog (`performRecovery`) 가
    /// 사용자 OFF 와 macOS evict 를 구분하는 데 사용 — `false` 면 visibility 강제 복구
    /// 안 함. AppDelegate 가 `setVisible(_:)` 로 set.
    private var userEnabled: Bool = true
    /// 1.7.2: stuck 진입 timestamp. `performRecovery()` 가 set/clear.
    /// 자동 process restart escalation 판단에 사용.
    private var stuckSince: Date?
    /// 1.8.0: wake / screen-change / app-active burst 를 단일 복구 패스로 합치는 coalescer.
    private var pendingRecoveryTask: Task<Void, Never>?
    /// 1.8.0: 마지막 recreate (stop+start = removeStatusItem) 시점. cooldown 안에선 재호출
    /// 돼도 다시 removeStatusItem 안 함.
    private var lastRecreateAt: Date?
    private static let recreateCooldown: TimeInterval = 30
    /// 비파괴 redraw 로 안 풀린 채 이 시간 이상 지속되면 recreate 승격.
    private static let redrawEscalationThreshold: TimeInterval = 20

    // Companion-owned 5-minute ring buffer
    private var samples: [PlanUtilizationHistoryEntry] = []
    private let sampleWindow: TimeInterval = 300

    var character: CompanionCharacter {
        didSet {
            guard oldValue != self.character else { return }
            // 캐릭터별 frameCount 가 다를 수 있으므로 driver 재구성.
            self.driver.configure(frameCount: CompanionSpriteFrameRenderer.frameCount(for: self.character))
            // 즉시 신규 캐릭터의 첫 프레임으로 button image 교체 (1 tick 대기 없이).
            if let item = self.statusItem {
                item.button?.image = CompanionSpriteFrameRenderer.render(
                    character: self.character, frameIndex: 0)
            }
        }
    }
    var provider: UsageProvider

    var currentStage: CompanionPaceStage { self.lastStage ?? .idle }
    var lastSampleAt: Date? { self.samples.last?.capturedAt }
    private(set) var currentBurnRate: Double = 0

    init(character: CompanionCharacter,
         provider: UsageProvider,
         usageStore: UsageStore,
         menuProvider: @escaping () -> NSMenu)
    {
        self.character = character
        self.provider = provider
        self.usageStore = usageStore
        self.menuProvider = menuProvider
    }

    func start() {
        guard self.statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 1.8.7: 좁은(노치) 메뉴바에서 캐릭터가 overflow 로 잘려 안 보일 때, 사용자가 ⌘-드래그로
        // 위치를 옮겨 빼낼 수 있다. autosaveName 이 없으면 잦은 재시작(디스플레이 변경/heartbeat
        // 등)마다 위치가 초기화돼 다시 잘린다. 이름을 주면 macOS 가 위치를 기억해 수동 복구가 유지됨.
        item.autosaveName = "ClCoBar.companion"
        item.button?.image = CompanionSpriteFrameRenderer.render(
            character: self.character, frameIndex: 0)
        item.button?.action = #selector(self.handleClick)
        item.button?.target = self
        item.menu = self.menuProvider()
        self.statusItem = item
        self.updateButtonMetadata(stage: .idle, burnRate: 0)

        self.driver.onFrame = { [weak self] frameIndex in
            guard let self, let item = self.statusItem else { return }
            item.button?.image = CompanionSpriteFrameRenderer.render(
                character: self.character, frameIndex: frameIndex)
        }
        self.driver.configure(frameCount: CompanionSpriteFrameRenderer.frameCount(for: self.character))
        self.driver.start()
        self.observeSystemWake()
        self.startObservation()
    }

    func stop() {
        self.observationTask?.cancel()
        self.observationTask = nil
        self.pendingRecoveryTask?.cancel()
        self.pendingRecoveryTask = nil
        self.removeWakeObserver()
        self.driver.stop()
        if let item = self.statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.statusItem = nil
        self.samples.removeAll()
    }

    /// 사용자 토글 상태 반영 — 1.5.5 부터 토글 OFF 시에도 controller instance / NSStatusItem
    /// 은 유지하고 `isVisible` 만 토글. macOS status bar 의 add/remove race 차단.
    ///
    /// `userEnabled` flag 도 같이 set 해서 watchdog 이 사용자 OFF 와 macOS evict 를 구분.
    ///
    /// 1.5.6: visible=true 호출 시 기존 statusItem 이 unhealthy 상태 (button.window/image
    /// 가 nil 또는 image.size 가 zero) 면 즉시 강제 재생성. 사용자가 메뉴에서 OFF/ON 해도
    /// 안 보이던 stuck 케이스 직접 복구.
    func setVisible(_ visible: Bool) {
        self.userEnabled = visible
        if visible {
            if self.statusItem == nil {
                self.start()
                return
            }
            if !self.isStatusItemHealthy() {
                self.recreateStatusItem()
                return
            }
            self.statusItem?.isVisible = true
        } else {
            self.statusItem?.isVisible = false
        }
    }

    /// statusItem 이 macOS 에 정상 등록되어 표시 가능한 상태인지 검증.
    /// 하나라도 missing 이면 stuck 상태 — 강제 재생성 필요.
    private func isStatusItemHealthy() -> Bool {
        guard let item = self.statusItem,
              let button = item.button,
              button.window != nil,
              button.window?.screen != nil,
              let image = button.image,
              image.size.width > 0,
              image.size.height > 0
        else { return false }
        // 1.7.1: image 정상 set 됐는데도 button.frame.width=0 = macOS overflow hide.
        // StatusItemController 의 `isBlockedSnapshot` 과 같은 detection.
        if button.frame.size.width <= 0 { return false }
        return true
    }

    /// 1.7.1: 외부 (AppDelegate) 에서 process restart escalation 시 호출.
    /// userEnabled=true 인데 stuck 상태면 true. 사용자 OFF 한 케이스는 stuck 아님.
    /// 1.8.0: stuckSince 는 `performRecovery()` 가 단독 관리하므로 여기선 read-only.
    func isStuckWhileUserEnabled() -> Bool {
        guard self.userEnabled else { return false }
        return !self.isStatusItemHealthy()
    }

    /// stuck 상태가 시작된 시점부터의 경과 시간. nil 이면 정상.
    func stuckDuration() -> TimeInterval? {
        guard let since = self.stuckSince else { return nil }
        return Date().timeIntervalSince(since)
    }

    /// statusItem 을 통째로 새로 생성. character/provider/userEnabled 상태는 보존.
    /// 1.5.6: display sleep 후 macOS 가 status item 을 reject 한 상태에서 사용자
    /// 토글로 직접 복구 가능하게 하는 escape hatch.
    private func recreateStatusItem() {
        let savedCharacter = self.character
        let savedProvider = self.provider
        let savedEnabled = self.userEnabled
        self.stop()
        self.character = savedCharacter
        self.provider = savedProvider
        self.start()
        self.userEnabled = savedEnabled
        self.statusItem?.isVisible = savedEnabled
    }

    @objc private func handleClick() {
        // NSStatusItem.menu auto-shows.
    }

    /// Polls every 30s — append current weekly usedPercent to ring buffer, recompute stage.
    /// 추가로 매 주기마다 `performRecovery()` 를 호출해 evict 된 status item 을
    /// 자동 복구한다. wake-once 복구만으론 long-uptime / display-only sleep / Tahoe
    /// allow-list 변경 등에서 캐릭터가 사라진 채 안 돌아오는 케이스가 잡히지 않음.
    private func startObservation() {
        self.observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshStage()
                // 1.8.0: steady-state watchdog — coalescer 없이 직접. 비파괴 우선이라 안전.
                self?.performRecovery(reason: "tick")
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func refreshStage() async {
        let now = Date()
        self.recordSampleIfPossible(at: now)

        // (1) Backoff: freeze calculator, keep last stage
        let inBackoff = self.isProviderInBackoff(provider: self.provider, now: now)
        if inBackoff {
            await self.calculator.freeze()
        } else {
            await self.calculator.resume()
        }

        let burn = await self.calculator.update(entries: self.samples, now: now)
        self.currentBurnRate = burn
        let timeSince = now.timeIntervalSince(self.lastStageChangeAt)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let lastSampleAge: TimeInterval = self.samples.last
            .map { now.timeIntervalSince($0.capturedAt) } ?? .greatestFiniteMagnitude
        let stale = lastSampleAge > 300

        let newStage: CompanionPaceStage
        if reduceMotion || stale {
            newStage = .idle
        } else if inBackoff {
            newStage = self.lastStage ?? .idle   // keep last
        } else {
            newStage = CompanionPace.classify(
                burnRate: burn,
                previous: self.lastStage,
                timeSinceLastChange: timeSince)
        }

        if newStage != self.lastStage {
            self.lastStage = newStage
            self.lastStageChangeAt = now
            self.driver.stage = newStage
            self.updateButtonMetadata(stage: newStage, burnRate: burn)
        }
    }

    private func isProviderInBackoff(provider: UsageProvider, now: Date) -> Bool {
        guard let until = self.usageStore.rateLimitBackoffUntil[provider] else { return false }
        return until > now
    }

    /// Reads the current session usedPercent from UsageStore.snapshots and appends to ring buffer.
    /// Trims samples older than `sampleWindow`.
    private func recordSampleIfPossible(at now: Date) {
        guard let percent = self.currentSessionPercent(for: self.provider) else { return }
        self.samples.append(PlanUtilizationHistoryEntry(
            capturedAt: now,
            usedPercent: percent,
            resetsAt: nil))
        let cutoff = now.addingTimeInterval(-self.sampleWindow)
        self.samples.removeAll { $0.capturedAt < cutoff }

    }

    /// Returns the current 5-hour session used-percent from UsageStore.snapshots.
    /// The "primary" rate window is Claude/Codex 5-hour session — best signal for
    /// real-time activity. Weekly (secondary) moves too slowly to drive animation.
    private func currentSessionPercent(for provider: UsageProvider) -> Double? {
        return self.usageStore.snapshots[provider]?.primary?.usedPercent
    }

    private func updateButtonMetadata(stage: CompanionPaceStage, burnRate: Double) {
        guard let button = self.statusItem?.button else { return }
        let providerName = self.provider == .claude ? "Claude" : "Codex"
        if stage == .idle {
            let tip = String(format: NSLocalizedString("companion.tooltip.idle",
                                                       comment: ""), providerName)
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
        } else {
            let stageName = self.stageDisplayName(stage)
            let tip = String(format: NSLocalizedString("companion.tooltip.active",
                                                       comment: ""),
                             providerName, stageName, burnRate)
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
        }
    }

    private func stageDisplayName(_ s: CompanionPaceStage) -> String {
        switch s {
        case .idle:   return NSLocalizedString("companion.stage.idle", comment: "")
        case .slow:   return NSLocalizedString("companion.stage.slow", comment: "")
        case .normal: return NSLocalizedString("companion.stage.normal", comment: "")
        case .fast:   return NSLocalizedString("companion.stage.fast", comment: "")
        case .burst:  return NSLocalizedString("companion.stage.burst", comment: "")
        }
    }

    private func observeSystemWake() {
        let workspace = NSWorkspace.shared.notificationCenter
        let app = NotificationCenter.default
        // System wake (sleep → wake): macOS 가 status item 을 evict 한 가능성이 가장 큼.
        // 1.8.0: 모든 이벤트를 단일 coalescer (`requestRecovery`) 로 보내 burst 를 1회로 합침.
        // 지연값은 사용량 pill (StatusItemController) 보다 의도적으로 더 크게 둬서, 두
        // 컨트롤러가 같은 run-loop 창에서 동시에 removeStatusItem 하지 않게 stagger 한다
        // (사용량 pill: wake 1.5s / screen 0.75s / active 0s, Companion: 2.3s / 1.4s / 0.4s).
        // cross-broker 가 아니라 각자 독립 복구 — 단지 타이밍만 어긋나게.
        self.wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestRecovery(reason: "system-wake", delay: Self.wakeCheckDelay + 0.8)
            }
        }
        self.screensWakeObserver = workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestRecovery(reason: "screens-wake", delay: Self.wakeCheckDelay + 0.8)
            }
        }
        self.appActiveObserver = app.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestRecovery(reason: "app-active", delay: 0.4)
            }
        }
        self.screenParamsObserver = app.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestRecovery(reason: "screen-change", delay: 1.4)
            }
        }
    }

    private func removeWakeObserver() {
        let workspace = NSWorkspace.shared.notificationCenter
        let app = NotificationCenter.default
        if let token = self.wakeObserver {
            workspace.removeObserver(token)
            self.wakeObserver = nil
        }
        if let token = self.screensWakeObserver {
            workspace.removeObserver(token)
            self.screensWakeObserver = nil
        }
        if let token = self.appActiveObserver {
            app.removeObserver(token)
            self.appActiveObserver = nil
        }
        if let token = self.screenParamsObserver {
            app.removeObserver(token)
            self.screenParamsObserver = nil
        }
    }


    /// 1.8.0: wake / screen-change / app-active burst 용 coalescing 진입점.
    /// cancel + reschedule 로 1회 패스로 합침. 사용량 pill 보다 늦은 지연으로 stagger.
    private func requestRecovery(reason: String, delay: TimeInterval) {
        self.pendingRecoveryTask?.cancel()
        self.pendingRecoveryTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard let self, !Task.isCancelled else { return }
            self.performRecovery(reason: reason)
        }
    }

    /// **비파괴 우선** 복구. macOS Tahoe 는 long sleep / overflow 시 status item 을 다양한
    /// 단계로 망가뜨린다. 이전 (1.5.6~1.7.x) 엔 wake / screen-change 마다 무조건 stop+start
    /// (= removeStatusItem) 으로 재생성했는데, 사용량 pill 도 같은 타이밍에 그러면서
    /// status bar add→remove→add race 가 일어나 한쪽이 사라졌다. 이제 다음 순서로 복구:
    ///
    ///   1. statusItem == nil           → start() (최초 생성)
    ///   2. isVisible == false (ON인데)  → isVisible = true 토글 (비파괴)
    ///   3. window 살아있고 width=0/image 깨짐 → image 재설정 (비파괴, removeStatusItem 없음)
    ///   4. window/screen nil = 진짜 evict, 또는 비파괴로 오래 안 풀림 → recreate (cooldown)
    private func performRecovery(reason: String) {
        // 1.8.1 진단: Companion status item geometry 덤프 (캐릭터는 생존하는데 pill 만
        // 사라지는 비대칭 검증용).
        if let item = self.statusItem {
            CodexBarLog.logger(LogCategories.app).info(
                "MENUBAR-DIAG companion reason=\(reason) userEnabled=\(self.userEnabled) :: "
                    + MenuBarVisibilityWatcher.diagnosticDescription(item))
        } else {
            CodexBarLog.logger(LogCategories.app).info(
                "MENUBAR-DIAG companion reason=\(reason) userEnabled=\(self.userEnabled) :: <no statusItem>")
        }
        // 사용자가 명시적으로 OFF 한 상태면 어떤 복구도 안 함. 토글 무시 방지.
        guard self.userEnabled else {
            self.stuckSince = nil
            return
        }
        guard let item = self.statusItem else {
            self.start()
            self.stuckSince = nil
            return
        }
        if !item.isVisible {
            item.isVisible = true
            self.stuckSince = nil
            return
        }
        let button = item.button
        let windowEvicted = button?.window == nil || button?.window?.screen == nil
        let imageBroken = (button?.image?.size.width ?? 0) <= 0 || (button?.image?.size.height ?? 0) <= 0
        let widthCollapsed = (button?.frame.size.width ?? 0) <= 0

        guard windowEvicted || imageBroken || widthCollapsed else {
            self.stuckSince = nil
            return
        }
        if self.stuckSince == nil { self.stuckSince = Date() }
        let stuckFor = self.stuckSince.map { Date().timeIntervalSince($0) } ?? 0

        // 진짜 evict (window nil) 거나, 비파괴로 충분히 시도해도 안 풀림 → recreate (cooldown).
        if windowEvicted || stuckFor > Self.redrawEscalationThreshold {
            if let last = self.lastRecreateAt,
               Date().timeIntervalSince(last) < Self.recreateCooldown
            {
                return
            }
            self.lastRecreateAt = Date()
            self.recreateStatusItem()
            return
        }
        // window 는 살아있는데 image 깨짐 / width=0 → 비파괴 redraw. removeStatusItem 없음.
        button?.image = CompanionSpriteFrameRenderer.render(character: self.character, frameIndex: 0)
        item.isVisible = true
        _ = reason
    }
}
