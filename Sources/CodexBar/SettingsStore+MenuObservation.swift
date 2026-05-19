import Foundation

extension SettingsStore {
    var menuObservationToken: Int {
        _ = self.providerOrder
        _ = self.providerEnablement
        _ = self.refreshFrequency
        _ = self.launchAtLogin
        _ = self.debugDisableKeychainAccess
        _ = self.sessionQuotaNotificationsEnabled
        _ = self.usageBarsShowUsed
        _ = self.resetTimesShowAbsolute
        _ = self.menuBarShowsBrandIconWithPercent
        _ = self.menuBarShowsBrandIcon
        _ = self.menuBarShowsPercent
        _ = self.menuBarShowsBatteryShell
        _ = self.menuBarShowsResetTime
        _ = self.menuBarShowsHighestUsage
        _ = self.menuBarDisplayMode
        _ = self.menuBarTimeFormat
        _ = self.historicalTrackingEnabled
        _ = self.menuBarMetricPreferencesRaw
        _ = self.costUsageEnabled
        _ = self.hidePersonalInfo
        _ = self.claudeOAuthKeychainPromptMode
        _ = self.claudeOAuthKeychainReadStrategy
        _ = self.claudeWebExtrasEnabled
        _ = self.showOptionalCreditsAndExtraUsage
        _ = self.openAIWebAccessEnabled
        _ = self.openAIWebBatterySaverEnabled
        _ = self.codexUsageDataSource
        _ = self.codexActiveSource
        _ = self.claudeUsageDataSource
        _ = self.codexCookieSource
        _ = self.claudeCookieSource
        _ = self.mergeIcons
        _ = self.switcherShowsIcons
        _ = self.mergedMenuLastSelectedWasOverview
        _ = self.mergedOverviewSelectedProviders
        _ = self.codexCookieHeader
        _ = self.claudeCookieHeader
        _ = self.tokenAccountsByProvider
        _ = self.selectedMenuProvider
        _ = self.configRevision
        return 0
    }
}
