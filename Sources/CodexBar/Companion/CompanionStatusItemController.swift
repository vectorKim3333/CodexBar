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
    private static let wakeCheckDelay: TimeInterval = 1.5

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
        self.removeWakeObserver()
        self.driver.stop()
        if let item = self.statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.statusItem = nil
        self.samples.removeAll()
    }

    @objc private func handleClick() {
        // NSStatusItem.menu auto-shows.
    }

    /// Polls every 30s — append current weekly usedPercent to ring buffer, recompute stage.
    /// 추가로 매 주기마다 `recoverIfMissingOrBlocked()` 를 호출해 evict 된 status item 을
    /// 자동 복구한다. wake-once 복구만으론 long-uptime / display-only sleep / Tahoe
    /// allow-list 변경 등에서 캐릭터가 사라진 채 안 돌아오는 케이스가 잡히지 않음.
    private func startObservation() {
        self.observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshStage()
                self?.recoverIfMissingOrBlocked()
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
        self.wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // 장시간 deep sleep 후 wake 에선 macOS 가 status bar 재배치하는 시간이
                // 단발 1.5초로 안 잡힐 수 있음. 1.5s + 5s + 15s cascade 로 여러 번 검증.
                // recoverIfMissingOrBlocked 는 idempotent 라 중복 호출 안전.
                try? await Task.sleep(for: .seconds(Self.wakeCheckDelay))
                self?.recoverIfMissingOrBlocked()
                try? await Task.sleep(for: .seconds(5 - Self.wakeCheckDelay))
                self?.recoverIfMissingOrBlocked()
                try? await Task.sleep(for: .seconds(10))
                self?.recoverIfMissingOrBlocked()
            }
        }
        // Display 만 슬립에서 깨어난 경우 (lid open / monitor wake) — 시스템은 awake 였어도
        // 메뉴바 자체가 잠시 evict 되는 케이스가 있어 별도 처리.
        self.screensWakeObserver = workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.wakeCheckDelay))
                self?.recoverIfMissingOrBlocked()
            }
        }
        // 사용자가 ClCoBar 에 focus 를 돌려준 순간 — 클릭 직전에 마지막 sanity check.
        self.appActiveObserver = app.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recoverIfMissingOrBlocked()
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
    }


    /// macOS Tahoe evicts NSStatusItem window/screen after long sleep.
    /// statusItem 이 다음 3가지 상태 중 하나면 복구:
    ///   1. nil (어떤 코드 경로가 stop() 만 호출하고 안 돌아옴)
    ///   2. isVisible=false (외부에서 hidden 처리됨)
    ///   3. isVisible=true 인데 window/screen 이 nil (macOS evict)
    /// 30s observation tick 마다 호출되어 silent 사라짐을 방지한다.
    private func recoverIfMissingOrBlocked() {
        guard let item = self.statusItem else {
            // 컨트롤러는 살아있지만 status item 이 사라진 경우 → 재시작.
            // start() 는 `guard self.statusItem == nil` 가드가 있으므로 안전.
            self.start()
            return
        }
        if !item.isVisible {
            // Companion 컨트롤러가 살아있다는 것 자체가 companionEnabled=true 라는
            // 뜻이므로 즉시 다시 보이게 한다. (AppDelegate 가 companionEnabled=false
            // 일 땐 stop() + nil 처리하므로 여기 도달하지 않음)
            item.isVisible = true
            return
        }
        let blocked = item.button?.window == nil || item.button?.window?.screen == nil
        guard blocked else { return }
        let savedCharacter = self.character
        let savedProvider = self.provider
        self.stop()
        self.character = savedCharacter
        self.provider = savedProvider
        self.start()
    }
}
