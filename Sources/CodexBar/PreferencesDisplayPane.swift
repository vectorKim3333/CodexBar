import CodexBarCore
import SwiftUI

@MainActor
struct DisplayPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text(L("section_menu_bar"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: L("menu_bar_shows_percent_title"),
                        subtitle: L("menu_bar_shows_percent_subtitle"),
                        binding: self.$settings.menuBarShowsBrandIconWithPercent)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text(L("section_menu_content"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: L("show_usage_as_used_title"),
                        subtitle: L("show_usage_as_used_subtitle"),
                        binding: self.$settings.usageBarsShowUsed)
                    PreferenceToggleRow(
                        title: L("show_reset_time_as_clock_title"),
                        subtitle: L("show_reset_time_as_clock_subtitle"),
                        binding: self.$settings.resetTimesShowAbsolute)
                    PreferenceToggleRow(
                        title: L("show_credits_extra_usage_title"),
                        subtitle: L("show_credits_extra_usage_subtitle"),
                        binding: self.$settings.showOptionalCreditsAndExtraUsage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
