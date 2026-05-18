import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct StatusItemExtraUsageMetricTests {
    private func makeStatusBarForTesting() -> NSStatusBar {
        let env = ProcessInfo.processInfo.environment
        if env["GITHUB_ACTIONS"] == "true" || env["CI"] == "true" {
            return .system
        }
        return NSStatusBar()
    }

    @Test
    func `menu bar extra usage preference uses provider cost budget`() {
        let (store, controller) = self.makeController(suiteName: "StatusItemExtraUsageMetricTests-budget")
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: RateWindow(usedPercent: 72, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            providerCost: ProviderCostSnapshot(
                used: 15,
                limit: 100,
                currencyCode: "USD",
                updatedAt: Date()),
            updatedAt: Date())

        store._setSnapshotForTesting(snapshot, provider: .claude)
        store._setErrorForTesting(nil, provider: .claude)

        let window = controller.menuBarMetricWindow(for: .claude, snapshot: snapshot)

        #expect(window?.usedPercent == 15)
    }

    @Test
    func `menu bar extra usage preference returns nil when provider cost budget is missing`() {
        let (store, controller) = self.makeController(suiteName: "StatusItemExtraUsageMetricTests-missing-budget")
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 72, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            providerCost: nil,
            updatedAt: Date())

        store._setSnapshotForTesting(snapshot, provider: .claude)
        store._setErrorForTesting(nil, provider: .claude)

        let window = controller.menuBarMetricWindow(for: .claude, snapshot: snapshot)

        #expect(window == nil)
    }

    private func makeController(suiteName: String) -> (UsageStore, StatusItemController) {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: suiteName),
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.setMenuBarMetricPreference(.extraUsage, for: .claude)

        let registry = ProviderRegistry.shared
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        return (store, controller)
    }
}
