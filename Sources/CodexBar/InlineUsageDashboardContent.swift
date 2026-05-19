import CodexBarCore
import SwiftUI

struct InlineUsageDashboardModel: Equatable {
    struct KPI: Equatable {
        let title: String
        let value: String
        let emphasis: Bool
    }

    struct Point: Equatable, Identifiable {
        let id: String
        let label: String
        let value: Double
        let accessibilityValue: String
    }

    enum ValueStyle: Equatable {
        case currencyUSD
        case currency(symbol: String)
        case tokens
    }

    let accessibilityLabel: String
    let valueStyle: ValueStyle
    let kpis: [KPI]
    let points: [Point]
    let detailLines: [String]
}

extension UsageMenuCardView.Model {
    static func apiProviderUsageNotes(input: Input) -> [String]? {
        return nil
    }

    static func inlineUsageDashboard(input: Input) -> InlineUsageDashboardModel? {
        if input.provider == .claude,
           let usage = input.snapshot?.claudeAdminAPIUsage
        {
            return Self.claudeAdminAPIInlineDashboard(usage)
        }
        if (input.provider == .codex || input.provider == .claude),
           input.tokenCostUsageEnabled,
           let tokenSnapshot = input.tokenSnapshot,
           !tokenSnapshot.daily.isEmpty
        {
            return Self.costHistoryInlineDashboard(provider: input.provider, snapshot: tokenSnapshot)
        }
        return nil
    }

    fileprivate static func claudeAdminAPIInlineDashboard(_ usage: ClaudeAdminAPIUsageSnapshot)
        -> InlineUsageDashboardModel
    {
        let today = usage.latestDay
        let last7 = usage.last7Days
        let last30 = usage.last30Days
        let points = usage.daily.suffix(30).map {
            InlineUsageDashboardModel.Point(
                id: $0.day,
                label: Self.shortDayLabel($0.day),
                value: $0.costUSD,
                accessibilityValue: "\($0.day): \(UsageFormatter.usdString($0.costUSD))")
        }
        var details = [
            "30d: \(UsageFormatter.tokenCountString(last30.totalTokens)) tokens",
            "Cache read: \(UsageFormatter.tokenCountString(last30.cacheReadInputTokens)) tokens",
        ]
        if let topModel = usage.topModels.first {
            details.append(String(format: L("top_model_format"), Self.shortModelName(topModel.name)))
        }
        return InlineUsageDashboardModel(
            accessibilityLabel: "Claude Admin API 30 day spend trend",
            valueStyle: .currencyUSD,
            kpis: [
                .init(title: "Today", value: UsageFormatter.usdString(today.costUSD), emphasis: true),
                .init(title: "7d spend", value: UsageFormatter.usdString(last7.costUSD), emphasis: false),
                .init(
                    title: "30d spend",
                    value: UsageFormatter.usdString(last30.costUSD),
                    emphasis: false),
                .init(
                    title: "Today tokens",
                    value: UsageFormatter.tokenCountString(today.totalTokens),
                    emphasis: false),
            ],
            points: points,
            detailLines: details)
    }

    private static func costHistoryInlineDashboard(
        provider: UsageProvider,
        snapshot: CostUsageTokenSnapshot) -> InlineUsageDashboardModel
    {
        let points = snapshot.daily.suffix(30).compactMap { entry -> InlineUsageDashboardModel.Point? in
            guard let cost = entry.costUSD else { return nil }
            return InlineUsageDashboardModel.Point(
                id: entry.date,
                label: Self.shortDayLabel(entry.date),
                value: cost,
                accessibilityValue: "\(entry.date): \(UsageFormatter.usdString(cost))")
        }
        let latest = snapshot.daily.max { lhs, rhs in lhs.date < rhs.date }
        var details: [String] = []
        if let topModel = Self.topCostModel(from: snapshot.daily) {
            details.append(String(format: L("top_model_format"), Self.shortModelName(topModel)))
        }
        details.append(L(UsageFormatter.costEstimateHint(provider: provider)))
        let providerName = ProviderDefaults.metadata[provider]?.displayName ?? provider.rawValue
        return InlineUsageDashboardModel(
            accessibilityLabel: "\(providerName) 30 day cost trend",
            valueStyle: .currencyUSD,
            kpis: [
                .init(
                    title: "Today",
                    value: latest?.costUSD.map(UsageFormatter.usdString) ?? "—",
                    emphasis: true),
                .init(
                    title: "30d cost",
                    value: snapshot.last30DaysCostUSD.map(UsageFormatter.usdString) ?? "—",
                    emphasis: false),
                .init(
                    title: "30d tokens",
                    value: snapshot.last30DaysTokens.map(UsageFormatter.tokenCountString) ?? "—",
                    emphasis: false),
                .init(
                    title: "Latest tokens",
                    value: latest?.totalTokens.map(UsageFormatter.tokenCountString) ?? "—",
                    emphasis: false),
            ],
            points: points,
            detailLines: details)
    }

    private static func topCostModel(from entries: [CostUsageDailyReport.Entry]) -> String? {
        var scores: [String: (cost: Double, tokens: Int)] = [:]
        for entry in entries {
            for model in entry.modelBreakdowns ?? [] {
                var score = scores[model.modelName] ?? (0, 0)
                score.cost += model.costUSD ?? 0
                score.tokens += model.totalTokens ?? 0
                scores[model.modelName] = score
            }
        }
        return scores.max {
            if $0.value.cost == $1.value.cost { return $0.value.tokens < $1.value.tokens }
            return $0.value.cost < $1.value.cost
        }?.key
    }

    private static func shortDayLabel(_ day: String) -> String {
        let pieces = day.split(separator: "-")
        guard pieces.count == 3, let rawDay = Int(pieces[2]) else { return day }
        return "\(rawDay)"
    }

    private static func shortModelName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 26 else { return trimmed }
        return String(trimmed.prefix(25)) + "…"
    }
}

struct InlineUsageDashboardContent: View {
    private let model: InlineUsageDashboardModel
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(model: InlineUsageDashboardModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.kpis
            MiniUsageBars(model: self.model)
                .frame(height: 58)
                .accessibilityLabel(self.model.accessibilityLabel)
            self.detailLines
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpis: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 118), alignment: .leading),
                GridItem(.flexible(minimum: 100), alignment: .leading),
            ],
            alignment: .leading,
            spacing: 6)
        {
            ForEach(Array(self.model.kpis.enumerated()), id: \.offset) { _, kpi in
                KPIBlock(title: kpi.title, value: kpi.value, emphasis: kpi.emphasis)
            }
        }
    }

    private var detailLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(self.model.detailLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
    }

    private struct KPIBlock: View {
        let title: String
        let value: String
        let emphasis: Bool
        @Environment(\.menuItemHighlighted) private var isHighlighted

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(self.title)
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                Text(self.value)
                    .font(self.emphasis ? .headline : .subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct MiniUsageBars: View {
        let model: InlineUsageDashboardModel
        @Environment(\.menuItemHighlighted) private var isHighlighted

        var body: some View {
            let maxValue = max(self.model.points.map(\.value).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(self.model.points) { point in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.fill(for: point, maxValue: maxValue))
                        .frame(maxWidth: .infinity)
                        .frame(height: self.height(for: point, maxValue: maxValue))
                        .accessibilityLabel(point.accessibilityValue)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.22))
                    .frame(height: 1)
            }
        }

        private func height(for point: InlineUsageDashboardModel.Point, maxValue: Double) -> CGFloat {
            let ratio = point.value / maxValue
            guard ratio > 0 else { return 1 }
            return CGFloat(max(3, min(58, ratio * 58)))
        }

        private func fill(for point: InlineUsageDashboardModel.Point, maxValue: Double) -> Color {
            let ratio = max(0.18, min(1, point.value / maxValue))
            // Always render with the value-style native color; the card no
            // longer flips the chart to white-on-blue on hover because the
            // hover tint was dropped (chart now stays readable on hover).
            switch self.model.valueStyle {
            case .currencyUSD, .currency:
                return Color(red: 0.81, green: 0.56, blue: 0.24).opacity(0.42 + ratio * 0.58)
            case .tokens:
                return Color(red: 0.48, green: 0.41, blue: 0.86).opacity(0.42 + ratio * 0.58)
            }
        }
    }
}
