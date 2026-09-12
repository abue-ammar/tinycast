import SwiftUI

struct NotesSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.notesEnabled) {
                    SettingsRowTitle(.notesNotes, "Enable Notes")
                    Text("Keep plain Markdown notes in a floating editor, loaded only when needed.")
                }
            } header: {
                SettingsSectionHeader(.notesNotes)
            }

            FeatureCommandsSection(owner: .notes, anchor: .notesCommands)
                .settingsEnabled(settings.notesEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notes)
    }
}
