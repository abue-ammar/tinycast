import SwiftUI

/// Settings › Extensions: the master switch, then a row per extension that expands in place.
struct ExtensionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SettingsNavigationState.self) private var navigation
    @State private var expanded: String?
    @State private var filter = ""
    @State private var importCandidates: ImportCandidates?
    @State private var browsingStore = false
    @State private var storeInstall: ExtensionDeepLink.StoreInstall?
    @State private var installingFromGitHub = false
    @State private var error: String?
    @State private var updateError: String?
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
                anchor: .extensionsExtensions,
                enableTitle: "Enable extensions",
                enableSubtitle: "Run Raycast extensions natively.",
                // Enabling is consent to run third-party code, so the setter confirms.
                isEnabled: Binding(
                    get: { settings.extensionsEnabled },
                    set: { core.extensionCoordinator.setExtensionsEnabled($0) }),
                showsInLauncher: $settings.extensionsShowInLauncher,
                showsIcon: true)

            Group {
                install
                library
                compatibility
            }
            .settingsEnabled(settings.extensionsEnabled)

            // Outside the enabled group: leftovers are on disk whether or not extensions are on.
            storage
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.extensions)
        .releasesFocusOnOutsideClick()
        // Escape and Return are the keyboard way out of the same field.
        .onExitCommand { NSApp.keyWindow?.makeFirstResponder(nil) }
        .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
        // By item: `isPresented` builds the panel from a snapshot taken before the write.
        .settingsEditorPanel(item: $importCandidates) { candidates in
            ExtensionImportPanel(
                candidates: candidates.entries,
                onImport: { chosen in
                    importCandidates = nil
                    Task { await importAll(chosen) }
                },
                onCancel: { importCandidates = nil })
        }
        .settingsEditorPanel(isPresented: $browsingStore) {
            ExtensionStorePanel(onClose: { browsingStore = false })
        }
        .settingsEditorPanel(item: $storeInstall) { install in
            ExtensionStorePanel(storeInstall: install, onClose: { storeInstall = nil })
        }
        .settingsEditorPanel(isPresented: $installingFromGitHub) {
            ExtensionGitHubPanel(onClose: { installingFromGitHub = false })
        }
        .onChange(of: navigation.scrollRequest, initial: true) {
            if case .row(.extensionsInstalled, let name)? = navigation.scrollRequest?.target {
                (expanded, filter) = (name, "")
            }
        }
        .onChange(of: core.pendingExtensionStoreInstall, initial: true) { _, request in
            guard let request else { return }
            storeInstall = request
            core.pendingExtensionStoreInstall = nil
        }
        .onChange(of: core.extensions.installed.count) { Task { await measureReclaimable() } }
        .task {
            await core.extensions.refresh()
            await measureReclaimable()
            await findPending()
            await core.extensions.checkForUpdates()
        }
    }

    // MARK: - Compatibility

    private var compatibility: some View {
        Section {
            SettingsRow(
                title: "What works",
                subtitle:
                    "List, detail, form, grid, no-view and menu-bar commands, plus preferences and storage.",
                subtitleLineLimit: 2
            ) {
                ExtensionSettingsIcon(systemName: "checkmark.circle")
            } trailing: {
                EmptyView()
            }
            SettingsRow(
                title: "What doesn't, yet",
                subtitle: "Raycast's AI, browser and window services.",
                subtitleLineLimit: 2
            ) {
                ExtensionSettingsIcon(systemName: "xmark.circle")
            } trailing: {
                EmptyView()
            }
        } header: {
            SettingsSectionHeader(.extensionsCompatibility)
        }
    }

    // MARK: - The library

    private var library: some View {
        Section {
            if !core.extensions.updates.isEmpty {
                updatesRow
            }
            if core.extensions.installed.isEmpty {
                Text("Nothing installed yet.")
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
                    ForEach(matching) { installed in
                        let name = installed.manifest.name
                        ExtensionDisclosure(
                            installed: installed,
                            isExpanded: expanded == name,
                            isUpdating: core.extensions.updating.contains(name),
                            onToggle: { expanded = expanded == name ? nil : name },
                            onUpdate: core.extensions.updates[name] == nil ? nil : { update([name]) },
                            onUninstall: {
                                core.extensionCoordinator.confirmUninstall(installed)
                            })
                    }
                }
            }
        } header: {
            SettingsSectionHeader(anchor: .extensionsInstalled) {
                Text(
                    core.extensions.installed.isEmpty
                        ? "Installed" : "Installed (\(core.extensions.installed.count))")
            }
        } footer: {
            if let updateError {
                Label(updateError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Above the list as well as on each row, so a batch is one press.
    private var updatesRow: some View {
        SettingsRow(
            title: "Updates available",
            subtitle: listed(core.extensions.updates.values.map(\.title)) + "."
        ) {
            ExtensionSettingsIcon(systemName: "arrow.down.circle")
        } trailing: {
            if core.extensions.updating.isEmpty {
                Button("Update All") { update(core.extensions.updates.keys.sorted()) }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func update(_ names: [String]) {
        updateError = nil
        Task {
            let failed = await core.extensions.update(names)
            if !failed.isEmpty { updateError = "Couldn't update \(failed.joined(separator: ", "))." }
        }
    }

    private var matching: [InstalledExtension] {
        guard !filter.isEmpty else { return core.extensions.installed }
        return core.extensions.installed.filter { entry in
            entry.title.localizedCaseInsensitiveContains(filter)
                || entry.manifest.commands.contains {
                    $0.title.localizedCaseInsensitiveContains(filter)
                }
        }
    }

    /// Rows rather than a menu: each route installs differently.
    private var install: some View {
        Section {
            SettingsRow(
                title: "Search extensions", subtitle: "Ready-built from the Raycast Store.",
                anchor: .extensionsInstall
            ) {
                ExtensionSettingsIcon(systemName: "magnifyingglass")
            } trailing: {
                Button("Search…") { browsingStore = true }
            }
            SettingsRow(
                title: "Install from GitHub",
                subtitle: "Builds from source with your package manager.",
                anchor: .extensionsInstall
            ) {
                ExtensionSettingsIcon(systemName: "hammer")
            } trailing: {
                Button("Install…") { installingFromGitHub = true }
            }
            // A state of this row, not a card: the same job as the button beside it.
            SettingsRow(
                title: "Import from Raycast", subtitle: importSubtitle,
                anchor: .extensionsInstall
            ) {
                ExtensionSettingsIcon(systemName: "arrow.down.doc")
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
                subtitle: "A folder with package.json and built commands.",
                anchor: .extensionsInstall
            ) {
                ExtensionSettingsIcon(systemName: "folder")
            } trailing: {
                Button("Choose…", action: addFolder)
            }
        } header: {
            SettingsSectionHeader(.extensionsInstall)
        } footer: {
            if let error {
                // Under the buttons that caused it.
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// An install cleans up after itself, so in normal use this row has nothing to offer.
    private var storage: some View {
        Section {
            SettingsRow(
                title: "Leftover files", subtitle: reclaimableSubtitle,
                anchor: .extensionsStorage
            ) {
                ExtensionSettingsIcon(systemName: "internaldrive")
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
            SettingsSectionHeader(.extensionsStorage)
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

    private var importSubtitle: String {
        if let importProgress {
            return "Importing \(importProgress.done) of \(importProgress.total)…"
        }
        if let importSummary { return importSummary }
        guard raycastAvailable else {
            return "No Raycast install found in ~/.config."
        }
        guard !pending.isEmpty else {
            return "Copies what Raycast has already built."
        }
        return "\(pending.count) not here yet — \(listed(pending.map(\.installed.title)))."
    }

    /// The first three in list order, then a count, so a long batch still fits one subtitle.
    private func listed(_ titles: [String]) -> String {
        let sorted = titles.sorted {
            $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending
        }
        let names = sorted.prefix(3).joined(separator: ", ")
        return sorted.count > 3 ? "\(names) and \(sorted.count - 3) more" : names
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

private struct ExtensionSettingsIcon: View {
    let systemName: String
    private let iconSize = Theme.Size.settingsRowIcon + Theme.Spacing.xs

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: Theme.Size.settingsRowIcon - Theme.Spacing.xs))
            .foregroundStyle(.primary)
            .frame(width: iconSize, height: iconSize)
    }
}

/// A summary row, and while open its settings on an inset card — separators and fill, never glass.
private struct ExtensionDisclosure: View {
    let installed: InstalledExtension
    let isExpanded: Bool
    let isUpdating: Bool
    let onToggle: () -> Void
    /// Nil unless the store has a newer version.
    let onUpdate: (() -> Void)?
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if isExpanded {
                settings
                    .padding(.top, Theme.Spacing.lg)
            }
        }
    }

    private var summary: some View {
        SettingsRow(title: installed.title, subtitle: subtitle) {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon)
        } trailing: {
            if isUpdating {
                ProgressView().controlSize(.small)
            } else if let onUpdate {
                Button("Update", action: onUpdate)
            }
            Button(action: onUninstall) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help("Uninstall")
            .accessibilityLabel("Uninstall \(installed.title)")
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
            isExpanded ? "Hide \(installed.title) settings" : "Configure \(installed.title)"
        )
        .id(SettingsTarget.row(.extensionsInstalled, installed.manifest.name))
    }

    /// One `Grid` for every run: separate grids size columns apart, stranding controls.
    private var settings: some View {
        Grid(
            alignment: .leading, horizontalSpacing: Theme.Spacing.lg,
            verticalSpacing: Theme.Spacing.md
        ) {
            // No heading: these two are one idea, and first so 19 commands can't bury them.
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
        // Indented under the row's icon, so the settings read as belonging to the row above them.
        .padding(.leading, Theme.Size.rowIcon + Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A step below the pane's section headers; nothing here sets a heading in caps.
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
    /// `nil` lets a pair of 120pt fields size themselves; other rows keep the shared 200pt slot.
    var controlWidth: CGFloat? = Self.controlWidth
    @ViewBuilder var control: Control

    var body: some View {
        GridRow(alignment: .center) {
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
            // One width for every control: else a toggle, a pop-up and a field end apart.
            control
                .frame(width: controlWidth, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }
}

/// One command: alias, shortcut and launcher checkbox on the title row, then its own preferences.
private struct CommandRows: View {
    let installed: InstalledExtension
    let command: ExtensionCommand
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(VisibilityStore.self) private var visibility

    /// A fact about the command, so it sits by the name as a badge rather than a warning colour.
    private var badge: String? { command.mode == .menuBar ? "Menu Bar" : nil }

    private var reference: ExtensionCommandRef {
        ExtensionCommandRef(extensionName: installed.manifest.name, commandName: command.name)
    }

    var body: some View {
        let entry = installed.launcherEntry(for: command)
        let isVisible = visibility.isItemVisible(entry)
        SettingsCardRow(
            title: command.title, detail: command.description, badge: badge, controlWidth: nil
        ) {
            HStack(spacing: Theme.Spacing.lg) {
                // Hidden or unpublished commands never reach rank, so typing here would match nothing.
                AliasField(entry: entry)
                    .settingsEnabled(settings.extensionsShowInLauncher && isVisible)
                // Per command, not per extension: a shortcut has to land on one thing to run.
                ShortcutRecorder(action: .extensionCommand(entryID: entry.id))
                Toggle(
                    "", isOn: Binding(get: { isVisible }, set: { visibility.setItemVisible($0, for: entry) })
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Show in launcher")
                .accessibilityLabel("Show \(command.title) in launcher")
            }
        }
        if command.mode == .menuBar {
            SettingsCardRow(title: "Show in menu bar", indent: Theme.Spacing.lg) {
                Toggle(
                    "Show in menu bar",
                    isOn: Binding(
                        get: { core.extensionCoordinator.menuBarIsEnabled(reference) },
                        set: { core.extensionCoordinator.setMenuBarEnabled($0, reference: reference) })
                )
                .labelsHidden()
            }
        }
        // Indented under its command: at the same inset the association is reading order.
        ForEach(command.preferences, id: \.name) { schema in
            ExtensionPreferenceRow(
                extensionName: installed.manifest.name, schema: schema, indent: Theme.Spacing.lg)
        }
        // The same predicate the scheduler runs on: an unparseable interval gets no toggle.
        if ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval),
            let schedule = command.intervalRaw
        {
            ExtensionRefreshRow(
                extensionName: installed.manifest.name, command: command, schedule: schedule,
                indent: Theme.Spacing.lg)
        }
    }
}

/// One `no-view` command's background refresh: Raycast's interval preference, stored locally.
private struct ExtensionRefreshRow: View {
    let extensionName: String
    let command: ExtensionCommand
    let schedule: String
    var indent: CGFloat = 0
    @Environment(AppCore.self) private var core

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }()

    var body: some View {
        let info = core.extensions.backgroundInfo(extension: extensionName, command: command.name)
        SettingsCardRow(title: "Background refresh", detail: detail(for: info), indent: indent) {
            Toggle(
                "",
                isOn: Binding(
                    get: { info.backgroundEnabled }, set: { setEnabled($0) })
            )
            .labelsHidden()
        }
    }

    private func detail(for info: ExtensionCommandMetadata) -> String {
        var detail = "Every \(schedule)."
        if let lastRun = info.lastRun {
            detail += " Last refresh \(Self.relative.localizedString(for: lastRun, relativeTo: Date()))."
        } else {
            detail += " Hasn't refreshed yet."
        }
        if let error = info.lastError {
            detail += " Last error: \(ExtensionRefreshPolicy.headline(error))."
        }
        return detail
    }

    private func setEnabled(_ enabled: Bool) {
        core.extensions.setBackgroundEnabled(enabled, extension: extensionName, command: command.name)
    }
}

/// Hides one extension's commands: an import can add hundreds, and the global switch is too blunt.
private struct ExtensionLauncherRow: View {
    let installed: InstalledExtension
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        let entries = installed.manifest.commands.map(installed.launcherEntry)
        let visibleCount = entries.count(where: visibility.isItemVisible)
        SettingsCardRow(title: "Show in launcher", detail: detail(visible: visibleCount, of: entries.count)) {
            // A closure, not `set: setVisible`: an actor-isolated method as a setter crashes IRGen.
            Toggle(
                "",
                isOn: Binding(
                    get: { visibleCount > 0 },
                    set: { visible in entries.forEach { visibility.setItemVisible(visible, for: $0) } })
            )
            .labelsHidden()
        }
    }

    private func detail(visible: Int, of total: Int) -> String? {
        switch visible {
        case 0: "Hidden. Shortcuts still work."
        case total: nil
        default: "\(visible) of \(total) commands."
        }
    }
}

/// The launcher icon, and the picker that replaces it.
private struct ExtensionIconRow: View {
    let installed: InstalledExtension
    @Environment(AppCore.self) private var core
    @State private var picking = false

    /// From the store, not the manager: picking publishes there, so both observe it.
    private var appearance: ExtensionAppearance? {
        core.extensions.appearances.appearance(for: installed.manifest.name)
    }

    var body: some View {
        SettingsCardRow(
            title: "Launcher icon",
            detail: appearance == nil ? nil : "Custom icon."
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

/// One scan of the local Raycast install, carried as the import panel's presentation item.
private struct ImportCandidates: Identifiable {
    let id = UUID()
    let entries: [RaycastImportCandidate]
}

/// Anything not already built starts selected, so the common case is one press.
private struct ExtensionImportPanel: View {
    let candidates: [RaycastImportCandidate]
    let onImport: ([InstalledExtension]) -> Void
    let onCancel: () -> Void
    @State private var chosen: Set<String> = []
    @State private var seeded = false
    @State private var filter = ""

    private var fresh: [RaycastImportCandidate] { candidates.filter { !$0.isInstalled } }

    /// Thirty-odd rows is past the point where scanning beats filtering.
    private var matching: [RaycastImportCandidate] {
        guard !filter.isEmpty else { return candidates }
        return candidates.filter {
            $0.installed.title.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ExtensionSettingsEditorHeader(title: "Import from Raycast", subtitle: subtitle)

            if candidates.count > 6 {
                SettingsFilterField(prompt: "Filter…", query: $filter)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matching) { candidate in
                        // AppKit aligns a checkbox to its label's first baseline.
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
            .frame(minHeight: 220, maxHeight: 360)

            HStack {
                // Reads against what is selected, so it is never a button that does nothing.
                Button(allChosen ? "Deselect All" : "Select All") {
                    chosen = allChosen ? [] : Set(candidates.map(\.installed.manifest.name))
                }
                .buttonStyle(
                    ExtensionSettingsEditorButtonStyle(role: .standard, fillsWidth: false)
                )
                .disabled(candidates.isEmpty)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Import \(chosen.isEmpty ? "" : "(\(chosen.count))")") {
                    onImport(
                        candidates.map(\.installed).filter { chosen.contains($0.manifest.name) })
                }
                .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .extensionSettingsEditorPanelSurface()
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

extension InstalledExtension {
    /// The entry `VisibilityStore` and `AliasStore` key on: only its id is read, never its row.
    fileprivate func launcherEntry(for command: ExtensionCommand) -> AppEntry {
        AppEntry(
            id: ExtensionCommandRef(extensionName: manifest.name, commandName: command.name).entryID,
            name: command.title, url: directory, bundleID: nil, kind: .extensionCommand)
    }
}

extension String {
    /// Sorts on the first letter: "(Basic) Bookmarks" otherwise leads on its bracket.
    fileprivate var sortKey: String {
        String(drop { !$0.isLetter && !$0.isNumber })
    }
}
