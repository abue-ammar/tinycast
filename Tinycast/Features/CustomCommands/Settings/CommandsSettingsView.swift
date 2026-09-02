import SwiftUI

/// Both flavours in one pane: the built-ins, then the user's own shell commands.
struct CommandsSettingsView: View {
    @Environment(CustomCommandStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var editor: EditorTarget?
    @State private var pendingDeletion: CustomCommand?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherItemsSection(
                kind: .command,
                anchor: .commandsCommands,
                searchPrompt: "Search commands…")

            FeatureSwitchSection(
                anchor: .commandsCustomCommands,
                enableTitle: "Enable custom commands",
                enableSubtitle:
                    "Commands run with your user account in /bin/zsh, so use full executable paths.",
                launcherSubtitle: "Find your commands in launcher search.",
                isEnabled: $settings.customCommandsEnabled,
                showsInLauncher: $settings.customCommandsShowInLauncher)

            Section {
                if store.commands.isEmpty {
                    Text("Add one to make it searchable from the launcher.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedCommands) { command in
                        CustomCommandSettingsRow(
                            command: command,
                            isEnabled: Binding(
                                get: { command.isEnabled },
                                set: {
                                    core.customCommandCoordinator.setCustomCommandEnabled(
                                        $0, id: command.id)
                                }),
                            onEdit: { editor = EditorTarget(command: command) },
                            onDelete: { pendingDeletion = command })
                    }
                }
                Button {
                    editor = EditorTarget(command: nil)
                } label: {
                    SettingsRowTitle(.commandsCustomCommands, "Add Custom Command")
                }
            } footer: {
                Text("Name it, then give it a shortcut if you want one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.customCommandsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commands)
        .releasesFocusOnOutsideClick()
        .sheet(item: $editor) { target in
            CustomCommandEditorSheet(command: target.command)
        }
        .alert(item: $pendingDeletion) { command in
            Alert(
                title: Text("Delete “\(command.name)”?"),
                message: Text("Its global shortcut and launcher references will also be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    core.customCommandCoordinator.deleteCustomCommand(id: command.id)
                },
                secondaryButton: .cancel())
        }
    }

    private var sortedCommands: [CustomCommand] {
        store.commands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct EditorTarget: Identifiable {
    let id = UUID()
    let command: CustomCommand?
}

private struct CustomCommandSettingsRow: View {
    let command: CustomCommand
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: command.name, subtitle: command.command) {
            Image(systemName: command.symbol)
        } trailing: {
            // A disabled command's shortcut fires into the funnel's refusal, so it dims too.
            ShortcutRecorder(action: .customCommand(id: command.id))
                .settingsEnabled(command.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Command")
            .accessibilityLabel("Edit \(command.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Command")
            .accessibilityLabel("Delete \(command.name)")

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Enabled")
                .accessibilityLabel("Enable \(command.name)")
        }
    }
}
