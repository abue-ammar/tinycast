import SwiftUI

/// Settings › Extensions: the master switch, then one row per installed extension that expands in
/// place into its icon, its preferences and its commands.
struct ExtensionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var expanded: String?
    @State private var filter = ""
    @State private var importCandidates: ImportCandidates?
    @State private var browsingStore = false
    @State private var error: String?
    /// Extensions Raycast has built that aren't here yet, refreshed whenever the pane appears.
    @State private var pending: [RaycastImportCandidate] = []

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
                if !pending.isEmpty { newInRaycast }
                library
                ExtensionRegistriesSection()
            }
            .settingsEnabled(settings.extensionsEnabled)
        }
        .formStyle(.grouped)
        .releasesFocusOnOutsideClick()
        // Escape and Return are the keyboard way out of the same field.
        .onExitCommand { NSApp.keyWindow?.makeFirstResponder(nil) }
        .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
        .onChange(of: settings.extensionsShowInLauncher) {
            core.extensionCoordinator.applyExtensionsLauncherPresence()
        }
        // Presented by item, not by a bare flag: with `isPresented` SwiftUI builds the sheet from the
        // body snapshot that precedes the button's state write, so the freshly scanned candidates
        // arrived as an empty list.
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
        .onReceive(NotificationCenter.default.publisher(for: .tinycastSelectExtension)) { note in
            if let name = note.object as? String { expanded = name }
        }
        .task {
            await core.extensions.refresh()
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
            Text(
                "Tinycast runs Raycast's extension API on its own runtime, so a few corners of it "
                    + "are Raycast's alone. An extension that needs one says so when you run it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - What Raycast has that we don't

    /// Raycast installs into its own directory, and nothing tells us when it does. Rather than leave
    /// that to be discovered, the pane looks every time it opens and says what it found.
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

    // MARK: - The library

    /// Filter row, then the list as a single form row holding its own stack — the shape
    /// `LauncherItemsSection` uses, so a long list reads as a list rather than as a run of settings.
    /// Separation inside the content layer comes from separators and a standard fill, not from
    /// glass: Liquid Glass belongs to the layer above the content, not inside it.
    private var library: some View {
        Section {
            if core.extensions.installed.isEmpty {
                Text("Install one to see it here.")
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
            HStack {
                Text(
                    core.extensions.installed.isEmpty
                        ? "Installed" : "Installed (\(core.extensions.installed.count))")
                Spacer()
                Menu("Install…") {
                    Button("Browse Extensions…") { browsingStore = true }
                    Divider()
                    Button("Import from Raycast…", action: openImport)
                        .disabled(!raycastAvailable)
                    Button("Add from Folder…", action: addFolder)
                }
                .menuStyle(.button)
                .fixedSize()
            }
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

    private func findPending() async {
        guard core.settings.extensionsEnabled, raycastAvailable else {
            pending = []
            return
        }
        pending = await core.extensions.raycastImportCandidates().filter { !$0.isInstalled }
    }
}

/// One extension in the list: a summary row, and — while open — its settings on a card inset beneath
/// it. The card is what separates "this extension's settings" from the rows of the list around it;
/// Apple's guidance is to build that structure in the content layer out of standard materials and
/// separators rather than glass, which belongs to the layer floating above content.
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

    private var settings: some View {
        // A `Form` in the columns style inside the card: the controls keep the aligned label column
        // and system styling they would lose in a hand-built stack, without the grouped chrome that
        // would fight the card around them.
        Form {
            ExtensionIconRow(installed: installed)

            if !installed.manifest.preferences.isEmpty {
                group("Preferences") {
                    ForEach(installed.manifest.preferences, id: \.name) { schema in
                        ExtensionPreferenceField(
                            extensionName: installed.manifest.name, schema: schema)
                    }
                }
            }

            group(installed.manifest.commands.count == 1 ? "Command" : "Commands") {
                ForEach(Array(installed.manifest.commands.enumerated()), id: \.element.id) {
                    index, command in
                    if index > 0 { Divider() }
                    CommandRow(installed: installed, command: command)
                }
            }

            HStack {
                Spacer()
                Button("Uninstall…", role: .destructive, action: onUninstall)
            }
        }
        .formStyle(.columns)
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
        // Inset from the row's leading edge so the card reads as belonging to the row above it.
        .padding(.leading, Theme.Size.rowIcon)
    }

    /// A titled run inside the card, so preferences and commands don't read as one flat column.
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

    private var subtitle: String {
        let count = installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        let author = installed.manifest.author
        return author.isEmpty ? commands : "\(commands) · \(author)"
    }
}

/// One command: its shortcut, and any preferences it declares of its own.
private struct CommandRow: View {
    let installed: InstalledExtension
    let command: ExtensionCommand

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
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
            ForEach(command.preferences, id: \.name) { schema in
                ExtensionPreferenceField(extensionName: installed.manifest.name, schema: schema)
            }
        }
    }
}

/// The launcher icon, and the picker that replaces it.
private struct ExtensionIconRow: View {
    let installed: InstalledExtension
    @Environment(AppCore.self) private var core
    @State private var picking = false

    /// Read from the store, not the manager: picking publishes from there, so the preview and the
    /// open popover both observe *it*.
    private var appearance: ExtensionAppearance? {
        core.extensions.appearances.appearance(for: installed.manifest.name)
    }

    var body: some View {
        LabeledContent {
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
        } label: {
            Text("Launcher icon")
            Text(
                appearance == nil
                    ? "Using the icon this extension ships."
                    : "Replaced with a Tinycast icon.")
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

/// One preference control, backed by `ExtensionStorage` so a command reads it through
/// `getPreferenceValues()`.
private struct ExtensionPreferenceField: View {
    let extensionName: String
    let schema: ExtensionPreferenceSchema
    @Environment(AppCore.self) private var core
    @State private var text: String = ""
    @State private var flag: Bool = false

    /// Wide enough for a path, and fixed: left to itself a text field in a form row collapses to
    /// nothing next to a long label, which is how one ends up invisible but still clickable.
    private static let controlWidth: CGFloat = 200

    private var storage: ExtensionStorage { core.extensions.storage }

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(schema.displayTitle)
            if let description = schema.description, !description.isEmpty {
                Text(schema.required ? description + " Required." : description)
            } else if schema.required {
                Text("Required.")
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
            .fixedSize()
            .onChange(of: text) { _, value in save(value) }
        case .password:
            SecureField(schema.placeholder ?? "", text: $text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .pointerStyle(.horizontalText)
                .frame(width: Self.controlWidth)
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
                .frame(width: Self.controlWidth)
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
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
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
        let noun = fresh.count == 1 ? "One" : "\(fresh.count)"
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
