import SwiftUI

struct CompactShortcutsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            ForEach(settings.compactBarCommands, id: \.self) { command in
                shortcut(command)
            }
            Menu {
                ForEach(availableCommands, id: \.self) { command in
                    Button {
                        guard settings.compactBarCommands.count < CommandID.compactBarLimit,
                            !settings.compactBarCommands.contains(command)
                        else { return }
                        settings.compactBarCommands.append(command)
                    } label: {
                        commandLabel(command)
                    }
                }
            } label: {
                Label("Add Shortcut", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(settings.compactBarCommands.count >= CommandID.compactBarLimit)
        } header: {
            SettingsSectionHeader(.generalCompactShortcuts)
        }
    }

    private var availableCommands: [CommandID] {
        CommandID.compactBarOptions.filter { !settings.compactBarCommands.contains($0) }
    }

    private func shortcut(_ command: CommandID) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            Menu {
                ForEach(CommandID.compactBarOptions, id: \.self) { option in
                    if option == command || !settings.compactBarCommands.contains(option) {
                        Button {
                            replace(command, with: option)
                        } label: {
                            commandLabel(option)
                        }
                    }
                }
            } label: {
                commandLabel(command)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            Spacer(minLength: Theme.Spacing.lg)
            Button("Move Up", systemImage: "chevron.up") { move(command, by: -1) }
                .help("Move Up")
                .disabled(settings.compactBarCommands.first == command)
            Button("Move Down", systemImage: "chevron.down") { move(command, by: 1) }
                .help("Move Down")
                .disabled(settings.compactBarCommands.last == command)
            Button("Remove", systemImage: "minus") {
                settings.compactBarCommands.removeAll { $0 == command }
            }
            .help("Remove")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }

    private func commandLabel(_ command: CommandID) -> some View {
        Label {
            Text(command.name)
        } icon: {
            SymbolImage(name: command.sfSymbol, size: Theme.Size.settingsRowIcon)
                .environment(\.symbolVariants, .none)
                .foregroundStyle(.secondary)
        }
        .labelStyle(.titleAndIcon)
    }

    private func replace(_ command: CommandID, with replacement: CommandID) {
        guard let index = settings.compactBarCommands.firstIndex(of: command),
            !settings.compactBarCommands.contains(replacement)
        else { return }
        settings.compactBarCommands[index] = replacement
    }

    private func move(_ command: CommandID, by step: Int) {
        guard let index = settings.compactBarCommands.firstIndex(of: command) else { return }
        let destination = index + step
        guard settings.compactBarCommands.indices.contains(destination) else { return }
        settings.compactBarCommands.swapAt(index, destination)
    }
}
