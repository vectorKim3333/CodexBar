import AppKit
import CodexBarCore

extension StatusItemController {
    func tokenAccountMenuDisplay(for provider: UsageProvider) -> TokenAccountMenuDisplay? {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return nil }
        let accounts = self.settings.tokenAccounts(for: provider)
        guard accounts.count > 1 else { return nil }
        let activeIndex = self.settings.tokenAccountsData(for: provider)?.clampedActiveIndex() ?? 0
        return TokenAccountMenuDisplay(
            provider: provider,
            accounts: accounts,
            snapshots: [],
            activeIndex: activeIndex,
            layout: .segmented)
    }

    func codexAccountMenuDisplay(for provider: UsageProvider) -> CodexAccountMenuDisplay? {
        guard provider == .codex else { return nil }
        let projection = self.settings.codexVisibleAccountProjection
        guard projection.visibleAccounts.count > 1 else { return nil }
        return CodexAccountMenuDisplay(
            accounts: projection.visibleAccounts,
            snapshots: [],
            activeVisibleAccountID: projection.activeVisibleAccountID,
            layout: .segmented)
    }

    func stableCodexAccountMenuDisplay(
        _ display: CodexAccountMenuDisplay?,
        menu: NSMenu,
        provider: UsageProvider) -> CodexAccountMenuDisplay?
    {
        guard provider == .codex else { return display }
        guard display == nil else { return display }
        guard self.openMenus[ObjectIdentifier(menu)] != nil else { return display }
        guard menu.items.contains(where: { $0.view is CodexAccountSwitcherView }) else { return display }
        guard let previous = self.lastCodexAccountMenuDisplay, previous.showSwitcher else { return display }
        return previous
    }
}
