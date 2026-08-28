import AppKit
import SwiftUI

/// Add / edit sheet for a single custom command, presented from the Commands pane.
struct CustomCommandEditorSheet: View {
    let command: CustomCommand?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @State private var name: String
    @State private var shellCommand: String
    @State private var loadsShellEnvironment: Bool
    @State private var requiresConfirmation: Bool
    @State private var showsConfirmation: Bool
    @State private var showsOutput: Bool
    @State private var arguments: [ArgumentDraft]
    @State private var workingDirectory: String
    @State private var iconSymbol: String?
    @State private var showingIconPicker = false
    @State private var errorMessage: String?

    /// Identity the persisted argument has no need for, so removing a row above one being typed
    /// into doesn't move its field editor.
    private struct ArgumentDraft: Identifiable {
        let id = UUID()
        var name: String
        var isOptional: Bool
    }

    init(command: CustomCommand?) {
        self.command = command
        _name = State(initialValue: command?.name ?? "")
        _shellCommand = State(initialValue: command?.command ?? "")
        _loadsShellEnvironment = State(initialValue: command?.loadsShellEnvironment ?? false)
        _requiresConfirmation = State(initialValue: command?.requiresConfirmation ?? false)
        _showsConfirmation = State(initialValue: command?.showsConfirmation ?? false)
        _showsOutput = State(initialValue: command?.showsOutput ?? false)
        _arguments = State(
            initialValue: (command?.arguments ?? []).map {
                ArgumentDraft(name: $0.name, isOptional: $0.isOptional)
            })
        _workingDirectory = State(initialValue: command?.workingDirectory ?? "")
        _iconSymbol = State(initialValue: command?.iconSymbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(command == nil ? "Add Custom Command" : "Edit Custom Command")
                .font(.title2.weight(.bold))

            HStack(alignment: .bottom, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Name")
                        .font(.callout.weight(.medium))
                    TextField("Sleep Displays", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                iconField
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

            workingDirectoryField

            argumentsSection

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
                optionToggle(
                    "Show output", isOn: $showsOutput,
                    detail: "Open a window with everything the command printed when it finishes.")
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

    private static let iconSymbols = [
        "terminal", "hammer", "wrench", "gearshape", "bolt", "arrow.clockwise", "trash",
        "shippingbox", "cube", "server.rack", "externaldrive", "internaldrive", "cloud",
        "arrow.up.circle", "arrow.down.circle", "doc.text", "folder", "magnifyingglass",
        "ladybug", "chevron.left.forwardslash.chevron.right", "network", "lock", "key",
        "display", "speaker.wave.2", "moon", "sun.max", "power", "clock", "calendar",
        "chart.bar", "flame"
    ]

    private var iconField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Icon")
                .font(.callout.weight(.medium))
            Button {
                showingIconPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: iconSymbol ?? CustomCommand.sfSymbol, size: 14)
                    Text(iconSymbol == nil ? "Automatic" : "Custom")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: Self.iconFieldWidth)
            }
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                SymbolPicker(
                    selection: $iconSymbol, fallback: CustomCommand.sfSymbol,
                    symbols: Self.iconSymbols
                ) {
                    showingIconPicker = false
                }
            }
        }
    }

    private static let iconFieldWidth: CGFloat = 130

    private var workingDirectoryField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Run In")
                .font(.callout.weight(.medium))
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Home folder", text: $workingDirectory)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…", action: chooseWorkingDirectory)
            }
            Text("The folder the command starts in. Leave empty for your home folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder this command runs in."
        if !workingDirectory.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: (workingDirectory as NSString).expandingTildeInPath)
        }
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingDirectory = (url.path as NSString).abbreviatingWithTildeInPath
    }

    private var argumentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Arguments")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Add") { arguments.append(ArgumentDraft(name: "", isOptional: false)) }
                    .controlSize(.small)
            }
            ForEach($arguments) { $argument in
                HStack(spacing: Theme.Spacing.sm) {
                    Text("$\(position(of: argument.id))")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: Self.positionWidth, alignment: .leading)
                    TextField("Argument name", text: $argument.name)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Optional", isOn: $argument.isOptional)
                        .toggleStyle(.checkbox)
                    Button {
                        arguments.removeAll { $0.id == argument.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this argument")
                }
            }
            Text(
                arguments.isEmpty
                    ? "Add one to be asked for a value before the command runs."
                    : "Asked for in order, then passed to the command as $1, $2 …"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private static let positionWidth: CGFloat = 22

    /// The shell variable the row's value lands in; blank names are dropped, but only on save.
    private func position(of id: UUID) -> Int {
        (arguments.firstIndex { $0.id == id } ?? 0) + 1
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
        // Editing keeps the UUID, and with it every reference the command owns.
        let draft = CustomCommand(
            id: command?.id ?? UUID(), name: name, command: shellCommand,
            loadsShellEnvironment: loadsShellEnvironment,
            requiresConfirmation: requiresConfirmation,
            showsConfirmation: showsConfirmation,
            arguments: arguments.map {
                CustomCommandArgument(name: $0.name, isOptional: $0.isOptional)
            },
            showsOutput: showsOutput, workingDirectory: workingDirectory, iconSymbol: iconSymbol)
        do {
            if command == nil {
                try core.customCommandCoordinator.addCustomCommand(draft)
            } else {
                try core.customCommandCoordinator.updateCustomCommand(draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
