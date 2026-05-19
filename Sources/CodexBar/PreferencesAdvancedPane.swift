import KeyboardShortcuts
import SwiftUI

@MainActor
struct AdvancedPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 8) {
                    Text(L("section_keyboard_shortcut"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HStack(alignment: .center, spacing: 12) {
                        Text(L("open_menu_shortcut_title"))
                            .font(.body)
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .openMenu)
                    }
                    Text(L("open_menu_shortcut_subtitle"))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                SettingsSection(contentSpacing: 10) {
                    PreferenceToggleRow(
                        title: L("hide_personal_info_title"),
                        subtitle: L("hide_personal_info_subtitle"),
                        binding: self.$settings.hidePersonalInfo)
                }

                Divider()

                SettingsSection(
                    title: L("section_keychain_access"),
                    caption: L("keychain_access_caption"))
                {
                    PreferenceToggleRow(
                        title: L("disable_keychain_access_title"),
                        subtitle: L("disable_keychain_access_subtitle"),
                        binding: self.$settings.debugDisableKeychainAccess)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
