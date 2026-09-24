import SwiftUI

struct NotesSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.notesEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .notesNotes, title: "Enable Notes",
                        subtitle: "Plain Markdown in a floating editor.")
                }
            }
            .settingsAnchor(.notesNotes)

            Section {
                Toggle(isOn: $settings.notesRendersMarkdown) {
                    SettingsRowTitle(.notesOptions, "Render Markdown")
                    Text("Formats as you type.")
                }
                .settingsEnabled(settings.notesEnabled)
                Toggle(isOn: $settings.notesShowsFormattingBar) {
                    SettingsRowTitle(.notesOptions, "Show Formatting Bar")
                }
                .settingsEnabled(settings.notesEnabled && settings.notesRendersMarkdown)
            } header: {
                SettingsSectionHeader(.notesOptions)
            }

            FeatureCommandsSection(owner: .notes, anchor: .notesCommands)
                .settingsEnabled(settings.notesEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notes)
    }
}
