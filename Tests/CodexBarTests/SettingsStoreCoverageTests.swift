import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreCoverageTests {
    @Test
    func `provider ordering and caching`() throws {
        let suite = "SettingsStoreCoverageTests-ordering"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .codex),
            ProviderConfig(id: .claude),
        ])
        try configStore.save(config)
        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        let ordered = settings.orderedProviders()
        let cached = settings.orderedProviders()

        #expect(ordered == cached)
        #expect(ordered.contains(.codex))
        #expect(ordered.contains(.claude))

        settings.moveProvider(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(settings.orderedProviders() != ordered)

        let metadata = ProviderRegistry.shared.metadata
        try settings.setProviderEnabled(provider: .codex, metadata: #require(metadata[.codex]), enabled: true)
        try settings.setProviderEnabled(provider: .claude, metadata: #require(metadata[.claude]), enabled: false)
        let enabled = settings.enabledProvidersOrdered(metadataByProvider: metadata)
        #expect(enabled.contains(.codex))
    }

    @Test
    func `disabling selected provider clears menu selection`() throws {
        let settings = Self.makeSettingsStore()
        let metadata = ProviderRegistry.shared.metadata

        try settings.setProviderEnabled(provider: .codex, metadata: #require(metadata[.codex]), enabled: true)
        try settings.setProviderEnabled(provider: .claude, metadata: #require(metadata[.claude]), enabled: true)
        settings.selectedMenuProvider = .claude

        try settings.setProviderEnabled(provider: .claude, metadata: #require(metadata[.claude]), enabled: false)

        #expect(settings.selectedMenuProvider == nil)
        #expect(settings.enabledProvidersOrdered(metadataByProvider: metadata) == [.codex])
    }

    @Test
    func `menu bar metric preferences and display modes`() {
        let settings = Self.makeSettingsStore()

        settings.setMenuBarMetricPreference(.average, for: .codex)
        #expect(settings.menuBarMetricPreference(for: .codex) == .automatic)

        settings.menuBarDisplayMode = .pace
        #expect(settings.menuBarDisplayMode == .pace)
        #expect(settings.historicalTrackingEnabled == false)
        settings.historicalTrackingEnabled = true
        #expect(settings.historicalTrackingEnabled == true)

        settings.resetTimesShowAbsolute = true
        #expect(settings.resetTimeDisplayStyle == .absolute)
    }

    @Test
    func `multi account menu layout persists and bridges legacy show all token accounts`() throws {
        let suite = "SettingsStoreCoverageTests-multi-account-layout"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let initial = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(initial.multiAccountMenuLayout == .segmented)

        initial.multiAccountMenuLayout = .stacked
        #expect(defaults.string(forKey: "multiAccountMenuLayout") == MultiAccountMenuLayout.stacked.rawValue)
        #expect(initial.showAllTokenAccountsInMenu)

        let reloaded = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(reloaded.multiAccountMenuLayout == .stacked)
        reloaded.showAllTokenAccountsInMenu = false
        #expect(reloaded.multiAccountMenuLayout == .segmented)
    }

    @Test
    func `legacy show all token accounts migrates to stacked layout`() throws {
        let suite = "SettingsStoreCoverageTests-legacy-token-account-layout"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "showAllTokenAccountsInMenu")
        let configStore = testConfigStore(suiteName: suite)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)

        #expect(settings.multiAccountMenuLayout == .stacked)
    }

    @Test
    func `token account mutations apply side effects`() {
        let settings = Self.makeSettingsStore()

        settings.addTokenAccount(provider: .claude, label: "Primary", token: "token")
        #expect(settings.tokenAccounts(for: .claude).count == 1)
        #expect(settings.claudeCookieSource == .manual)

        let account = settings.selectedTokenAccount(for: .claude)
        #expect(account != nil)

        settings.setActiveTokenAccountIndex(10, for: .claude)
        #expect(settings.selectedTokenAccount(for: .claude)?.id == account?.id)

        if let id = account?.id {
            settings.removeTokenAccount(provider: .claude, accountID: id)
        }
        #expect(settings.tokenAccounts(for: .claude).isEmpty)

        settings.reloadTokenAccounts()
    }

    @Test
    func `token cost usage source detection`() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "token-cost-\(UUID().uuidString)",
            isDirectory: true)
        let codexRoot = root.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        let codexFile = codexRoot.appendingPathComponent("usage.jsonl")
        fileManager.createFile(atPath: codexFile.path, contents: Data("{}".utf8))

        #expect(SettingsStore.hasAnyTokenCostUsageSources(
            env: ["CODEX_HOME": root.path],
            fileManager: fileManager))

        let claudeRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "claude-\(UUID().uuidString)",
            isDirectory: true)
        let claudeProjects = claudeRoot.appendingPathComponent("projects", isDirectory: true)
        try fileManager.createDirectory(at: claudeProjects, withIntermediateDirectories: true)
        let claudeFile = claudeProjects.appendingPathComponent("usage.jsonl")
        fileManager.createFile(atPath: claudeFile.path, contents: Data("{}".utf8))

        #expect(SettingsStore.hasAnyTokenCostUsageSources(
            env: ["CLAUDE_CONFIG_DIR": claudeRoot.path],
            fileManager: fileManager))
    }

    @Test
    func `keychain disable forces manual cookie sources`() throws {
        let suite = "SettingsStoreCoverageTests-keychain"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)

        settings.codexCookieSource = .auto
        settings.claudeCookieSource = .auto
        settings.debugDisableKeychainAccess = true

        #expect(settings.codexCookieSource == .manual)
        #expect(settings.claudeCookieSource == .manual)
    }

    @Test
    func `claude keychain prompt mode defaults to only on user action`() {
        let settings = Self.makeSettingsStore()
        #expect(settings.claudeOAuthKeychainPromptMode == .onlyOnUserAction)
    }

    @Test
    func `claude keychain prompt mode persists across store reload`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-prompt-mode"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let first = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        first.claudeOAuthKeychainPromptMode = .never
        #expect(
            defaults.string(forKey: "claudeOAuthKeychainPromptMode")
                == ClaudeOAuthKeychainPromptMode.never.rawValue)

        let second = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(second.claudeOAuthKeychainPromptMode == .never)
    }

    @Test
    func `claude keychain prompt mode invalid raw falls back to only on user action`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-prompt-mode-invalid"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("invalid-mode", forKey: "claudeOAuthKeychainPromptMode")
        let configStore = testConfigStore(suiteName: suite)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(settings.claudeOAuthKeychainPromptMode == .onlyOnUserAction)
    }

    @Test
    func `claude keychain read strategy defaults to security CLI experimental`() {
        let settings = Self.makeSettingsStore()
        #expect(settings.claudeOAuthKeychainReadStrategy == .securityCLIExperimental)
    }

    @Test
    func `claude keychain read strategy persists across store reload`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-read-strategy"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let first = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        first.claudeOAuthKeychainReadStrategy = .securityCLIExperimental
        #expect(
            defaults.string(forKey: "claudeOAuthKeychainReadStrategy")
                == ClaudeOAuthKeychainReadStrategy.securityCLIExperimental.rawValue)

        let second = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(second.claudeOAuthKeychainReadStrategy == .securityCLIExperimental)
    }

    @Test
    func `claude keychain read strategy invalid raw falls back to security framework`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-read-strategy-invalid"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("invalid-strategy", forKey: "claudeOAuthKeychainReadStrategy")
        let configStore = testConfigStore(suiteName: suite)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(settings.claudeOAuthKeychainReadStrategy == .securityFramework)
    }

    @Test
    func `claude prompt free credentials toggle maps to read strategy`() {
        let settings = Self.makeSettingsStore()
        #expect(settings.claudeOAuthPromptFreeCredentialsEnabled == true)

        settings.claudeOAuthPromptFreeCredentialsEnabled = false
        #expect(settings.claudeOAuthKeychainReadStrategy == .securityFramework)

        settings.claudeOAuthPromptFreeCredentialsEnabled = true
        #expect(settings.claudeOAuthKeychainReadStrategy == .securityCLIExperimental)
    }

    private static func makeSettingsStore(suiteName: String = "SettingsStoreCoverageTests") -> SettingsStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suiteName)
        return Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
    }

    private static func makeSettingsStore(
        userDefaults: UserDefaults,
        configStore: CodexBarConfigStore) -> SettingsStore
    {
        SettingsStore(
            userDefaults: userDefaults,
            configStore: configStore,
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }
}
