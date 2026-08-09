import AppKit
import SwiftUI

/// Searchable list of installed apps, drawn from the launcher's own index.
struct AppPickerPopover: View {
    /// Bundle IDs to leave out — the ones already chosen.
    var excluded: Set<String> = []
    /// Shown above the list when the caller can also clear its choice.
    var clearTitle: String?
    /// Nil means the caller's `clearTitle` row was tapped.
    let onSelect: (String?) -> Void

    @Environment(AppIndex.self) private var appIndex
    @State private var query = ""

    private var candidates: [AppEntry] {
        (query.isEmpty ? appIndex.apps : appIndex.matches(query))
            .filter { $0.kind == .application }
            .filter { $0.bundleID.map { !excluded.contains($0) } ?? false }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(Theme.Spacing.md)
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    if let clearTitle, query.isEmpty {
                        row(title: clearTitle, icon: nil) { onSelect(nil) }
                    }
                    ForEach(candidates) { app in
                        row(title: app.name, icon: app.icon) {
                            if let id = app.bundleID { onSelect(id) }
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
        .frame(width: 220, height: 240)
    }

    private func row(title: String, icon: NSImage?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(width: 20, height: 20)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bundle ID → something showable: the index, then LaunchServices, then a placeholder.
@MainActor
enum AppPresentation {
    static func resolve(bundleID: String, in appIndex: AppIndex) -> (name: String, icon: NSImage) {
        if let app = appIndex.apps.first(where: { $0.bundleID == bundleID }) {
            return (app.name, app.icon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return (url.deletingPathExtension().lastPathComponent, IconCache.icon(forFile: url.path))
        }
        return (bundleID, NSWorkspace.shared.icon(for: .applicationBundle))
    }
}
