import SwiftUI

/// Settings › Extensions: the master switch, what Raycast's API does and doesn't reach here, and one
/// row per installed extension. Configuring one opens a sheet, the way a custom command or a snippet
/// does — an extension carries preferences, several commands and their shortcuts, which is more than
/// a settings row can hold.
struct ExtensionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var editor: EditorTarget?
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
        .onChange(of: settings.extensionsShowInLauncher) {
            core.extensionCoordinator.applyExtensionsLauncherPresence()
        }
        .sheet(item: $editor) { target in
            ExtensionEditorSheet(installed: target.installed)
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
            guard let name = note.object as? String,
                let installed = core.extensions.extensionNamed(name)
            else { return }
            editor = EditorTarget(installed: installed)
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

    private var library: some View {
        Section {
            if core.extensions.installed.isEmpty {
                Text("Browse for one, or import what Raycast has already built.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(core.extensions.installed) { installed in
                    ExtensionSettingsRow(
                        installed: installed,
                        onConfigure: { editor = EditorTarget(installed: installed) },
                        onUninstall: { core.extensionCoordinator.confirmUninstall(installed) })
                }
            }
            Button("Browse Extensions…") { browsingStore = true }
            Button("Import from Raycast…", action: openImport)
                .disabled(!raycastAvailable)
            Button("Add from Folder…", action: addFolder)
        } header: {
            Text(
                core.extensions.installed.isEmpty
                    ? "Installed" : "Installed (\(core.extensions.installed.count))")
        } footer: {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(
                    "Configure an extension to set its preferences and give its commands shortcuts."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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

/// One installed extension, shaped like every other editable row in Settings: icon, name, what it
/// holds, then configure and remove.
private struct ExtensionSettingsRow: View {
    let installed: InstalledExtension
    let onConfigure: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        SettingsRow(title: installed.title, subtitle: summary) {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon)
        } trailing: {
            Button(action: onConfigure) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Configure Extension")
            .accessibilityLabel("Configure \(installed.title)")

            Button(action: onUninstall) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Uninstall Extension")
            .accessibilityLabel("Uninstall \(installed.title)")
        }
    }

    private var summary: String {
        let count = installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        let author = installed.manifest.author
        return author.isEmpty ? commands : "\(commands) · \(author)"
    }
}

/// The extension the editor sheet is open on.
private struct EditorTarget: Identifiable {
    let id = UUID()
    let installed: InstalledExtension
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
