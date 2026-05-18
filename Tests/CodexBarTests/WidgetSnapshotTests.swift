import Foundation
import Testing
@testable import CodexBarCore

struct WidgetSnapshotTests {
    @Test
    func `widget snapshot round trip`() throws {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: Date(),
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "session", title: "Session", percentLeft: 90),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "weekly", title: "Weekly", percentLeft: 80),
            ],
            creditsRemaining: 123.4,
            codeReviewRemainingPercent: 80,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 12.3,
                sessionTokens: 1200,
                last30DaysCostUSD: 456.7,
                last30DaysTokens: 9800),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-20", totalTokens: 1200, costUSD: 12.3),
            ])

        let snapshot = WidgetSnapshot(
            entries: [entry],
            enabledProviders: [.codex, .claude],
            generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries.first?.provider == .codex)
        #expect(decoded.entries.first?.tokenUsage?.sessionTokens == 1200)
        #expect(decoded.entries.first?.usageRows?.map(\.id) == ["session", "weekly"])
        #expect(decoded.enabledProviders == [.codex, .claude])
    }

    @Test
    func `widget snapshot decodes legacy payload without usage rows`() throws {
        let json = """
        {
          "entries": [
            {
              "provider": "codex",
              "updatedAt": "2026-04-04T06:30:00Z",
              "primary": null,
              "secondary": {
                "usedPercent": 25,
                "windowMinutes": 10080,
                "resetsAt": null,
                "resetDescription": null
              },
              "tertiary": null,
              "creditsRemaining": null,
              "codeReviewRemainingPercent": null,
              "tokenUsage": null,
              "dailyUsage": []
            }
          ],
          "enabledProviders": ["codex"],
          "generatedAt": "2026-04-04T06:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries.first?.usageRows == nil)
        #expect(decoded.entries.first?.secondary?.usedPercent == 25)
    }
}
