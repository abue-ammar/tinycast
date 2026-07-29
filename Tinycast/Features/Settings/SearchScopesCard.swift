import SwiftUI
import UniformTypeIdentifiers

/// The editable list of folders (and individual `.app` bundles) the launcher indexes.
struct SearchScopesCard: View {
    @ObservedObject private var settings = AppCore.shared.settings
    /// Recomputed only when the list changes — a `fileExists` per row is cheap, but not cheap enough to run on every body render.
    @State private var missing: Set<String> = []

    private var isDefault: Bool { settings.searchScopes == SearchScopes.defaults }

    var body: some View {
        SettingsCard(header: "Search Scopes") {
            ForEach(settings.searchScopes, id: \.self) { scope in
                ScopeRow(scope: scope, isMissing: missing.contains(scope)) {
                    settings.searchScopes.removeAll { $0 == scope }
                }
                SettingsDivider()
            }

            HStack(spacing: Theme.Spacing.lg) {
                Text("Folders searched when indexing applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.xl)
                if !isDefault {
                    Button("Restore Defaults") { settings.searchScopes = SearchScopes.defaults }
                        .controlSize(.small)
                }
                Button(action: addScopes) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Add a folder or application to search.")
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
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
        panel.prompt = String(localized: "Add")
        panel.message = String(
            localized: "Choose folders or applications to include in the launcher.")
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
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: (scope as NSString).pathExtension == "app" ? "app" : "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon)
            Text(scope)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isMissing ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            Spacer(minLength: Theme.Spacing.xl)
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
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}
