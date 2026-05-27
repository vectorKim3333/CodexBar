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
    private static let wakeCheckDelay: TimeInterval = 1.5

    // Companion-owned 5-minute ring buffer
    private var samples: [PlanUtilizationHistoryEntry] = []
    private let sampleWindow: TimeInterval = 300

    var character: CompanionCharacter
    var provider: UsageProvider

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
        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.button?.image = CompanionIconRenderer.render(
            character: self.character, stage: .idle, phase: 0)
        item.button?.action = #selector(self.handleClick)
        item.button?.target = self
        item.menu = self.menuProvider()
        self.statusItem = item
        self.updateButtonMetadata(stage: .idle, burnRate: 0)

        self.driver.onFrame = { [weak self] phase in
            guard let self, let item = self.statusItem else { return }
            item.button?.image = CompanionIconRenderer.render(
                character: self.character, stage: self.driver.stage, phase: phase)
        }
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
    private func startObservation() {
        self.observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshStage()
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

    /// Reads the current weekly usedPercent from UsageStore.snapshots and appends to ring buffer.
    /// Trims samples older than `sampleWindow`.
    private func recordSampleIfPossible(at now: Date) {
        guard let percent = self.currentWeeklyPercent(for: self.provider) else { return }
        self.samples.append(PlanUtilizationHistoryEntry(
            capturedAt: now,
            usedPercent: percent,
            resetsAt: nil))
        let cutoff = now.addingTimeInterval(-self.sampleWindow)
        self.samples.removeAll { $0.capturedAt < cutoff }
    }

    /// Returns the current weekly used-percent from UsageStore.snapshots.
    /// The "secondary" rate window is Claude/Codex weekly. Returns nil if no snapshot yet.
    private func currentWeeklyPercent(for provider: UsageProvider) -> Double? {
        return self.usageStore.snapshots[provider]?.secondary?.usedPercent
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
        let center = NSWorkspace.shared.notificationCenter
        self.wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.wakeCheckDelay))
                self?.recoverIfBlocked()
            }
        }
    }

    private func removeWakeObserver() {
        if let token = self.wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            self.wakeObserver = nil
        }
    }

    /// macOS Tahoe evicts NSStatusItem window/screen after long sleep.
    /// `isVisible=true` 인데 `button.window/screen` 이 nil 인 blocked 상태가 됨.
    /// Stop+start로 statusBar에 새로 등록.
    private func recoverIfBlocked() {
        guard let item = self.statusItem else { return }
        let blocked = item.isVisible && (item.button?.window == nil || item.button?.window?.screen == nil)
        guard blocked else { return }
        let savedCharacter = self.character
        let savedProvider = self.provider
        self.stop()
        self.character = savedCharacter
        self.provider = savedProvider
        self.start()
    }
}
