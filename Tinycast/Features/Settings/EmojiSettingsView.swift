import SwiftUI

struct EmojiSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Emoji & Symbols",
            subtitle: "Search emoji and symbols, and paste them into any app."
        ) {
            SettingsCard(header: "Global Shortcuts") {
                SettingsRow(
                    title: "Emoji & Symbols",
                    subtitle: "Summon the emoji and symbols palette.",
                    systemImage: "face.smiling",
                    tint: .yellow
                ) {
                    ShortcutRecorder(action: .toggleEmoji)
                }
            }

            SettingsCard(header: "Appearance") {
                SettingsRow(
                    title: "Emoji Skin Tone",
                    subtitle: "Applied when an emoji supports skin tones; pastes use it too.",
                    systemImage: "hand.wave",
                    tint: .orange
                ) {
                    // A hand per tone, Raycast style — quicker to scan than a dropdown of tone names.
                    Picker("Emoji Skin Tone", selection: $settings.emojiSkinTone) {
                        ForEach(EmojiSkinTone.allCases) { tone in
                            Text(tone.sample).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}
