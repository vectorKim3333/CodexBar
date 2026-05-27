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

        self.driver.onFrame = { [weak self] phase in
            guard let self, let item = self.statusItem else { return }
            item.button?.image = CompanionIconRenderer.render(
                character: self.character, stage: self.driver.stage, phase: phase)
        }
        self.driver.start()
        self.startObservation()
    }

    func stop() {
        self.observationTask?.cancel()
        self.observationTask = nil
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
        let burn = await self.calculator.update(entries: self.samples, now: now)
        let timeSince = now.timeIntervalSince(self.lastStageChangeAt)
        let newStage = CompanionPace.classify(
            burnRate: burn,
            previous: self.lastStage,
            timeSinceLastChange: timeSince)
        if newStage != self.lastStage {
            self.lastStage = newStage
            self.lastStageChangeAt = now
            self.driver.stage = newStage
        }
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
}
