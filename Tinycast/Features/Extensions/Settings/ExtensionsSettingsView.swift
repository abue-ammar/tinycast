import SwiftUI

/// Manage installed Raycast extensions: what's installed, each one's commands and preferences, and the
/// two ways in — import from a locally installed Raycast, or add a prebuilt folder.
struct ExtensionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var selected: String?
    @State private var importCandidates: ImportCandidates?
    @State private var error: String?

    var body: some View {
        @Bindable var settings = core.settings
        return Form {
            FeatureSwitchSection(
                header: "Extensions",
                enableTitle: "Enable extensions",
                enableSubtitle:
                    "Run Raycast extensions natively. A running command holds a JavaScript engine "
                    + "in memory until you leave it.",
                launcherSubtitle: "List every extension's commands in launcher search.",
                // Enabling is also consent to run third-party code, so it uses the confirming setter.
                isEnabled: Binding(
                    get: { settings.extensionsEnabled },
                    set: { core.extensionCoordinator.setExtensionsEnabled($0) }),
                showsInLauncher: $settings.extensionsShowInLauncher)

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Group {
                Section {
                    SettingsRow(title: "Import from Raycast", subtitle: importSubtitle) {
                        Image(systemName: "arrow.down.doc")
                    } trailing: {
                        Button("Choose…") {
                            importCandidates = ImportCandidates(
                                extensions: ExtensionCatalog.importableFromRaycast())
                        }
                        .disabled(!raycastAvailable)
                    }
                    SettingsRow(
                        title: "Add Extension Folder…",
                        subtitle: "Pick a folder containing package.json and the built <command>.js files."
                    ) {
                        Image(systemName: "folder.badge.plus")
                    } trailing: {
                        Button("Choose…", action: addFolder)
                    }
                } header: {
                    Text("Add")
                }

                Section {
                    if core.extensions.installed.isEmpty {
                        Text("Everything you add shows up in the launcher under “Extensions”.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(core.extensions.installed) { installed in
                            ExtensionSettingsRow(
                                installed: installed,
                                isExpanded: selected == installed.manifest.name,
                                onToggle: {
                                    selected =
                                        selected == installed.manifest.name
                                        ? nil : installed.manifest.name
                                },
                                onUninstall: {
                                    Task { await core.extensions.uninstall(installed) }
                                })
                        }
                    }
                } header: {
                    Text(
                        core.extensions.installed.isEmpty
                            ? "Installed" : "Installed (\(core.extensions.installed.count))")
                }
            }
            .settingsEnabled(settings.extensionsEnabled)
        }
        .formStyle(.grouped)
        .onChange(of: settings.extensionsShowInLauncher) {
            core.extensionCoordinator.applyExtensionsLauncherPresence()
        }
        // Presented by item, not by a bare flag: with `isPresented` SwiftUI builds the sheet from the
        // body snapshot that precedes the button's state write, so the freshly scanned candidates
        // arrived as an empty list.
        .sheet(item: $importCandidates) { candidates in
            ExtensionImportSheet(
                candidates: candidates.extensions,
                onImport: { chosen in
                    importCandidates = nil
                    Task { await install(chosen.map(\.directory)) }
                },
                onCancel: { importCandidates = nil })
        }
        .onReceive(NotificationCenter.default.publisher(for: .tinycastSelectExtension)) { note in
            if let name = note.object as? String { selected = name }
        }
        .task { await core.extensions.refresh() }
    }

    private var raycastAvailable: Bool {
        FileManager.default.fileExists(atPath: ExtensionCatalog.raycastExtensionsDirectory().path)
    }

    private var importSubtitle: String {
        raycastAvailable
            ? "Copies the bundles Raycast already built — no Node or npm needed."
            : "No Raycast install found at ~/.config/raycast/extensions."
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        Task { await install(panel.urls) }
    }

    private func install(_ urls: [URL]) async {
        error = nil
        for url in urls {
            do {
                try await core.extensions.install(from: url)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// One installed extension: a summary row that expands into its commands and preferences.
private struct ExtensionSettingsRow: View {
    let installed: InstalledExtension
    let isExpanded: Bool
    let onToggle: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SettingsRow(title: installed.title, subtitle: commandSummary) {
                ExtensionIconView(
                    resolved: installed.iconPath.map {
                        ExtensionImage.Resolved(source: .file($0))
                    },
                    size: Theme.Size.settingsRowIcon)
            } trailing: {
                Button(isExpanded ? "Hide" : "Configure", action: onToggle)
                Button("Remove", action: onUninstall)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ExtensionAppearanceRow(installed: installed)
                    if !installed.manifest.preferences.isEmpty {
                        preferenceGroup(
                            title: "Extension preferences",
                            schemas: installed.manifest.preferences)
                    }
                    ForEach(installed.manifest.commands) { command in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Text(command.title).font(.body)
                                Text(command.mode.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !command.mode.isSupported {
                                    Text("not supported")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            if !command.description.isEmpty {
                                Text(command.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !command.preferences.isEmpty {
                                preferenceGroup(title: nil, schemas: command.preferences)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var commandSummary: String {
        let count = installed.manifest.commands.count
        let author = installed.manifest.author
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        return author.isEmpty ? commands : "\(commands) · \(author)"
    }

    @ViewBuilder
    private func preferenceGroup(title: String?, schemas: [ExtensionPreferenceSchema]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let title {
                Text(title).font(Theme.Typography.sectionHeader).foregroundStyle(.secondary)
            }
            ForEach(schemas, id: \.name) { schema in
                ExtensionPreferenceField(extensionName: installed.manifest.name, schema: schema)
            }
        }
        .padding(.leading, Theme.Spacing.md)
    }
}

/// One preference control, backed by `ExtensionStorage` so a command reads it through
/// `getPreferenceValues()`.
private struct ExtensionPreferenceField: View {
    let extensionName: String
    let schema: ExtensionPreferenceSchema
    @Environment(AppCore.self) private var core
    @State private var text: String = ""
    @State private var flag: Bool = false

    private var storage: ExtensionStorage { core.extensions.storage }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(schema.displayTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            control
            if schema.required {
                Text("required").font(.caption).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var control: some View {
        switch schema.kind {
        case .checkbox:
            Toggle(schema.label ?? "", isOn: $flag)
                .toggleStyle(.checkbox)
                .onChange(of: flag) { _, value in
                    storage.setPreference(extension: extensionName, key: schema.name, value: .bool(value))
                }
        case .dropdown:
            Picker("", selection: $text) {
                ForEach(schema.options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220, alignment: .leading)
            .onChange(of: text) { _, value in save(value) }
        case .password:
            SecureField(schema.placeholder ?? "", text: $text)
                .frame(maxWidth: 260)
                .onChange(of: text) { _, value in save(value) }
        case .file, .directory, .appPicker:
            HStack(spacing: Theme.Spacing.sm) {
                Text(text.isEmpty ? "Not set" : (text as NSString).lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                Button("Choose…", action: choosePath)
            }
        case .textfield:
            TextField(schema.placeholder ?? "", text: $text)
                .frame(maxWidth: 260)
                .onChange(of: text) { _, value in save(value) }
        }
    }

    private func load() {
        let value = storage.preference(extension: extensionName, key: schema.name) ?? schema.effectiveDefault
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

/// One scan of the local Raycast install, carried as the import sheet's presentation item.
private struct ImportCandidates: Identifiable {
    let id = UUID()
    let extensions: [InstalledExtension]
}

/// Picker over the extensions a locally installed Raycast has already built.
private struct ExtensionImportSheet: View {
    let candidates: [InstalledExtension]
    let onImport: ([InstalledExtension]) -> Void
    let onCancel: () -> Void
    @State private var chosen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Import from Raycast").font(.title2.weight(.bold))
                Text(
                    candidates.isEmpty
                        ? "No built extensions found in ~/.config/raycast/extensions."
                        : "Pick the extensions to copy into Tinycast."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        // The checkbox sits outside the Toggle's label: an AppKit checkbox aligns to
                        // its label's first baseline, which reads off-centre next to a two-line row.
                        HStack(spacing: Theme.Spacing.md) {
                            Toggle("", isOn: binding(for: candidate))
                                .labelsHidden()
                            ExtensionIconView(
                                resolved: candidate.iconPath.map {
                                    ExtensionImage.Resolved(source: .file($0))
                                }, size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(candidate.title).font(.body)
                                Text("\(candidate.manifest.commands.count) commands")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .onTapGesture { binding(for: candidate).wrappedValue.toggle() }
                    }
                }
                .hideNativeScrollers()
            }
            .thinScrollbar()
            .frame(minHeight: 220)

            HStack {
                Button(chosen.count == candidates.count ? "Deselect All" : "Select All") {
                    chosen =
                        chosen.count == candidates.count
                        ? [] : Set(candidates.map(\.manifest.name))
                }
                .disabled(candidates.isEmpty)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Import \(chosen.count > 0 ? "(\(chosen.count))" : "")") {
                    onImport(candidates.filter { chosen.contains($0.manifest.name) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    private func binding(for candidate: InstalledExtension) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(candidate.manifest.name) },
            set: { isOn in
                if isOn {
                    chosen.insert(candidate.manifest.name)
                } else {
                    chosen.remove(candidate.manifest.name)
                }
            })
    }
}
