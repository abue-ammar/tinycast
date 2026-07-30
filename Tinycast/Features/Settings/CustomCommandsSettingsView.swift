import SwiftUI

struct CustomCommandsSettingsView: View {
    @EnvironmentObject private var store: CustomCommandStore
    @State private var editor: EditorTarget?
    @State private var pendingDeletion: CustomCommand?

    var body: some View {
        SettingsPane(
            title: "Custom Commands",
            subtitle: "Run your own shell commands from the launcher or a global shortcut."
        ) {
            SettingsCallout(
                title: "Commands run with your user account.",
                message: "Tinycast runs them in /bin/zsh, so use full executable paths.",
                systemImage: "terminal",
                tint: .green
            )

            SettingsCard(header: "Commands") {
                if store.commands.isEmpty {
                    SettingsRow(
                        title: "No custom commands",
                        subtitle: "Add one to make it searchable from the launcher.",
                        systemImage: "terminal",
                        tint: .secondary
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(sortedCommands.enumerated()), id: \.element.id) {
                        index, command in
                        if index > 0 { SettingsDivider() }
                        CustomCommandSettingsRow(
                            command: command,
                            onEdit: { editor = EditorTarget(command: command) },
                            onDelete: { pendingDeletion = command })
                    }
                }
                SettingsDivider()

                SettingsRow(
                    title: "Add Custom Command",
                    subtitle: "Name it, then give it a shortcut if you want one.",
                    systemImage: "plus.circle",
                    tint: .green
                ) {
                    Button("Add…") { editor = EditorTarget(command: nil) }
                        .controlSize(.small)
                }
            }
        }
        .sheet(item: $editor) { target in
            CustomCommandEditorSheet(command: target.command)
        }
        .alert(item: $pendingDeletion) { command in
            Alert(
                title: Text("Delete “\(command.name)”?"),
                message: Text("Its global shortcut and launcher references will also be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    AppCore.shared.deleteCustomCommand(id: command.id)
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
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: Theme.Size.settingsRowIcon)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(command.name)
                    .font(.body)
                    .lineLimit(1)
                Text(command.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(command.command)
            }

            Spacer(minLength: Theme.Spacing.lg)
            ShortcutRecorder(action: .customCommand(id: command.id))

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
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

private struct CustomCommandEditorSheet: View {
    let command: CustomCommand?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var shellCommand: String
    @State private var loadsShellEnvironment: Bool
    @State private var requiresConfirmation: Bool
    @State private var showsConfirmation: Bool
    @State private var errorMessage: String?

    init(command: CustomCommand?) {
        self.command = command
        _name = State(initialValue: command?.name ?? "")
        _shellCommand = State(initialValue: command?.command ?? "")
        _loadsShellEnvironment = State(initialValue: command?.loadsShellEnvironment ?? false)
        _requiresConfirmation = State(initialValue: command?.requiresConfirmation ?? false)
        _showsConfirmation = State(initialValue: command?.showsConfirmation ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(command == nil ? "Add Custom Command" : "Edit Custom Command")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name")
                    .font(.callout.weight(.medium))
                TextField("Sleep Displays", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Command")
                    .font(.callout.weight(.medium))
                TextEditor(text: $shellCommand)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: Theme.Size.editorTextHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text("Example: /usr/bin/pmset displaysleepnow")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                optionToggle(
                    "Load shell environment", isOn: $loadsShellEnvironment,
                    detail: "Resolves aliases, functions and PATH. Slower to start.")
                optionToggle(
                    "Needs confirmation", isOn: $requiresConfirmation,
                    detail: "Ask before running this command.")
                optionToggle(
                    "Show confirmation", isOn: $showsConfirmation,
                    detail: "Confirm on screen after the command succeeds.")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || shellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    private func optionToggle(
        _ title: String, isOn: Binding<Bool>, detail: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }

    private func save() {
        // Editing keeps the UUID, and with it the command's favorite, visibility and hotkey references.
        let draft = CustomCommand(
            id: command?.id ?? UUID(), name: name, command: shellCommand,
            loadsShellEnvironment: loadsShellEnvironment,
            requiresConfirmation: requiresConfirmation,
            showsConfirmation: showsConfirmation)
        do {
            if command == nil {
                try AppCore.shared.addCustomCommand(draft)
            } else {
                try AppCore.shared.updateCustomCommand(draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
