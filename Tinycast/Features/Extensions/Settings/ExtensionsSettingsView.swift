import SwiftUI

/// Settings › Extensions: the master switch, what Raycast's API does and doesn't reach here, and one
/// expandable row per installed extension — its preferences, its commands and their shortcuts.
struct ExtensionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var expanded: String?
    @State private var importCandidates: ImportCandidates?
    @State private var filter = ""
    @State private var error: String?
    /// Extensions Raycast has built that aren't here yet, refreshed whenever the pane appears.
    @State private var pending: [RaycastImportCandidate] = []
    @State private var browsingStore = false

    private var matching: [InstalledExtension] {
        guard !filter.isEmpty else { return core.extensions.installed }
        return core.extensions.installed.filter { entry in
            entry.title.localizedCaseInsensitiveContains(filter)
                || entry.manifest.commands.contains {
                    $0.title.localizedCaseInsensitiveContains(filter)
                }
        }
    }

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

            Group {
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                CompatibilityNotice()
                if !pending.isEmpty { newInRaycast }
                filterSection
                library
                ExtensionAdvancedSection()
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
        .sheet(isPresented: $browsingStore) {
            ExtensionStoreSheet(onClose: { browsingStore = false })
        }
        .sheet(item: $importCandidates) { candidates in
            ExtensionImportSheet(
                candidates: candidates.entries,
                onImport: { chosen in
                    importCandidates = nil
                    Task { await importAll(chosen) }
                },
                onCancel: { importCandidates = nil })
        }
        .onReceive(NotificationCenter.default.publisher(for: .tinycastSelectExtension)) { note in
            if let name = note.object as? String { expanded = name }
        }
        .task {
            await core.extensions.refresh()
            await findPending()
        }
    }

    /// Raycast installs into its own directory, and nothing tells us when it does. Rather than leave
    /// that to be discovered, the pane looks every time it opens and says what it found.
    @ViewBuilder
    private var newInRaycast: some View {
        Section {
            SettingsRow(title: pendingTitle, subtitle: pendingSubtitle) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.tint)
            } trailing: {
                Button("Review…", action: openImport)
                Button("Import All") { Task { await importAll(pending.map(\.installed)) } }
            }
        }
    }

    private var pendingTitle: String {
        pending.count == 1
            ? "1 extension in Raycast isn't here yet"
            : "\(pending.count) extensions in Raycast aren't here yet"
    }

    private var pendingSubtitle: String {
        pending.prefix(3).map(\.installed.title).joined(separator: ", ")
            + (pending.count > 3 ? " and \(pending.count - 3) more" : "")
    }

    private func findPending() async {
        guard core.settings.extensionsEnabled, raycastAvailable else {
            pending = []
            return
        }
        pending = await core.extensions.raycastImportCandidates().filter { !$0.isInstalled }
    }

    // MARK: - The library

    /// The filter sits in a section of its own on purpose. Sharing one with the results means every
    /// keystroke rebuilds the rows beside the field, and SwiftUI takes first responder with them —
    /// the same hazard the palette's search field is pinned in place to avoid.
    @ViewBuilder
    private var filterSection: some View {
        if core.extensions.installed.count > 3 {
            Section {
                SettingsFilterField(prompt: "Filter extensions…", query: $filter)
            }
        }
    }

    @ViewBuilder
    private var library: some View {
        Section {
            if core.extensions.installed.isEmpty {
                emptyLibrary
            } else if matching.isEmpty {
                Text("No extension matches \u{201C}\(filter)\u{201D}.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matching) { entry in
                    ExtensionSettingsRow(
                        installed: entry,
                        isExpanded: expanded == entry.manifest.name,
                        onToggle: {
                            expanded = expanded == entry.manifest.name ? nil : entry.manifest.name
                        },
                        onUninstall: { core.extensionCoordinator.confirmUninstall(entry) })
                }
            }
        } header: {
            HStack {
                Text(
                    core.extensions.installed.isEmpty
                        ? "Installed" : "Installed (\(core.extensions.installed.count))")
                Spacer()
                addMenu
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Nothing installed yet.")
            Text(
                raycastAvailable
                    ? "Search the registries, import what Raycast has already built, or add a "
                        + "folder you built yourself."
                    : "Search the registries, or add a folder you built yourself."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addMenu: some View {
        Menu {
            Button("Browse Extensions\u{2026}") { browsingStore = true }
            Divider()
            Button("Import from Raycast\u{2026}", action: openImport)
                .disabled(!raycastAvailable)
            Button("Add from Folder\u{2026}", action: addFolder)
        } label: {
            Label("Add Extension", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .fixedSize()
        .help("Add an extension")
    }

    private var raycastAvailable: Bool {
        FileManager.default.fileExists(atPath: ExtensionCatalog.raycastExtensionsDirectory().path)
    }

    // MARK: - Adding

    private func openImport() {
        Task {
            importCandidates = ImportCandidates(
                entries: await core.extensions.raycastImportCandidates())
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        Task {
            error = nil
            for url in panel.urls {
                do {
                    try await core.extensions.install(from: url)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func importAll(_ chosen: [InstalledExtension]) async {
        error = nil
        let failed = await core.extensions.importAllFromRaycast(chosen)
        await findPending()
        guard !failed.isEmpty else { return }
        error = "Couldn't import \(failed.joined(separator: ", "))."
    }
}

/// What Raycast's API does and doesn't reach here. Above the library rather than below it: the honest
/// answer to "will my extension work" belongs before the thing that installs one.
///
/// A `Section(isExpanded:)` rather than a `DisclosureGroup`: it is the collapsible a macOS settings
/// form actually uses, and its whole header row is the target rather than the chevron alone.
private struct CompatibilityNotice: View {
    @State private var expanded = false

    var body: some View {
        Section(isExpanded: $expanded) {
            detail(
                "Works", symbol: "checkmark.circle", tint: .green,
                text:
                    "Commands that show a list, a detail view, a form or a grid, and ones that just "
                    + "run. Preferences, arguments, per-extension storage, the clipboard, toasts and "
                    + "HUDs, and most of the Node APIs an extension reaches for.")
            detail(
                "Doesn't, yet", symbol: "xmark.circle", tint: .orange,
                text:
                    "Signing in through Raycast's OAuth redirect, menu-bar commands, and Raycast's "
                    + "own AI, browser and window-management services. An extension that needs one "
                    + "says so when you run it rather than failing quietly.")
        } header: {
            Text("Compatibility")
        }
    }

    private func detail(_ title: String, symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: Theme.Size.settingsRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One installed extension: a summary row that expands into its preferences, its commands and their
/// shortcuts, and the button that removes it.
private struct ExtensionSettingsRow: View {
    let installed: InstalledExtension
    let isExpanded: Bool
    let onToggle: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SettingsRow(title: installed.title, subtitle: summary) {
                ExtensionIconButton(installed: installed)
            } trailing: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            // The whole row toggles, so the chevron is an affordance rather than the only target.
            .contentShape(.rect)
            .onTapGesture(perform: onToggle)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                isExpanded ? "Hide \(installed.title) settings" : "Configure \(installed.title)")

            if isExpanded { expandedBody }
        }
    }

    /// Grouped and ruled: preferences, then one block per command, then what removes the extension.
    /// Flat, these ran together into one undifferentiated column of controls.
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if !installed.manifest.preferences.isEmpty {
                group("Preferences") {
                    ForEach(installed.manifest.preferences, id: \.name) { schema in
                        ExtensionPreferenceField(
                            extensionName: installed.manifest.name, schema: schema)
                    }
                }
            }
            group("Commands") {
                ForEach(Array(installed.manifest.commands.enumerated()), id: \.element.id) {
                    index, command in
                    if index > 0 { Divider() }
                    CommandSettings(installed: installed, command: command)
                }
            }
            Divider()
            HStack {
                Text(installed.manifest.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Uninstall\u{2026}", role: .destructive, action: onUninstall)
            }
        }
        .padding(.leading, Theme.Size.settingsRowIcon + Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func group<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var summary: String {
        let count = installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        let author = installed.manifest.author
        return author.isEmpty ? commands : "\(commands) \u{00B7} \(author)"
    }
}

/// One command inside an expanded extension: what it is, its shortcut, and its own preferences.
private struct CommandSettings: View {
    let installed: InstalledExtension
    let command: ExtensionCommand

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(command.title)
                    if !command.description.isEmpty {
                        Text(command.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Spacing.lg)
                if command.mode.isSupported {
                    // Per command, not per extension: a shortcut has to land on one thing to run,
                    // and an extension is a set of commands.
                    ShortcutRecorder(
                        action: .extensionCommand(
                            entryID: ExtensionCommandRef(
                                extensionName: installed.manifest.name, commandName: command.name
                            ).entryID))
                } else {
                    Text("Menu bar command")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(command.mode.unsupportedReason ?? "")
                }
            }
            if !command.preferences.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(command.preferences, id: \.name) { schema in
                        ExtensionPreferenceField(
                            extensionName: installed.manifest.name, schema: schema)
                    }
                }
                .padding(.leading, Theme.Spacing.md)
            }
        }
    }
}

/// The extension's launcher icon, with the badge that re-skins it. The icon *is* the button: it is
/// what the change applies to, so it is what you press to change it.
private struct ExtensionIconButton: View {
    /// Icon artwork is fitted to the share of its canvas an app icon paints, so the box has to be a
    /// little larger than a symbol's to land the ink at the same size as the rows around it.
    static let side = Theme.Size.rowIcon

    let installed: InstalledExtension
    @Environment(AppCore.self) private var core
    @State private var picking = false

    /// Read from the store, not the manager: picking publishes from there, so the preview and the
    /// open popover both observe *it*.
    private var appearance: ExtensionAppearance? {
        core.extensions.appearances.appearance(for: installed.manifest.name)
    }

    var body: some View {
        Button {
            picking = true
        } label: {
            preview
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.accentColor)
                        .offset(x: 3, y: 3)
                }
        }
        .buttonStyle(.plain)
        .help("Change the launcher icon")
        .accessibilityLabel("Change the launcher icon for \(installed.title)")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            ExtensionAppearancePicker(
                current: appearance ?? .fallback,
                isCustom: appearance != nil,
                onPick: { core.extensions.setAppearance($0, for: installed.manifest.name) },
                onReset: { core.extensions.setAppearance(nil, for: installed.manifest.name) })
        }
    }

    /// Exactly what the launcher row will draw — the shipped image, or the chosen tile.
    @ViewBuilder
    private var preview: some View {
        if let appearance {
            SymbolTile(symbol: appearance.symbol, tint: appearance.tint, side: Self.side)
        } else {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Self.side)
        }
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
                .frame(width: Theme.Size.formLabelWidth, alignment: .trailing)
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
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
            .onChange(of: text) { _, value in save(value) }
        case .password:
            SecureField(schema.placeholder ?? "", text: $text)
                .textFieldStyle(.roundedBorder)
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
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
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

/// One candidate from a local Raycast install, and whether we already have it.
struct RaycastImportCandidate: Identifiable {
    let installed: InstalledExtension
    let isInstalled: Bool

    var id: String { installed.id }
}

/// One scan of the local Raycast install, carried as the import sheet's presentation item.
private struct ImportCandidates: Identifiable {
    let id = UUID()
    let entries: [RaycastImportCandidate]
}

/// Picker over the extensions a locally installed Raycast has already built. Everything not already
/// here starts selected, so the common case — "import what Raycast just added" — is one press.
private struct ExtensionImportSheet: View {
    let candidates: [RaycastImportCandidate]
    let onImport: ([InstalledExtension]) -> Void
    let onCancel: () -> Void
    @State private var chosen: Set<String> = []
    @State private var seeded = false

    private var fresh: [RaycastImportCandidate] { candidates.filter { !$0.isInstalled } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Import from Raycast").font(.title2.weight(.bold))
                Text(subtitle)
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
                                resolved: candidate.installed.iconPath.map {
                                    ExtensionImage.Resolved(source: .file($0))
                                }, size: Theme.Size.rowIcon)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(candidate.installed.title).font(.body)
                                Text(detail(for: candidate))
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
                        ? [] : Set(candidates.map(\.installed.manifest.name))
                }
                .disabled(candidates.isEmpty)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Import \(chosen.isEmpty ? "" : "(\(chosen.count))")") {
                    onImport(
                        candidates.map(\.installed).filter { chosen.contains($0.manifest.name) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
        .onAppear {
            // Once: re-seeding on every render would fight the user's own deselection.
            guard !seeded else { return }
            seeded = true
            chosen = Set(fresh.map(\.installed.manifest.name))
        }
    }

    private var subtitle: String {
        guard !candidates.isEmpty else {
            return "No built extensions found in ~/.config/raycast/extensions."
        }
        guard !fresh.isEmpty else {
            return "Everything Raycast has built is already here. Re-import one to update it."
        }
        let noun = fresh.count == 1 ? "one" : "\(fresh.count)"
        return "\(noun) not here yet, already selected. Re-importing an existing one updates it."
    }

    private func detail(for candidate: RaycastImportCandidate) -> String {
        let count = candidate.installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        return candidate.isInstalled ? "\(commands) · already installed" : commands
    }

    private func binding(for candidate: RaycastImportCandidate) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(candidate.installed.manifest.name) },
            set: { isOn in
                if isOn {
                    chosen.insert(candidate.installed.manifest.name)
                } else {
                    chosen.remove(candidate.installed.manifest.name)
                }
            })
    }
}
