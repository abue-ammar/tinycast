import SwiftUI

struct FileSearchSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.fileSearchEnabled) {
                    SettingsRowTitle(.fileSearchFileSearch, "Enable File Search")
                    Text("Find files and folders through the system Spotlight index, only on demand.")
                }
            } header: {
                SettingsSectionHeader(.fileSearchFileSearch)
            }

            SearchFilesCommandSection()
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

/// Search Files has a binding of its own, so it carries a recorder as well as a checkbox.
private struct SearchFilesCommandSection: View {
    @Environment(VisibilityStore.self) private var visibility

    private let entry = CommandCatalog.entry(for: .searchFiles)

    var body: some View {
        Section {
            if let entry {
                SettingsRow(title: entry.name) {
                    Image(systemName: CommandID.searchFiles.sfSymbol)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    ShortcutRecorder(action: .command(.searchFiles))
                    Toggle("", isOn: visibilityBinding(entry))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Show \(entry.name) in launcher")
                }
            }
        } header: {
            SettingsSectionHeader(.fileSearchCommands)
        } footer: {
            Text("The shortcut works even when the command is hidden from the launcher.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func visibilityBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
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
                ScopeRow(scope: scope, isMissing: missing.contains(scope)) {
                    settings.fileSearchScopes.removeAll { $0 == scope }
                }
            }

            HStack(spacing: Theme.Spacing.lg) {
                Button("Add…", action: addScopes)
                    .help("Add a folder to search.")
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
                Your home folder expands to its visible folders and cloud drives, never to its Library. \
                An empty list searches nothing.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: settings.fileSearchScopes) { _, _ in refreshMissing() }
    }

    private func refreshMissing() {
        let fm = FileManager.default
        missing = Set(
            settings.fileSearchScopes.filter { scope in
                !fm.fileExists(atPath: FileSearchScope.expand(scope, homeDirectory: home).path)
            })
    }

    private func addScopes() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to include when searching for files."
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        settings.fileSearchScopes = FileSearchScope.normalize(
            settings.fileSearchScopes + panel.urls.map(\.path), homeDirectory: home)
    }
}

private struct ScopeRow: View {
    let scope: String
    let isMissing: Bool
    let onRemove: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                if isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("This location no longer exists.")
                }
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(scope)")
            }
        } label: {
            Label {
                Text(scope)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isMissing ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            } icon: {
                Image(systemName: "folder")
            }
        }
    }
}

private struct FileSearchIgnoreSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""

    var body: some View {
        Section {
            ForEach(FileSearchIgnoreList.defaults, id: \.self) { pattern in
                PatternRow(pattern: pattern, onRemove: nil)
            }
            ForEach(settings.fileSearchIgnorePatterns, id: \.self) { pattern in
                PatternRow(pattern: pattern) {
                    settings.fileSearchIgnorePatterns.removeAll { $0 == pattern }
                }
            }

            TextField("Add pattern…", text: $draft)
                .onSubmit(addPattern)
        } header: {
            SettingsSectionHeader(.fileSearchIgnorePatterns)
        } footer: {
            Text(
                """
                A pattern without a slash matches any file or folder name, like *.tmp or node_modules; \
                one with a slash matches the whole path, like **/[Cc]ache/**. The built-in patterns \
                always apply.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func addPattern() {
        let pattern = draft.trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !pattern.isEmpty,
            !FileSearchIgnoreList.defaults.contains(pattern),
            !settings.fileSearchIgnorePatterns.contains(pattern)
        else { return }
        settings.fileSearchIgnorePatterns.append(pattern)
    }
}

private struct PatternRow: View {
    let pattern: String
    /// Nil for a built-in rule, which has no remove affordance because it cannot be turned off.
    let onRemove: (() -> Void)?

    var body: some View {
        LabeledContent {
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(pattern)")
            }
        } label: {
            Text(pattern)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(onRemove == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }
}
