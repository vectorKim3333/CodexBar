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
                        title: "아이콘 표시",
                        subtitle: "메뉴바에 Claude/Codex 브랜드 글리프를 표시합니다.",
                        binding: self.$settings.menuBarShowsBrandIcon)
                    PreferenceToggleRow(
                        title: "퍼센트 표시",
                        subtitle: "남은(또는 사용한) 사용량을 % 숫자로 표시합니다.",
                        binding: self.$settings.menuBarShowsPercent)
                    PreferenceToggleRow(
                        title: "배터리 표시",
                        subtitle: "사용량을 배터리 모양의 게이지로 표시합니다.",
                        binding: self.$settings.menuBarShowsBatteryShell)
                    PreferenceToggleRow(
                        title: "시간 표시",
                        subtitle: "리셋까지 남은 시간을 표시합니다.",
                        binding: self.$settings.menuBarShowsResetTime)
                    if self.settings.menuBarShowsResetTime {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("time_format_title"))
                                    .font(.body)
                                Text(L("time_format_subtitle"))
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Picker(L("time_format_title"), selection: self.$settings.menuBarTimeFormat) {
                                ForEach(MenuBarTimeFormat.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }
                        .padding(.leading, 16)
                    }
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

                Divider()

                self.companionSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var companionSection: some View {
        SettingsSection(contentSpacing: 12) {
            HStack {
                Text(L("companion.section.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if !self.settings.companionFeatureSeen {
                    Text(L("companion.new.badge"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }

            PreferenceToggleRow(
                title: L("companion.toggle.label"),
                subtitle: L("companion.toggle.subtitle"),
                binding: Binding(
                    get: { self.settings.companionEnabled },
                    set: {
                        self.settings.companionEnabled = $0
                        self.settings.companionFeatureSeen = true
                    }
                ))

            if self.settings.companionEnabled {
                self.companionCharacterRow
                self.companionTargetRow
                CompanionPreviewView(character: self.settings.companionCharacter)
            }
        }
    }

    @ViewBuilder
    private var companionCharacterRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(L("companion.character.label"))
                .font(.body)
            Spacer()
            Picker(L("companion.character.label"),
                   selection: Binding(
                    get: { self.settings.companionCharacter },
                    set: { self.settings.companionCharacter = $0 })) {
                ForEach(CompanionCharacter.allCases, id: \.self) { char in
                    Text(self.characterLabel(char)).tag(char)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
        }
    }

    @ViewBuilder
    private var companionTargetRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(L("companion.target.label"))
                .font(.body)
            Spacer()
            Picker(L("companion.target.label"),
                   selection: Binding(
                    get: { self.settings.companionProvider },
                    set: { self.settings.companionProvider = $0 })) {
                Text("Claude").tag(UsageProvider.claude)
                Text("Codex").tag(UsageProvider.codex)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
    }

    private func characterLabel(_ c: CompanionCharacter) -> String {
        switch c {
        case .catPixel: return L("companion.character.catPixel")
        case .catLine:  return L("companion.character.catLine")
        case .dogPixel: return L("companion.character.dogPixel")
        case .dogLine:  return L("companion.character.dogLine")
        }
    }
}
