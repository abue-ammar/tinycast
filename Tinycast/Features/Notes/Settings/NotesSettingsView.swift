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

            NotesCommandsSection()
                .settingsEnabled(settings.notesEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notes)
    }
}

private struct NotesCommandsSection: View {
    @Environment(VisibilityStore.self) private var visibility

    private let entries = [CommandID.showNotes, .createNote, .searchNotes]
        .compactMap(CommandCatalog.entry(for:))

    var body: some View {
        Section {
            ForEach(entries) { entry in
                SettingsRow(title: entry.name) {
                    AppIconView(app: entry)
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                } trailing: {
                    if let action = entry.hotKeyAction {
                        ShortcutRecorder(action: action)
                    }
                    Toggle("", isOn: visibilityBinding(entry))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Show \(entry.name) in launcher")
                }
            }
        } header: {
            SettingsSectionHeader(.notesCommands)
        } footer: {
            Text("A shortcut works even when its command is hidden from the launcher.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func visibilityBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }
}
