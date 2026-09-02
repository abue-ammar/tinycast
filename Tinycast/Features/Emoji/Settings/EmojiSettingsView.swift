import SwiftUI

struct EmojiSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                SettingsRow(title: "Emoji & Symbols", anchor: .emojiGlobalShortcuts) {
                    ShortcutRecorder(action: .command(.searchEmoji))
                }
            } header: {
                SettingsSectionHeader(.emojiGlobalShortcuts)
            } footer: {
                Text("Summon the emoji and symbols palette.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                // A hand per tone, quicker to scan than a dropdown of tone names.
                Picker(selection: $settings.emojiSkinTone) {
                    ForEach(EmojiSkinTone.allCases) { tone in
                        Text(tone.sample).tag(tone)
                    }
                } label: {
                    SettingsRowTitle(.emojiAppearance, "Emoji Skin Tone")
                }
                .pickerStyle(.segmented)
            } header: {
                SettingsSectionHeader(.emojiAppearance)
            } footer: {
                Text("Applied when an emoji supports skin tones; pastes use it too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.emoji)
    }
}
