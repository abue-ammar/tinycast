import SwiftUI
import UniformTypeIdentifiers

/// The editable list of folders (and individual `.app` bundles) the launcher indexes.
struct SearchScopesSection: View {
    @Environment(AppSettings.self) private var settings
    /// Recomputed only on change: a `fileExists` per row is too much per body render.
    @State private var missing: Set<String> = []

    private var isDefault: Bool { settings.searchScopes == SearchScopes.defaults }

    var body: some View {
        Section {
            ForEach(settings.searchScopes, id: \.self) { scope in
                ScopeRow(scope: scope, isMissing: missing.contains(scope)) {
                    settings.searchScopes.removeAll { $0 == scope }
                }
            }

            HStack(spacing: Theme.Spacing.lg) {
                Button("Add…", action: addScopes)
                    .help("Add a folder or application to search.")
                if !isDefault {
                    Button("Restore Defaults") { settings.searchScopes = SearchScopes.defaults }
                }
            }
        } header: {
            SettingsSectionHeader(.applicationsSearchScopes)
        } footer: {
            Text("Folders searched when indexing applications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: settings.searchScopes) { _, _ in refreshMissing() }
    }

    private func refreshMissing() {
        let fm = FileManager.default
        missing = Set(
            settings.searchScopes.filter { !fm.fileExists(atPath: SearchScopes.expand($0)) })
    }

    private func addScopes() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        // Otherwise an .app is navigated into rather than selected.
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders or applications to include in the launcher."
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        settings.searchScopes = SearchScopes.normalize(
            settings.searchScopes + panel.urls.map(\.path))
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
                Image(systemName: (scope as NSString).pathExtension == "app" ? "app" : "folder")
            }
        }
    }
}
