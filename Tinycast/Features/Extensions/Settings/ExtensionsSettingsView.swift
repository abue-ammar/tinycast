import SwiftUI

/// Settings › Extensions: the master switch, then a row per extension that expands in place.
struct ExtensionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var expanded: String?
    @State private var filter = ""
    @State private var importCandidates: ImportCandidates?
    @State private var browsingStore = false
    @State private var editingRegistries = false
    @State private var error: String?
    /// Extensions Raycast has built that aren't here yet, refreshed whenever the pane appears.
    @State private var pending: [RaycastImportCandidate] = []
    /// What a bulk import is doing, so a thirty-item batch reports rather than going quiet.
    @State private var importProgress: (done: Int, total: Int)?
    @State private var importSummary: String?
    /// What a cleanup would reclaim, rescanned whenever the installed set changes.
    @State private var reclaimable = ExtensionCleanup.Report()

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
                compatibility
                install
                library
            }
            .settingsEnabled(settings.extensionsEnabled)

            // Outside the enabled group: leftovers are on disk whether or not extensions are on.
            storage
        }
        .formStyle(.grouped)
        .releasesFocusOnOutsideClick()
        // Escape and Return are the keyboard way out of the same field.
        .onExitCommand { NSApp.keyWindow?.makeFirstResponder(nil) }
        .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
        .onChange(of: settings.extensionsShowInLauncher) {
            core.extensionCoordinator.applyExtensionsLauncherPresence()
        }
        // By item, not a flag: `isPresented` builds the sheet from a snapshot taken before the write.
        .sheet(item: $importCandidates) { candidates in
            ExtensionImportSheet(
                candidates: candidates.entries,
                onImport: { chosen in
                    importCandidates = nil
                    Task { await importAll(chosen) }
                },
                onCancel: { importCandidates = nil })
        }
        .sheet(isPresented: $browsingStore) {
            ExtensionStoreSheet(onClose: { browsingStore = false })
        }
        .sheet(isPresented: $editingRegistries) {
            ExtensionRegistriesSheet(onClose: { editingRegistries = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .tinycastSelectExtension)) { note in
            if let name = note.object as? String { expanded = name }
        }
        .onChange(of: core.extensions.installed.count) { Task { await measureReclaimable() } }
        .task {
            await core.extensions.refresh()
            await measureReclaimable()
            await findPending()
        }
    }

    // MARK: - Compatibility

    private var compatibility: some View {
        Section {
            LabeledContent {
                EmptyView()
            } label: {
                Label("What works", systemImage: "checkmark.circle")
                Text(
                    "List, detail, form and grid commands, and ones that just run. Preferences, "
                        + "arguments, storage, the clipboard, toasts and HUDs.")
            }
            LabeledContent {
                EmptyView()
            } label: {
                Label("What doesn't, yet", systemImage: "xmark.circle")
                Text(
                    "Raycast's OAuth sign-in, menu-bar commands, and Raycast's own AI, browser and "
                        + "window-management services.")
            }
        } header: {
            Text("Compatibility")
        } footer: {
            Text("An extension that needs something missing says so when you run it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - The library

    /// `LauncherItemsSection`'s shape, so a long list reads as a list rather than a run of settings.
    private var library: some View {
        Section {
            if core.extensions.installed.isEmpty {
                Text("Nothing installed yet — search for one under Install, below.")
                    .foregroundStyle(.secondary)
            } else {
                if core.extensions.installed.count > 3 {
                    SettingsFilterField(prompt: "Filter extensions…", query: $filter)
                }
                if matching.isEmpty {
                    Text("No extension matches \u{201C}\(filter)\u{201D}.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // One row holding a lazy stack: a `Form` realizes every row it is handed.
                    LazyVStack(spacing: 0) {
                        ForEach(matching) { installed in
                            if installed.id != matching.first?.id { Divider() }
                            ExtensionDisclosure(
                                installed: installed,
                                isExpanded: expanded == installed.manifest.name,
                                onToggle: {
                                    expanded =
                                        expanded == installed.manifest.name
                                        ? nil : installed.manifest.name
                                },
                                onUninstall: {
                                    core.extensionCoordinator.confirmUninstall(installed)
                                })
                        }
                    }
                    .padding(.vertical, -Self.rowPadding)
                }
            }
        } header: {
            Text(
                core.extensions.installed.isEmpty
                    ? "Installed" : "Installed (\(core.extensions.installed.count))")
        } footer: {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// A grouped `Form` row's own vertical padding, which the stack above has to give back.
    private static let rowPadding: CGFloat = 15

    private var matching: [InstalledExtension] {
        guard !filter.isEmpty else { return core.extensions.installed }
        return core.extensions.installed.filter { entry in
            entry.title.localizedCaseInsensitiveContains(filter)
                || entry.manifest.commands.contains {
                    $0.title.localizedCaseInsensitiveContains(filter)
                }
        }
    }

    /// Three rows rather than a menu: a search, a copy and a folder behave differently enough to say so.
    private var install: some View {
        Section {
            SettingsRow(title: "Search extensions", subtitle: searchSubtitle) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            } trailing: {
                // Beside search, because this is the setting that decides what search can find.
                Button("Registries…") { editingRegistries = true }
                Button("Search…") { browsingStore = true }
            }
            // A state of this row, not a card above the pane: it is the same job as the button beside it.
            SettingsRow(title: "Import from Raycast", subtitle: importSubtitle) {
                Image(systemName: "arrow.down.doc")
                    .foregroundStyle(pending.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            } trailing: {
                if importProgress != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Import…", action: openImport)
                        .disabled(!raycastAvailable)
                    if !pending.isEmpty {
                        Button("Import All") { Task { await importAll(pending.map(\.installed)) } }
                    }
                }
            }
            SettingsRow(
                title: "Add from folder",
                subtitle: "A folder holding package.json and the built command files."
            ) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            } trailing: {
                Button("Choose…", action: addFolder)
            }
        } header: {
            Text("Install")
        } footer: {
            if let error {
                // Under the buttons that caused it: it used to sit beneath the list, far above.
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// An install cleans up after itself, so in normal use this row has nothing to offer.
    private var storage: some View {
        Section {
            SettingsRow(title: "Leftover files", subtitle: reclaimableSubtitle) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(reclaimable.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            } trailing: {
                Button("Clean Up…") {
                    Task {
                        await core.extensionCoordinator.confirmCleanup(reclaimable)
                        await measureReclaimable()
                    }
                }
                .disabled(reclaimable.isEmpty)
            }
        } header: {
            Text("Storage")
        }
    }

    private var reclaimableSubtitle: String {
        guard !reclaimable.isEmpty else { return "Nothing to clean up." }
        let items = reclaimable.items == 1 ? "1 item" : "\(reclaimable.items) items"
        return "Reclaims \(ExtensionCleanup.formatted(bytes: reclaimable.bytes)) from \(items)."
    }

    /// Off-main: measuring walks a `node_modules`, which is tens of thousands of files.
    private func measureReclaimable() async {
        let installed = Set(core.extensions.installed.map(\.manifest.name))
        let roots = ExtensionCleanup.defaultRoots()
        reclaimable = await Task.detached(priority: .utility) {
            ExtensionCleanup.reclaimable(installed: installed, in: roots)
        }.value
    }

    /// Names what searching will cover, so the row says what the Registries button is for.
    private var searchSubtitle: String {
        let on = core.settings.extensionRegistries.filter(\.isEnabled)
        guard !on.isEmpty else { return "No registries enabled — searching would find nothing." }
        return "Searching \(on.map(\.name).joined(separator: ", "))."
    }

    private var importSubtitle: String {
        if let importProgress {
            return "Importing \(importProgress.done) of \(importProgress.total)…"
        }
        if let importSummary { return importSummary }
        guard raycastAvailable else {
            return "No Raycast install found in ~/.config — checked raycast and raycast-x."
        }
        guard !pending.isEmpty else {
            return "Copy what Raycast has already built. No Node or package manager needed."
        }
        let names = pending.map(\.installed.title)
            .sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
            .prefix(3)
            .joined(separator: ", ")
        let more = pending.count > 3 ? " and \(pending.count - 3) more" : ""
        return "\(pending.count) not here yet — \(names)\(more)."
    }

    private var raycastAvailable: Bool {
        ExtensionCatalog.raycastExtensionsDirectory() != nil
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
        importSummary = nil
        importProgress = (0, chosen.count)
        let failed = await core.extensions.importAllFromRaycast(chosen) { done in
            importProgress = (done, chosen.count)
        }
        importProgress = nil
        await findPending()
        let imported = chosen.count - failed.count
        if failed.isEmpty {
            importSummary = "Imported \(imported) extension\(imported == 1 ? "" : "s")."
        } else {
            importSummary = "Imported \(imported); \(failed.count) failed."
            error = "Couldn't import \(failed.joined(separator: ", "))."
        }
    }

    private func findPending() async {
        guard core.settings.extensionsEnabled, raycastAvailable else {
            pending = []
            return
        }
        pending = await core.extensions.raycastImportCandidates().filter { !$0.isInstalled }
    }
}

/// A summary row, and while open its settings on an inset card — separators and fill, never glass.
private struct ExtensionDisclosure: View {
    let installed: InstalledExtension
    let isExpanded: Bool
    let onToggle: () -> Void
    let onUninstall: () -> Void

    /// A grouped `Form` row's own vertical padding, restored around the summary.
    private static let rowPadding: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
                .padding(.vertical, Self.rowPadding)
            if isExpanded {
                settings
                    .padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    private var summary: some View {
        SettingsRow(title: installed.title, subtitle: subtitle) {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon)
        } trailing: {
            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        // The whole row toggles: a `DisclosureGroup` would only respond to its chevron.
        .contentShape(.rect)
        .onTapGesture(perform: onToggle)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            isExpanded ? "Hide \(installed.title) settings" : "Configure \(installed.title)")
    }

    /// One `Grid` for every run: separate grids size their columns apart, stranding controls mid-row.
    private var settings: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Grid(
                alignment: .leading, horizontalSpacing: Theme.Spacing.lg,
                verticalSpacing: Theme.Spacing.md
            ) {
                // No heading: these two are one idea, and first so a 19-command extension can't bury them.
                ExtensionLauncherRow(installed: installed)
                ExtensionIconRow(installed: installed)

                if !installed.manifest.preferences.isEmpty {
                    rule
                    heading("Preferences")
                    ForEach(
                        Array(installed.manifest.preferences.enumerated()), id: \.element.name
                    ) { index, schema in
                        if index > 0 { rule }
                        ExtensionPreferenceRow(
                            extensionName: installed.manifest.name, schema: schema)
                    }
                }

                rule
                heading(installed.manifest.commands.count == 1 ? "Command" : "Commands")
                ForEach(Array(installed.manifest.commands.enumerated()), id: \.element.id) {
                    index, command in
                    if index > 0 { rule }
                    CommandRows(installed: installed, command: command)
                }
            }
            HStack {
                Spacer()
                Button("Uninstall…", role: .destructive, action: onUninstall)
            }
        }
        // Indented under the row's icon, so the settings read as belonging to the row above them.
        .padding(.leading, Theme.Size.rowIcon + Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A step below the pane's section headers, by size and colour: nothing here sets a heading in caps.
    private func heading(_ title: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .gridCellColumns(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Spacing.xs)
        }
    }

    /// The hairline every other multi-row group in the app puts between its rows.
    private var rule: some View {
        GridRow {
            Divider()
                .gridCellColumns(2)
        }
    }

    private var subtitle: String {
        let count = installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        let author = installed.manifest.author
        return author.isEmpty ? commands : "\(commands) · \(author)"
    }
}

/// One card row: the label left, the control right, columns aligned by the enclosing `Grid`.
private struct SettingsCardRow<Control: View>: View {
    /// Wide enough for a path field, and the trailing edge every control in the column shares.
    static var controlWidth: CGFloat { 200 }

    let title: String
    var detail: String?
    /// Leading inset for a row that belongs to the row above it, rather than to the run.
    var indent: CGFloat = 0
    /// A short fact about the row, beside its name rather than in the control column.
    var badge: String?
    @ViewBuilder var control: Control

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                    if let badge {
                        Text(badge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.controlSurface, in: .capsule)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, indent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridColumnAlignment(.leading)
            // One width for every control: left alone a toggle, a pop-up and a field end on three edges.
            control
                .frame(width: SettingsCardRow.controlWidth, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
    }
}

/// One command: its shortcut, then any preferences it declares of its own.
private struct CommandRows: View {
    let installed: InstalledExtension
    let command: ExtensionCommand

    /// A fact about the command, so it sits by the name as a badge rather than a warning colour.
    private var badge: String? { command.mode.isSupported ? nil : "Menu Bar" }

    var body: some View {
        SettingsCardRow(title: command.title, detail: command.description, badge: badge) {
            if command.mode.isSupported {
                // Per command, not per extension: a shortcut has to land on one thing to run.
                ShortcutRecorder(
                    action: .extensionCommand(
                        entryID: ExtensionCommandRef(
                            extensionName: installed.manifest.name, commandName: command.name
                        ).entryID),
                    isQuiet: true)
            }
        }
        // Indented under its command: at the same inset the association rests on reading order alone.
        ForEach(command.preferences, id: \.name) { schema in
            ExtensionPreferenceRow(
                extensionName: installed.manifest.name, schema: schema, indent: Theme.Spacing.lg)
        }
    }
}

/// Hides one extension's commands: an import can add hundreds, and the global switch is too blunt.
private struct ExtensionLauncherRow: View {
    let installed: InstalledExtension
    @Environment(AppCore.self) private var core

    private var entryIDs: [String] {
        installed.manifest.commands.map {
            ExtensionCommandRef(extensionName: installed.manifest.name, commandName: $0.name)
                .entryID
        }
    }

    private var isVisible: Bool {
        entryIDs.contains { !core.visibility.hiddenItemKeys.contains($0) }
    }

    var body: some View {
        SettingsCardRow(
            title: "Show in launcher",
            detail: isVisible
                ? "Its commands appear in launcher search."
                : "Hidden from launcher search; shortcuts still work."
        ) {
            // A closure, not `set: setVisible`: an actor-isolated method as a setter crashes IRGen.
            Toggle("", isOn: Binding(get: { isVisible }, set: { setVisible($0) }))
                .labelsHidden()
        }
    }

    private func setVisible(_ visible: Bool) {
        for entryID in entryIDs {
            core.visibility.setItemVisible(
                visible,
                for: AppEntry(
                    id: entryID, name: "", url: installed.directory, bundleID: nil,
                    kind: .extensionCommand))
        }
    }
}

/// The launcher icon, and the picker that replaces it.
private struct ExtensionIconRow: View {
    let installed: InstalledExtension
    @Environment(AppCore.self) private var core
    @State private var picking = false

    /// From the store, not the manager: picking publishes there, so preview and popover both observe it.
    private var appearance: ExtensionAppearance? {
        core.extensions.appearances.appearance(for: installed.manifest.name)
    }

    var body: some View {
        SettingsCardRow(
            title: "Launcher icon",
            detail: appearance == nil
                ? "The icon this extension ships." : "Replaced with a Tinycast icon."
        ) {
            HStack(spacing: Theme.Spacing.md) {
                preview
                Button("Change…") { picking = true }
                    .popover(isPresented: $picking, arrowEdge: .bottom) {
                        ExtensionAppearancePicker(
                            current: appearance ?? .fallback,
                            isCustom: appearance != nil,
                            onPick: { core.extensions.setAppearance($0, for: installed.manifest.name) },
                            onReset: {
                                core.extensions.setAppearance(nil, for: installed.manifest.name)
                            })
                    }
            }
        }
    }

    /// Exactly what the launcher row will draw — the shipped image, or the chosen tile.
    @ViewBuilder
    private var preview: some View {
        if let appearance {
            SymbolTile(symbol: appearance.symbol, tint: appearance.tint, side: Theme.Size.rowIcon)
        } else {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon)
        }
    }
}

/// One preference control, stored so a command reads it through `getPreferenceValues()`.
private struct ExtensionPreferenceRow: View {
    let extensionName: String
    let schema: ExtensionPreferenceSchema
    var indent: CGFloat = 0
    @Environment(AppCore.self) private var core
    @State private var text: String = ""
    @State private var flag: Bool = false

    private var storage: ExtensionStorage { core.extensions.storage }

    var body: some View {
        SettingsCardRow(title: schema.displayTitle, detail: detail, indent: indent) {
            control
        }
        .onAppear(perform: load)
    }

    private var detail: String? {
        let description = schema.description ?? ""
        guard schema.required else { return description }
        return description.isEmpty ? "Required." : description + " Required."
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
            SecureField("", text: $text, prompt: schema.placeholder.map(Text.init))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .pointerStyle(.horizontalText)
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
            TextField("", text: $text, prompt: schema.placeholder.map(Text.init))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .pointerStyle(.horizontalText)
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

/// What a local Raycast has built. Anything not here starts selected, so the common case is one press.
private struct ExtensionImportSheet: View {
    let candidates: [RaycastImportCandidate]
    let onImport: ([InstalledExtension]) -> Void
    let onCancel: () -> Void
    @State private var chosen: Set<String> = []
    @State private var seeded = false
    @State private var filter = ""

    private var fresh: [RaycastImportCandidate] { candidates.filter { !$0.isInstalled } }

    /// Thirty-odd rows is past the point where scanning beats filtering — the same field the pane
    /// puts above its own list.
    private var matching: [RaycastImportCandidate] {
        guard !filter.isEmpty else { return candidates }
        return candidates.filter {
            $0.installed.title.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Import from Raycast").font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if candidates.count > 6 {
                SettingsFilterField(prompt: "Filter…", query: $filter)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matching) { candidate in
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
                                Text(candidate.installed.title)
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
            .overflowFade()
            .thinScrollbar()
            .frame(minHeight: 220)

            HStack {
                // Reads against what is actually selected, so it is never a button that does nothing.
                Button(allChosen ? "Deselect All" : "Select All") {
                    chosen = allChosen ? [] : Set(candidates.map(\.installed.manifest.name))
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

    private var allChosen: Bool { chosen.count == candidates.count }

    private var subtitle: String {
        guard !candidates.isEmpty else {
            return "No built extensions found in ~/.config/raycast/extensions."
        }
        guard !fresh.isEmpty else {
            return "Everything Raycast has built is already here. Import one again to update it."
        }
        let count = fresh.count == 1 ? "one" : "\(fresh.count)"
        return "The \(count) you don't have yet \(fresh.count == 1 ? "is" : "are") already ticked. "
            + "Ticking one you have updates it."
    }

    private func detail(for candidate: RaycastImportCandidate) -> String {
        let count = candidate.installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        return candidate.isInstalled ? "\(commands) · installed — tick to update" : commands
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

extension String {
    /// Sorts on the first letter that is one: a name like "(Basic) Bookmarks" otherwise leads every
    /// list on the strength of its bracket.
    fileprivate var sortKey: String {
        String(drop { !$0.isLetter && !$0.isNumber })
    }
}
