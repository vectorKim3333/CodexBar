import Foundation

struct SettingsDefaultsState {
    var refreshFrequency: RefreshFrequency
    var launchAtLogin: Bool
    var debugMenuEnabled: Bool
    var debugDisableKeychainAccess: Bool
    var debugFileLoggingEnabled: Bool
    var debugLogLevelRaw: String?
    var debugLoadingPatternRaw: String?
    var debugKeepCLISessionsAlive: Bool
    var statusChecksEnabled: Bool
    var sessionQuotaNotificationsEnabled: Bool
    var quotaWarningNotificationsEnabled: Bool
    var quotaWarningThresholdsRaw: [Int]
    var quotaWarningSessionThresholdsRaw: [Int]
    var quotaWarningWeeklyThresholdsRaw: [Int]
    var quotaWarningSessionEnabled: Bool
    var quotaWarningWeeklyEnabled: Bool
    var quotaWarningSoundEnabled: Bool
    var quotaWarningMarkersVisible: Bool
    var usageBarsShowUsed: Bool
    var resetTimesShowAbsolute: Bool
    var providerChangelogLinksEnabled: Bool
    var menuBarShowsBrandIconWithPercent: Bool
    var menuBarDisplayModeRaw: String?
    /// Display style for the menu-bar pill countdown (`~2h` / `1h 45m` / `1h+`).
    var menuBarTimeFormatRaw: String

    /// Independent toggles for status-bar visual parts. All four can be combined freely.
    var menuBarShowsBrandIcon: Bool
    var menuBarShowsPercent: Bool
    var menuBarShowsBatteryShell: Bool
    var menuBarShowsResetTime: Bool

    var historicalTrackingEnabled: Bool
    var multiAccountMenuLayoutRaw: String
    var menuBarMetricPreferencesRaw: [String: String]
    var costUsageEnabled: Bool
    var hidePersonalInfo: Bool
    var randomBlinkEnabled: Bool
    var confettiOnWeeklyLimitResetsEnabled: Bool
    var menuBarShowsHighestUsage: Bool
    var claudeOAuthKeychainPromptModeRaw: String?
    var claudeOAuthKeychainReadStrategyRaw: String?
    var claudeWebExtrasEnabledRaw: Bool
    var claudePeakHoursEnabled: Bool
    var showOptionalCreditsAndExtraUsage: Bool
    var openAIWebAccessEnabled: Bool
    var openAIWebBatterySaverEnabled: Bool
    var providerStorageFootprintsEnabled: Bool
    var jetbrainsIDEBasePath: String
    var mergeIcons: Bool
    var switcherShowsIcons: Bool
    var mergedMenuLastSelectedWasOverview: Bool
    var mergedOverviewSelectedProvidersRaw: [String]
    var selectedMenuProviderRaw: String?
    var providerDetectionCompleted: Bool
    var appLanguageRaw: String?
}
