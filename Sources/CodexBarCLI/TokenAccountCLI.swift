import CodexBarCore
import Commander
import Foundation

struct TokenAccountCLISelection {
    let label: String?
    let index: Int?
    let allAccounts: Bool

    var usesOverride: Bool {
        self.label != nil || self.index != nil || self.allAccounts
    }
}

enum TokenAccountCLIError: LocalizedError {
    case noAccounts(UsageProvider)
    case accountNotFound(UsageProvider, String)
    case indexOutOfRange(UsageProvider, Int, Int)

    var errorDescription: String? {
        switch self {
        case let .noAccounts(provider):
            "No token accounts configured for \(provider.rawValue)."
        case let .accountNotFound(provider, label):
            "No token account labeled '\(label)' for \(provider.rawValue)."
        case let .indexOutOfRange(provider, index, count):
            "Token account index \(index) out of range for \(provider.rawValue) (1-\(count))."
        }
    }
}

struct TokenAccountCLIContext {
    let selection: TokenAccountCLISelection
    let config: CodexBarConfig
    let accountsByProvider: [UsageProvider: ProviderTokenAccountData]
    private let baseEnvironment: [String: String]
    private let managedCodexAccountStoreURL: URL?

    init(
        selection: TokenAccountCLISelection,
        config: CodexBarConfig,
        verbose _: Bool,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        managedCodexAccountStoreURL: URL? = nil) throws
    {
        self.selection = selection
        self.config = config
        self.baseEnvironment = baseEnvironment
        self.managedCodexAccountStoreURL = managedCodexAccountStoreURL
        self.accountsByProvider = Dictionary(uniqueKeysWithValues: config.providers.compactMap { provider in
            guard let accounts = provider.tokenAccounts else { return nil }
            return (provider.id, accounts)
        })
    }

    func resolvedAccounts(for provider: UsageProvider) throws -> [ProviderTokenAccount] {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return [] }
        guard let data = self.accountsByProvider[provider], !data.accounts.isEmpty else {
            if self.selection.usesOverride {
                throw TokenAccountCLIError.noAccounts(provider)
            }
            return []
        }

        if self.selection.allAccounts {
            return data.accounts
        }

        if let label = self.selection.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            let normalized = label.lowercased()
            if let match = data.accounts.first(where: { $0.label.lowercased() == normalized }) {
                return [match]
            }
            throw TokenAccountCLIError.accountNotFound(provider, label)
        }

        if let index = self.selection.index {
            guard index >= 0, index < data.accounts.count else {
                throw TokenAccountCLIError.indexOutOfRange(provider, index + 1, data.accounts.count)
            }
            return [data.accounts[index]]
        }

        let clamped = data.clampedActiveIndex()
        return [data.accounts[clamped]]
    }

    func settingsSnapshot(
        for provider: UsageProvider,
        account: ProviderTokenAccount?,
        codexActiveSourceOverride: CodexActiveSource? = nil) -> ProviderSettingsSnapshot?
    {
        let config = self.providerConfig(for: provider)
        if let snapshot = self.makeCookieBackedSnapshot(provider: provider, account: account, config: config) {
            return snapshot
        }

        switch provider {
        case .codex:
            return self.makeSnapshot(codex: self.makeCodexSettingsSnapshot(
                account: account,
                codexActiveSourceOverride: codexActiveSourceOverride))
        case .claude:
            let routing = self.claudeCredentialRouting(account: account, config: config)
            let claudeSource: ClaudeUsageDataSource = if routing.adminAPIKey != nil {
                .api
            } else if routing.isOAuth {
                .oauth
            } else {
                .auto
            }
            let cookieSource = routing.isOAuth || routing.adminAPIKey != nil
                ? ProviderCookieSource.off
                : self.cookieSource(provider: provider, account: account, config: config)
            return self.makeSnapshot(
                claude: ProviderSettingsSnapshot.ClaudeProviderSettings(
                    usageDataSource: claudeSource,
                    webExtrasEnabled: false,
                    cookieSource: cookieSource,
                    manualCookieHeader: routing.manualCookieHeader,
                    organizationID: account?.sanitizedOrganizationID))
        }
    }

    private func makeCookieBackedSnapshot(
        provider: UsageProvider,
        account: ProviderTokenAccount?,
        config: ProviderConfig?) -> ProviderSettingsSnapshot?
    {
        return nil
    }

    private func makeSnapshot(
        codex: ProviderSettingsSnapshot.CodexProviderSettings? = nil,
        claude: ProviderSettingsSnapshot.ClaudeProviderSettings? = nil) -> ProviderSettingsSnapshot
    {
        ProviderSettingsSnapshot.make(codex: codex, claude: claude)
    }

    private func makeCodexSettingsSnapshot(
        account: ProviderTokenAccount?,
        codexActiveSourceOverride: CodexActiveSource? = nil) ->
        ProviderSettingsSnapshot.CodexProviderSettings
    {
        let config = self.providerConfig(for: .codex)
        let reconciliationSnapshot = self.codexAccountReconciler(
            activeSource: codexActiveSourceOverride).loadSnapshot()
        let resolvedActiveSource = CodexActiveSourceResolver.resolve(from: reconciliationSnapshot)
        return CodexProviderSettingsBuilder.make(input: CodexProviderSettingsBuilderInput(
            usageDataSource: .auto,
            cookieSource: self.cookieSource(provider: .codex, account: account, config: config),
            manualCookieHeader: self.manualCookieHeader(provider: .codex, account: account, config: config),
            reconciliationSnapshot: reconciliationSnapshot,
            resolvedActiveSource: resolvedActiveSource))
    }

    func environment(
        base: [String: String],
        provider: UsageProvider,
        account: ProviderTokenAccount?,
        codexActiveSourceOverride: CodexActiveSource? = nil) -> [String: String]
    {
        let providerConfig = self.providerConfig(for: provider)
        var env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: base,
            provider: provider,
            config: providerConfig)
        // If token account is selected, use its token instead of config's apiKey
        if let account {
            TokenAccountSupportCatalog.scrubEnvironmentForSelectedAccount(
                &env,
                provider: provider,
                token: account.token)
            if let override = TokenAccountSupportCatalog.envOverride(for: provider, token: account.token) {
                for (key, value) in override {
                    env[key] = value
                }
            }
        }
        if provider == .codex,
           let managedAccount = self.managedCodexAccount(for: codexActiveSourceOverride)
        {
            env = CodexHomeScope.scopedEnvironment(base: env, codexHome: managedAccount.managedHomePath)
        }
        return env
    }

    func fetcher(base: UsageFetcher, provider: UsageProvider, env: [String: String]) -> UsageFetcher {
        guard provider == .codex else { return base }
        return UsageFetcher(environment: env)
    }

    func visibleCodexAccounts() -> CodexVisibleAccountProjection {
        self.codexAccountReconciler().loadVisibleAccounts()
    }

    func applyAccountLabel(
        _ snapshot: UsageSnapshot,
        provider: UsageProvider,
        account: ProviderTokenAccount) -> UsageSnapshot
    {
        let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return snapshot }
        let existing = snapshot.identity(for: provider)
        let email = existing?.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmail = (email?.isEmpty ?? true) ? label : email
        let identity = ProviderIdentitySnapshot(
            providerID: provider,
            accountEmail: resolvedEmail,
            accountOrganization: existing?.accountOrganization,
            loginMethod: existing?.loginMethod)
        return snapshot.withIdentity(identity)
    }

    func applyCodexVisibleAccountLabel(_ snapshot: UsageSnapshot, account: CodexVisibleAccount) -> UsageSnapshot {
        let existing = snapshot.identity(for: .codex)
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: account.email,
            accountOrganization: account.workspaceLabel ?? existing?.accountOrganization,
            loginMethod: existing?.loginMethod)
        return snapshot.withIdentity(identity)
    }

    func effectiveSourceMode(
        base: ProviderSourceMode,
        provider: UsageProvider,
        account: ProviderTokenAccount?) -> ProviderSourceMode
    {
        guard provider == .claude else {
            return base
        }
        let config = self.providerConfig(for: provider)
        let routing = self.claudeCredentialRouting(account: account, config: config)

        if base == .auto {
            if routing.adminAPIKey != nil { return .api }
            return routing.isOAuth ? .oauth : base
        }

        guard base == .cli, account != nil else {
            return base
        }

        // Claude CLI usage is ambient to the active local CLI profile, so per-token-account
        // CLI reads can be mislabeled as separate accounts. Use the selected account's
        // routable credential instead.
        switch routing {
        case .adminAPIKey:
            return .api
        case .oauth:
            return .oauth
        case .webCookie:
            return .web
        case .none:
            return base
        }
    }

    func preferredSourceMode(for provider: UsageProvider) -> ProviderSourceMode {
        let config = self.providerConfig(for: provider)
        return config?.source ?? .auto
    }

    private func providerConfig(for provider: UsageProvider) -> ProviderConfig? {
        self.config.providerConfig(for: provider)
    }

    private func codexAccountReconciler(activeSource: CodexActiveSource? = nil) -> DefaultCodexAccountReconciler {
        let storeLoader: @Sendable () throws -> ManagedCodexAccountSet = if let managedCodexAccountStoreURL {
            {
                try FileManagedCodexAccountStore(fileURL: managedCodexAccountStoreURL).loadAccounts()
            }
        } else {
            {
                try FileManagedCodexAccountStore().loadAccounts()
            }
        }
        return DefaultCodexAccountReconciler(
            storeLoader: storeLoader,
            activeSource: activeSource ?? self.providerConfig(for: .codex)?.codexActiveSource ?? .liveSystem,
            baseEnvironment: self.baseEnvironment,
            managedEnvironmentBuilder: { environment, account in
                CodexHomeScope.scopedEnvironment(base: environment, codexHome: account.managedHomePath)
            })
    }

    private func managedCodexAccount(for activeSourceOverride: CodexActiveSource?) -> ManagedCodexAccount? {
        let activeSource: CodexActiveSource = if let activeSourceOverride {
            activeSourceOverride
        } else {
            CodexActiveSourceResolver.resolve(from: self.codexAccountReconciler().loadSnapshot())
                .resolvedSource
        }

        guard case let .managedAccount(id) = activeSource else { return nil }
        let accounts: ManagedCodexAccountSet? = if let managedCodexAccountStoreURL {
            try? FileManagedCodexAccountStore(fileURL: managedCodexAccountStoreURL).loadAccounts()
        } else {
            try? FileManagedCodexAccountStore().loadAccounts()
        }
        return accounts?.account(id: id)
    }

    private func manualCookieHeader(
        provider: UsageProvider,
        account: ProviderTokenAccount?,
        config: ProviderConfig?) -> String?
    {
        if let account,
           let support = TokenAccountSupportCatalog.support(for: provider),
           case .cookieHeader = support.injection
        {
            let header = TokenAccountSupportCatalog.normalizedCookieHeader(account.token, support: support)
            return header.isEmpty ? nil : header
        }
        return config?.sanitizedCookieHeader
    }

    private func cookieSource(
        provider: UsageProvider,
        account: ProviderTokenAccount?,
        config: ProviderConfig?) -> ProviderCookieSource
    {
        if account != nil, TokenAccountSupportCatalog.support(for: provider)?.requiresManualCookieSource == true {
            return .manual
        }
        if let override = config?.cookieSource { return override }
        if config?.sanitizedCookieHeader != nil {
            return .manual
        }
        return .auto
    }

    private func claudeCredentialRouting(
        account: ProviderTokenAccount?,
        config: ProviderConfig?) -> ClaudeCredentialRouting
    {
        let manualCookieHeader = account == nil ? config?.sanitizedCookieHeader : nil
        return ClaudeCredentialRouting.resolve(
            tokenAccountToken: account?.token,
            manualCookieHeader: manualCookieHeader)
    }
}
