import CodexBarCore
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension UsageStore {
    /// 1.8.3: 마지막 사용량 snapshot 을 warm-start 캐시에 비동기 저장. 성공한 fetch 마다
    /// 호출 — 다음 cold start (디스플레이 변경 자동 재시작) 에서 즉시 복원해 빈 pill /
    /// "인증 만료" 문구 flash 제거.
    func saveUsageSnapshotCache() {
        let snapshots = self.snapshots
        Task.detached(priority: .utility) {
            UsageSnapshotCache.save(snapshots)
        }
    }

    func persistWidgetSnapshot(reason: String) {
        let snapshot = self.makeWidgetSnapshot()
        // 1.8.3: warm-start 캐시도 같은 시점에 보존 (마지막 사용량 snapshot).
        let usageSnapshots = self.snapshots
        let previousTask = self.widgetSnapshotPersistTask
        self.widgetSnapshotPersistTask = Task { @MainActor in
            _ = await previousTask?.result

            if let override = self._test_widgetSnapshotSaveOverride {
                await override(snapshot)
                return
            }

            await Task.detached(priority: .utility) {
                WidgetSnapshotStore.save(snapshot)
                UsageSnapshotCache.save(usageSnapshots)
            }.value
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    private func makeWidgetSnapshot() -> WidgetSnapshot {
        let enabledProviders = self.enabledProviders()
        let entries = UsageProvider.allCases.compactMap { provider in
            self.makeWidgetEntry(for: provider)
        }
        return WidgetSnapshot(entries: entries, enabledProviders: enabledProviders, generatedAt: Date())
    }

    private func makeWidgetEntry(for provider: UsageProvider) -> WidgetSnapshot.ProviderEntry? {
        guard let snapshot = self.snapshots[provider] else { return nil }

        let tokenSnapshot = self.tokenSnapshots[provider]
        let dailyUsage = tokenSnapshot?.daily.map { entry in
            WidgetSnapshot.DailyUsagePoint(
                dayKey: entry.date,
                totalTokens: entry.totalTokens,
                costUSD: entry.costUSD)
        } ?? []

        let tokenUsage = Self.widgetTokenUsageSummary(from: tokenSnapshot)
        let usageRows = self.widgetUsageRows(provider: provider, snapshot: snapshot)

        let creditsRemaining: Double?
        let codeReviewRemaining: Double?
        if provider == .codex {
            let projection = self.codexConsumerProjection(
                surface: .widget,
                snapshotOverride: snapshot,
                now: snapshot.updatedAt)
            let displayOnlyExtrasHidden = projection.dashboardVisibility == .displayOnly
            creditsRemaining = displayOnlyExtrasHidden ? nil : projection.credits?.remaining
            codeReviewRemaining = displayOnlyExtrasHidden ? nil : projection.remainingPercent(for: .codeReview)
        } else {
            creditsRemaining = nil
            codeReviewRemaining = nil
        }

        return WidgetSnapshot.ProviderEntry(
            provider: provider,
            updatedAt: snapshot.updatedAt,
            primary: snapshot.primary,
            secondary: snapshot.secondary,
            tertiary: snapshot.tertiary,
            usageRows: usageRows,
            creditsRemaining: creditsRemaining,
            codeReviewRemainingPercent: codeReviewRemaining,
            tokenUsage: tokenUsage,
            dailyUsage: dailyUsage)
    }

    private nonisolated static func widgetTokenUsageSummary(
        from snapshot: CostUsageTokenSnapshot?) -> WidgetSnapshot.TokenUsageSummary?
    {
        guard let snapshot else { return nil }
        let fallbackTokens = snapshot.daily.compactMap(\.totalTokens).reduce(0, +)
        let monthTokensValue = snapshot.last30DaysTokens ?? (fallbackTokens > 0 ? fallbackTokens : nil)
        return WidgetSnapshot.TokenUsageSummary(
            sessionCostUSD: snapshot.sessionCostUSD,
            sessionTokens: snapshot.sessionTokens,
            last30DaysCostUSD: snapshot.last30DaysCostUSD,
            last30DaysTokens: monthTokensValue)
    }

    private func widgetUsageRows(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> [WidgetSnapshot.WidgetUsageRowSnapshot]
    {
        let metadata = ProviderDefaults.metadata[provider]
        if provider == .codex {
            let projection = self.codexConsumerProjection(
                surface: .widget,
                snapshotOverride: snapshot,
                now: snapshot.updatedAt)
            return projection.visibleRateLanes.compactMap { lane in
                guard let window = projection.rateWindow(for: lane) else { return nil }
                let title = switch lane {
                case .session:
                    metadata?.sessionLabel ?? "세션"
                case .weekly:
                    metadata?.weeklyLabel ?? "주간"
                }
                return WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: lane.rawValue,
                    title: title,
                    percentLeft: window.remainingPercent)
            }
        }

        let rows: [WidgetSnapshot.WidgetUsageRowSnapshot] = [
            WidgetSnapshot.WidgetUsageRowSnapshot(
                id: "primary",
                title: metadata?.sessionLabel ?? "세션",
                percentLeft: snapshot.primary?.remainingPercent),
            WidgetSnapshot.WidgetUsageRowSnapshot(
                id: "secondary",
                title: metadata?.weeklyLabel ?? "주간",
                percentLeft: snapshot.secondary?.remainingPercent),
        ]
        return rows.filter { $0.percentLeft != nil }
    }
}
