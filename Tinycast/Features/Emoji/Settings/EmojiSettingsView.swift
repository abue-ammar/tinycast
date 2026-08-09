import SwiftUI

struct EmojiSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                SettingsRow(title: "Emoji & Symbols") {
                    ShortcutRecorder(action: .toggleEmoji)
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Summon the emoji and symbols palette.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                // A hand per tone, quicker to scan than a dropdown of tone names.
                Picker("Emoji Skin Tone", selection: $settings.emojiSkinTone) {
                    ForEach(EmojiSkinTone.allCases) { tone in
                        Text(tone.sample).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Applied when an emoji supports skin tones; pastes use it too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
