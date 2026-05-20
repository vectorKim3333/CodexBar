import CodexBarCore
import Foundation

extension UsageMenuCardView.Model {
    static func creditsLine(
        metadata: ProviderMetadata,
        credits: CreditsSnapshot?,
        error: String?) -> String?
    {
        guard metadata.supportsCredits else { return nil }
        if let credits {
            return UsageFormatter.creditsString(from: credits.remaining)
        }
        if let error, !error.isEmpty {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return metadata.creditsHint
    }

    static func tokenUsageSection(
        provider: UsageProvider,
        enabled: Bool,
        snapshot: CostUsageTokenSnapshot?,
        error: String?) -> TokenUsageSection?
    {
        guard provider == .codex || provider == .claude else {
            return nil
        }
        guard enabled else { return nil }
        guard let snapshot else { return nil }

        let sessionCost = snapshot.sessionCostUSD.map { UsageFormatter.usdString($0) } ?? "—"
        let sessionTokens = snapshot.sessionTokens.map { UsageFormatter.tokenCountString($0) }
        let sessionLine: String = {
            if let sessionTokens {
                return "오늘: \(sessionCost) · 토큰 \(sessionTokens)"
            }
            return "오늘: \(sessionCost)"
        }()

        let monthCost = snapshot.last30DaysCostUSD.map { UsageFormatter.usdString($0) } ?? "—"
        let fallbackTokens = snapshot.daily.compactMap(\.totalTokens).reduce(0, +)
        let monthTokensValue = snapshot.last30DaysTokens ?? (fallbackTokens > 0 ? fallbackTokens : nil)
        let monthTokens = monthTokensValue.map { UsageFormatter.tokenCountString($0) }
        let monthLine: String = {
            if let monthTokens {
                return "지난 30일: \(monthCost) · 토큰 \(monthTokens)"
            }
            return "지난 30일: \(monthCost)"
        }()
        let err = (error?.isEmpty ?? true) ? nil : error
        return TokenUsageSection(
            sessionLine: sessionLine,
            monthLine: monthLine,
            hintLine: Self.tokenUsageHint(provider: provider),
            errorLine: err,
            errorCopyText: (error?.isEmpty ?? true) ? nil : error)
    }

    static func tokenUsageHint(provider: UsageProvider) -> String? {
        switch provider {
        case .codex:
            "선택한 계정의 로컬 Codex 로그 기준 추정치."
        case .claude:
            UsageFormatter.costEstimateHint(provider: provider)
        }
    }

    static func providerCostSection(
        provider: UsageProvider,
        cost: ProviderCostSnapshot?) -> ProviderCostSection?
    {
        guard let cost else { return nil }

        if provider == .claude, cost.limit <= 0 {
            let spend = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
            let periodLabel = cost.period ?? "지난 30일"
            return ProviderCostSection(
                title: "API 지출",
                percentUsed: nil,
                spendLine: "\(periodLabel): \(spend)",
                percentLine: nil)
        }

        guard cost.limit > 0 else { return nil }

        let used: String
        let limit: String
        let title: String

        if cost.currencyCode == "Quota" {
            title = "할당량 사용"
            used = String(format: "%.0f", cost.used)
            limit = String(format: "%.0f", cost.limit)
        } else {
            title = "추가 사용량"
            used = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
            limit = UsageFormatter.currencyString(cost.limit, currencyCode: cost.currencyCode)
        }

        let percentUsed = Self.clamped((cost.used / cost.limit) * 100)
        let periodLabel = cost.period ?? "이번 달"

        return ProviderCostSection(
            title: title,
            percentUsed: percentUsed,
            spendLine: "\(periodLabel): \(used) / \(limit)",
            percentLine: String(format: "%.0f%% 사용", min(100, max(0, percentUsed))))
    }

    static func clamped(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
