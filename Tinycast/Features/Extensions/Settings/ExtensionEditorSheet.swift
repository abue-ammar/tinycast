import SwiftUI

/// Everything one extension holds: its icon, its preferences, and its commands with their shortcuts.
///
/// A sheet rather than an expanding row, like the custom command and snippet editors — an extension
/// carries more than a settings row can, and a `Form` gives every control the label column, focus
/// ring and hover behaviour a hand-built layout has to reinvent badly.
struct ExtensionEditorSheet: View {
    let installed: InstalledExtension

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @State private var picking = false

    private var appearance: ExtensionAppearance? {
        core.extensions.appearances.appearance(for: installed.manifest.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Form {
                Section {
                    LabeledContent("Launcher icon") {
                        HStack(spacing: Theme.Spacing.md) {
                            iconPreview
                            Button("Change…") { picking = true }
                                .popover(isPresented: $picking, arrowEdge: .bottom) {
                                    ExtensionAppearancePicker(
                                        current: appearance ?? .fallback,
                                        isCustom: appearance != nil,
                                        onPick: {
                                            core.extensions.setAppearance(
                                                $0, for: installed.manifest.name)
                                        },
                                        onReset: {
                                            core.extensions.setAppearance(
                                                nil, for: installed.manifest.name)
                                        })
                                }
                        }
                    }
                } footer: {
                    Text(
                        appearance == nil
                            ? "Using the icon this extension ships."
                            : "Replaced with a Tinycast icon."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !installed.manifest.preferences.isEmpty {
                    Section("Preferences") {
                        ForEach(installed.manifest.preferences, id: \.name) { schema in
                            ExtensionPreferenceField(
                                extensionName: installed.manifest.name, schema: schema)
                        }
                    }
                }

                ForEach(installed.manifest.commands) { command in
                    Section {
                        LabeledContent("Shortcut") {
                            if command.mode.isSupported {
                                // Per command, not per extension: a shortcut has to land on one thing
                                // to run, and an extension is a set of commands.
                                ShortcutRecorder(
                                    action: .extensionCommand(
                                        entryID: ExtensionCommandRef(
                                            extensionName: installed.manifest.name,
                                            commandName: command.name
                                        ).entryID))
                            } else {
                                Text("Menu bar commands don't run here yet")
                                    .foregroundStyle(.orange)
                            }
                        }
                        ForEach(command.preferences, id: \.name) { schema in
                            ExtensionPreferenceField(
                                extensionName: installed.manifest.name, schema: schema)
                        }
                    } header: {
                        Text(command.title)
                    } footer: {
                        if !command.description.isEmpty {
                            Text(command.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            footer
        }
        .frame(width: Theme.Size.editorSheetWidth, height: 520)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.lg) {
            iconPreview
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(installed.title).font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.top, Theme.Spacing.xxl)
    }

    private var footer: some View {
        HStack {
            Button("Uninstall…", role: .destructive) {
                dismiss()
                core.extensionCoordinator.confirmUninstall(installed)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Spacing.xxl)
    }

    /// Exactly what the launcher row will draw — the shipped image, or the chosen tile.
    @ViewBuilder
    private var iconPreview: some View {
        if let appearance {
            SymbolTile(symbol: appearance.symbol, tint: appearance.tint, side: Theme.Size.rowIcon)
        } else {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon)
        }
    }

    private var subtitle: String {
        let count = installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        let author = installed.manifest.author
        return author.isEmpty ? commands : "\(commands) · \(author)"
    }
}

/// One preference control, backed by `ExtensionStorage` so a command reads it through
/// `getPreferenceValues()`. A `LabeledContent` inside a `Form`, so it gets the same label column and
/// control styling as every other setting.
struct ExtensionPreferenceField: View {
    let extensionName: String
    let schema: ExtensionPreferenceSchema
    @Environment(AppCore.self) private var core
    @State private var text: String = ""
    @State private var flag: Bool = false

    private var storage: ExtensionStorage { core.extensions.storage }

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(schema.displayTitle)
            if schema.required {
                Text("Required")
                    .foregroundStyle(.orange)
            } else if let description = schema.description, !description.isEmpty {
                Text(description)
            }
        }
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var control: some View {
        switch schema.kind {
        case .checkbox:
            Toggle(schema.label ?? "", isOn: $flag)
                .labelsHidden()
                .onChange(of: flag) { _, value in
                    storage.setPreference(
                        extension: extensionName, key: schema.name, value: .bool(value))
                }
        case .dropdown:
            Picker("", selection: $text) {
                ForEach(schema.options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .onChange(of: text) { _, value in save(value) }
        case .password:
            SecureField(schema.placeholder ?? "", text: $text)
                .onChange(of: text) { _, value in save(value) }
        case .file, .directory, .appPicker:
            HStack(spacing: Theme.Spacing.sm) {
                Text(text.isEmpty ? "Not set" : (text as NSString).lastPathComponent)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…", action: choosePath)
            }
        case .textfield:
            TextField(schema.placeholder ?? "", text: $text)
                .onChange(of: text) { _, value in save(value) }
        }
    }

    private func load() {
        let value =
            storage.preference(extension: extensionName, key: schema.name)
            ?? schema.effectiveDefault
        text = value.stringValue
        flag = value.boolValue
    }

    private func save(_ value: String) {
        storage.setPreference(extension: extensionName, key: schema.name, value: .string(value))
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = schema.kind != .directory
        panel.canChooseDirectories = schema.kind == .directory
        if schema.kind == .appPicker {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text = url.path
        save(url.path)
    }
}
