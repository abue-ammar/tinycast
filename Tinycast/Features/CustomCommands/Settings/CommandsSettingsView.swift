import SwiftUI

/// Both flavours in one pane: the built-ins, then the user's own shell commands.
struct CommandsSettingsView: View {
    @Environment(CustomCommandStore.self) private var store
    @Environment(CustomCommandCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherCategorySwitchSection(kind: .command, anchor: .commandsCommands)

            LauncherItemsSection(
                kind: .command,
                anchor: .commandsCommands,
                searchPrompt: "Search commands…")

            FeatureSwitchSection(
                anchor: .commandsCustomCommands,
                enableTitle: "Enable custom commands",
                enableSubtitle:
                    "Run as you in /bin/zsh, or the interpreter a #! line names. "
                    + "Use full executable paths.",
                isEnabled: $settings.customCommandsEnabled,
                showsInLauncher: $settings.customCommandsShowInLauncher)

            Section {
                ForEach(CommandCatalog.entries(ownedBy: .commands)) { entry in
                    FeatureCommandRow(entry: entry)
                }
                if store.commands.isEmpty {
                    Text("No custom commands yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedCommands) { command in
                        CustomCommandSettingsRow(
                            command: command,
                            showsInLauncher: settings.customCommandsShowInLauncher,
                            isEnabled: Binding(
                                get: { command.isEnabled },
                                set: {
                                    coordinator.setCustomCommandEnabled(
                                        $0, id: command.id)
                                }),
                            onEdit: { coordinator.editCustomCommand(command) },
                            onDelete: { Task { await coordinator.deleteCustomCommand(id: command.id) } })
                    }
                }
                Button {
                    coordinator.editCustomCommand(nil)
                } label: {
                    SettingsRowTitle(.commandsCustomCommands, "Add Custom Command")
                }
                Button {
                    Task { await coordinator.importScriptDirectory() }
                } label: {
                    SettingsRowTitle(.commandsCustomCommands, "Import Raycast Scripts")
                }
            } footer: {
                Text("Import reads a folder of Raycast script commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.customCommandsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commands)
        .releasesFocusOnOutsideClick()
    }

    private var sortedCommands: [CustomCommand] {
        store.commands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct CustomCommandSettingsRow: View {
    let command: CustomCommand
    let showsInLauncher: Bool
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: command.name, subtitle: command.command) {
            Image(systemName: command.symbol)
        } trailing: {
            if !command.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .help("Hidden from root search")
            }

            // An alias only reaches the ranker through the launcher slice, so it dims with it.
            AliasField(key: command.entryID, name: command.name)
                .settingsEnabled(command.isEnabled && showsInLauncher && command.showsInRootSearch)

            // A disabled command's shortcut fires into the funnel's refusal, so it dims too.
            ShortcutRecorder(action: .customCommand(id: command.id))
                .settingsEnabled(command.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Custom Command")
            .accessibilityLabel("Edit \(command.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Custom Command")
            .accessibilityLabel("Delete \(command.name)")

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Enabled")
                .accessibilityLabel("Enable \(command.name)")
        }
    }
}
