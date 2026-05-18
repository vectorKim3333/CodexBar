import CodexBarCore
import Foundation
import Testing

struct ConfigValidationTests {
    @Test
    func `reports unsupported source`() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .codex, source: .api))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(issues.contains(where: { $0.code == "unsupported_source" }))
    }

    @Test
    func `reports missing API key when source API`() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .claude, source: .api, apiKey: nil))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(issues.contains(where: { $0.code == "api_key_missing" }))
    }

    @Test
    func `warns on unsupported token accounts`() {
        let accounts = ProviderTokenAccountData(
            version: 1,
            accounts: [ProviderTokenAccount(id: UUID(), label: "a", token: "t", addedAt: 0, lastUsed: nil)],
            activeIndex: 0)
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .codex, tokenAccounts: accounts))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(issues.contains(where: { $0.code == "token_accounts_unused" }))
    }

    @Test
    func `config store default url honors environment override`() {
        let url = CodexBarConfigStore.defaultURL(environment: [
            CodexBarConfigStore.pathEnvironmentKey: "~/tmp/codexbar-test-config.json",
        ])

        #expect(url.path.hasSuffix("/tmp/codexbar-test-config.json"))
    }
}
