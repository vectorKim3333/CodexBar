import CodexBarCore
import Commander
import Testing
@testable import CodexBarCLI

struct CLIConfigCommandTests {
    @Test
    func `config set api key parses provider stdin and no enable flags`() throws {
        let parser = CommandParser(signature: CodexBarCLI._configSetAPIKeySignatureForTesting())
        let parsed = try parser.parse(arguments: [
            "--provider", "claude",
            "--stdin",
            "--no-enable",
            "--json",
        ])

        #expect(parsed.options["provider"] == ["claude"])
        #expect(parsed.flags.contains("stdin"))
        #expect(parsed.flags.contains("noEnable"))
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .json)
    }

    @Test
    func `config set api key stores key and enables provider`() {
        let config = CodexBarConfig.makeDefault()
        let updated = CodexBarCLI.configSettingAPIKey(
            config,
            provider: .claude,
            apiKey: "sk-ant-test-token",
            enableProvider: true)
        let provider = updated.providerConfig(for: .claude)

        #expect(provider?.sanitizedAPIKey == "sk-ant-test-token")
        #expect(provider?.enabled == true)
    }

    @Test
    func `config provider toggle parses provider and json flags`() throws {
        let parser = CommandParser(signature: CodexBarCLI._configProviderToggleSignatureForTesting())
        let parsed = try parser.parse(arguments: [
            "--provider", "claude",
            "--json",
            "--pretty",
        ])

        #expect(parsed.options["provider"] == ["claude"])
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .json)
        #expect(parsed.flags.contains("pretty"))
    }

    @Test
    func `config provider toggle enables and disables provider`() {
        let config = CodexBarConfig.makeDefault()
        let enabled = CodexBarCLI.configSettingProviderEnabled(config, provider: .claude, enabled: true)
        let disabled = CodexBarCLI.configSettingProviderEnabled(enabled, provider: .claude, enabled: false)

        #expect(enabled.providerConfig(for: .claude)?.enabled == true)
        #expect(disabled.providerConfig(for: .claude)?.enabled == false)
    }

    @Test
    func `config provider status includes effective default`() throws {
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .claude, enabled: true),
            ProviderConfig(id: .codex, enabled: false),
        ])
        let statuses = CodexBarCLI.configProviderStatuses(config)
        let claude = try #require(statuses.first { $0.provider == "claude" })
        let codex = try #require(statuses.first { $0.provider == "codex" })

        #expect(claude.enabled)
        #expect(!codex.enabled)
        #expect(statuses.count == UsageProvider.allCases.count)
    }

    @Test
    func `config set api key only accepts consumed config keys`() {
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .claude))
        #expect(!ProviderConfigEnvironment.supportsAPIKeyOverride(for: .codex))
    }

    @Test
    func `config set api key preserves disabled provider when requested`() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .claude, enabled: false))

        let updated = CodexBarCLI.configSettingAPIKey(
            config,
            provider: .claude,
            apiKey: "sk-ant-test-token",
            enableProvider: false)
        let provider = updated.providerConfig(for: .claude)

        #expect(provider?.sanitizedAPIKey == "sk-ant-test-token")
        #expect(provider?.enabled == false)
    }

    @Test
    func `config set api key rejects ambiguous input`() {
        #expect(throws: CLIArgumentError.self) {
            try CodexBarCLI.resolveConfigAPIKeyInput(apiKey: "sk-ant-test-token", readFromStdin: true)
        }
    }

    @Test
    func `config help documents set api key`() {
        let help = CodexBarCLI.configHelp(version: "0.0.0")

        #expect(help.contains("config set-api-key --provider <name>"))
        #expect(help.contains("config providers"))
        #expect(help.contains("config enable --provider <name>"))
        #expect(help.contains("config disable --provider <name>"))
        #expect(help.contains("--stdin"))
        #expect(help.contains("enables that provider by default"))
    }
}
