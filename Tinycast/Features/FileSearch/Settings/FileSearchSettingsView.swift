import Combine
import SwiftUI

struct FileSearchSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .fileSearchFileSearch,
                enableTitle: "Enable File Search",
                enableSubtitle: "Indexes your disk for instant results. Needs Full Disk Access.",
                isEnabled: $settings.fileSearchEnabled,
                showsInLauncher: $settings.fileSearchShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            FileSearchAccessSection()
            FileSearchIndexSection()
                .settingsEnabled(settings.fileSearchEnabled)
            FeatureCommandsSection(owner: .fileSearch, anchor: .fileSearchCommands)
                .settingsEnabled(settings.fileSearchEnabled)
            FileSearchScopesSection()
                .settingsEnabled(settings.fileSearchEnabled)
            FileSearchIgnoreSection()
                .settingsEnabled(settings.fileSearchEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.fileSearch)
    }
}

private struct FileSearchAccessSection: View {
    @Environment(AppCore.self) private var core
    @State private var granted = Permissions.hasFullDiskAccess()
    /// Nothing announces a grant made in System Settings, so the pane asks while it is open.
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                        Text(granted ? "Granted" : "Required")
                    }
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    Button(granted ? "Open…" : "Open Privacy Settings…") {
                        Permissions.openFullDiskAccessSettings()
                    }
                    .help("Opens Privacy & Security › Full Disk Access.")
                }
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.fileSearchFullDiskAccess, "Full Disk Access")
                    Text(granted ? "Tinycast can index every folder." : "File Search can’t index without it.")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSectionHeader(.fileSearchFullDiskAccess)
        } footer: {
            if !granted {
                Text(
                    """
                    File Search reads your disk directly to build a private index on this Mac. \
                    In System Settings › Privacy & Security › Full Disk Access, turn on \
                    Tinycast. If it isn’t listed, click + and choose Tinycast from \
                    Applications. If access still shows as required, quit and reopen Tinycast.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func refresh() {
        let now = Permissions.hasFullDiskAccess()
        guard now != granted else { return }
        granted = now
        core.fileIndexer.refreshAccess()
    }
}

private struct FileSearchIndexSection: View {
    @Environment(AppCore.self) private var core

    private var indexer: FileIndexer { core.fileIndexer }

    var body: some View {
        Section {
            LabeledContent {
                Button("Rebuild Index") { core.fileSearchCoordinator.rebuildIndex() }
                    .disabled(!canRebuild)
                    .help("Crawls every scope again from scratch.")
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.fileSearchIndex, "Indexed Items")
                    summary
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSectionHeader(.fileSearchIndex)
        } footer: {
            Text(
                """
                Built once, then kept current as files change. Indexing uses extra memory only \
                while it runs.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var canRebuild: Bool {
        switch indexer.status {
        case .ready, .failed: return true
        case .off, .needsAccess, .building: return false
        }
    }

    @ViewBuilder
    private var summary: some View {
        switch indexer.status {
        case .off:
            Text("Not indexed")
        case .needsAccess:
            Text("Waiting for Full Disk Access")
        case .building(let items):
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView().controlSize(.mini)
                Text("Indexing… \(items.formatted()) items")
                    .monospacedDigit()
            }
        case .ready(let items, let builtAt):
            Text("\(items.formatted()) items · Built \(builtAt, format: .relative(presentation: .named))")
                .monospacedDigit()
        case .failed:
            Text("The last build failed")
        }
    }
}

private struct FileSearchScopesSection: View {
    @Environment(AppSettings.self) private var settings
    /// Recomputed only on change: a `fileExists` per row is too much per body render.
    @State private var missing: Set<String> = []

    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var isDefault: Bool { settings.fileSearchScopes == FileSearchScope.defaultScopes }

    var body: some View {
        Section {
            ForEach(settings.fileSearchScopes, id: \.self) { scope in
                SettingsScopeRow(
                    scope: title(for: scope),
                    path: FileSearchScope.expand(scope, homeDirectory: home).path,
                    isMissing: missing.contains(scope)
                ) {
                    settings.fileSearchScopes.removeAll { $0 == scope }
                }
            }

            HStack(spacing: Theme.Spacing.lg) {
                Button("Add…", action: addScopes)
                    .help("Add a folder to index and search.")
                if !isDefault {
                    Button("Restore Defaults") {
                        settings.fileSearchScopes = FileSearchScope.defaultScopes
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.fileSearchSearchScopes)
        } footer: {
            Text(
                """
                Only these folders and their contents are indexed. Subfolders already included do not \
                need to be added separately.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: settings.fileSearchScopes) { _, _ in refreshMissing() }
    }

    private func title(for scope: String) -> String {
        guard scope == "/" else { return scope }
        let name = try? URL(filePath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey])
            .volumeLocalizedName
        return name ?? "Macintosh HD"
    }

    private func refreshMissing() {
        let fm = FileManager.default
        missing = Set(
            settings.fileSearchScopes.filter { scope in
                !fm.fileExists(atPath: FileSearchScope.expand(scope, homeDirectory: home).path)
            })
    }

    private func addScopes() {
        guard let urls = chooseFolders(message: String(localized: "Choose folders to index and search."))
        else { return }
        settings.fileSearchScopes = FileSearchScope.normalize(
            settings.fileSearchScopes + urls.map(\.path), homeDirectory: home)
    }
}

private struct FileSearchIgnoreSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""

    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var patterns: [String] { settings.fileSearchEffectiveIgnorePatterns }

    var body: some View {
        Section {
            ForEach(patterns, id: \.self) { pattern in
                PatternRow(pattern: pattern) { remove(pattern) }
            }

            // Titled, a grouped form squeezes the field into a sliver too narrow to click.
            HStack(spacing: Theme.Spacing.lg) {
                TextField("Pattern", text: $draft, prompt: Text("node_modules, *.tmp or ~/Movies"))
                    .labelsHidden()
                    .onSubmit { add(draft) }
                Button("Add") { add(draft) }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Add Folder…", action: addFolders)
                    .help("Skip a folder and everything in it.")
                if patterns != FileSearchIgnoreList.defaults {
                    Button("Restore Defaults", action: restoreDefaults)
                }
            }
        } header: {
            SettingsSectionHeader(.fileSearchIgnorePatterns)
        } footer: {
            Text(
                """
                Matching folders are skipped while indexing. A name like node_modules or *.tmp \
                matches anywhere; a path like ~/Movies skips that folder.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func addFolders() {
        guard
            let urls = chooseFolders(
                message: String(localized: "Choose folders to leave out of the index."))
        else { return }
        for url in urls {
            add(FileSearchScope.abbreviate(url.standardizedFileURL.path, homeDirectory: home))
        }
    }

    private func add(_ text: String) {
        let pattern = text.trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !pattern.isEmpty, !patterns.contains(pattern) else { return }
        if FileSearchIgnoreList.defaults.contains(pattern) {
            settings.fileSearchRemovedDefaultPatterns.removeAll { $0 == pattern }
        } else {
            settings.fileSearchIgnorePatterns.append(pattern)
        }
    }

    private func remove(_ pattern: String) {
        if FileSearchIgnoreList.defaults.contains(pattern) {
            settings.fileSearchRemovedDefaultPatterns.append(pattern)
        } else {
            settings.fileSearchIgnorePatterns.removeAll { $0 == pattern }
        }
    }

    private func restoreDefaults() {
        settings.fileSearchIgnorePatterns = []
        settings.fileSearchRemovedDefaultPatterns = []
    }
}

@MainActor
private func chooseFolders(message: String) -> [URL]? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = String(localized: "Add")
    panel.message = message
    // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
    NSApp.activate()
    guard panel.runModal() == .OK else { return nil }
    return panel.urls
}

private struct PatternRow: View {
    let pattern: String
    let onRemove: () -> Void

    var body: some View {
        LabeledContent {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(pattern)")
        } label: {
            Text(pattern)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
