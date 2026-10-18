import SwiftUI

struct NotesSettingsView: View {
    @Environment(AppCore.self) private var core
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
                LabeledContent {
                    if settings.notesFolder != nil {
                        Button(
                            String(localized: "notes-use-default-folder", defaultValue: "Use Default"),
                            action: core.notesCoordinator.resetNotesFolder)
                    }
                    Button("Choose…", action: core.notesCoordinator.chooseNotesFolder)
                } label: {
                    SettingsRowTitle(.notesOptions, "Notes Folder")
                    Text((core.notesStore.notesDirectory.path as NSString).abbreviatingWithTildeInPath)
                }
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
