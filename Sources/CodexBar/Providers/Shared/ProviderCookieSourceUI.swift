import CodexBarCore

enum ProviderCookieSourceUI {
    static let keychainDisabledPrefix =
        "Keychain access is disabled in Advanced, so browser cookie import is unavailable."

    private static func localizedTitle(for source: ProviderCookieSource) -> String {
        switch source {
        case .auto: L("Automatic")
        case .manual: L("Manual")
        case .off: L("Off")
        }
    }

    static func options(allowsOff: Bool, keychainDisabled: Bool) -> [ProviderSettingsPickerOption] {
        var options: [ProviderSettingsPickerOption] = []
        if !keychainDisabled {
            options.append(ProviderSettingsPickerOption(
                id: ProviderCookieSource.auto.rawValue,
                title: Self.localizedTitle(for: .auto)))
        }
        options.append(ProviderSettingsPickerOption(
            id: ProviderCookieSource.manual.rawValue,
            title: Self.localizedTitle(for: .manual)))
        if allowsOff {
            options.append(ProviderSettingsPickerOption(
                id: ProviderCookieSource.off.rawValue,
                title: Self.localizedTitle(for: .off)))
        }
        return options
    }

    static func subtitle(
        source: ProviderCookieSource,
        keychainDisabled: Bool,
        auto: String,
        manual: String,
        off: String) -> String
    {
        if keychainDisabled {
            return source == .off ? off : "\(self.keychainDisabledPrefix) \(manual)"
        }
        switch source {
        case .auto:
            return auto
        case .manual:
            return manual
        case .off:
            return off
        }
    }
}
