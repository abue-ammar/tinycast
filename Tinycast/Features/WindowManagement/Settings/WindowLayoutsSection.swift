import SwiftUI

/// The layout library, inside the Window Management pane: layouts belong to window management.
struct WindowLayoutsSection: View {
    let onEdit: (WindowLayout?) -> Void
    let onDelete: (WindowLayout) -> Void

    @Environment(WindowLayoutStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    /// Below this a filter row is noise: a layout library is a handful of rows, not four hundred.
    private static let filterThreshold = 6

    var body: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.windowLayoutsShowInLauncher) {
                SettingsRowTitle(.windowManagementLayouts, "Show layouts in launcher")
            }

            if store.layouts.count > Self.filterThreshold {
                SettingsFilterField(prompt: "Search layouts…", query: $query)
            }

            if results.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { layout in
                    WindowLayoutSettingsRow(
                        layout: layout,
                        showsInLauncher: settings.windowLayoutsShowInLauncher,
                        onEdit: { onEdit(layout) },
                        onDelete: { onDelete(layout) })
                }
            }

            Button {
                onEdit(nil)
            } label: {
                SettingsRowTitle(.windowManagementLayouts, "New Layout")
            }
            Button {
                core.windowLayoutCoordinator.captureWindowLayout()
            } label: {
                SettingsRowTitle(.windowManagementLayouts, "Create Layout from Current Windows")
            }
        } header: {
            SettingsSectionHeader(.windowManagementLayouts)
        }
    }

    private var results: [WindowLayout] {
        guard !query.isEmpty else { return store.layouts }
        return store.layouts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var emptyMessage: String {
        store.layouts.isEmpty
            ? "Save an arrangement, then restore it with one shortcut."
            : "No layout matches “\(query)”."
    }
}

/// One layout's alias, shortcut, launcher checkbox and actions, shaped like the window-command row.
private struct WindowLayoutSettingsRow: View {
    let layout: WindowLayout
    let showsInLauncher: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(AppCore.self) private var core
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        let entry = AppEntry(layout)
        let isVisible = visibility.isItemVisible(entry)
        SettingsRow(title: layout.name, subtitle: layout.summary) {
            SymbolImage(name: layout.symbol, size: 13)
        } trailing: {
            AliasField(entry: entry)
                .settingsEnabled(showsInLauncher && isVisible)

            ShortcutRecorder(action: .windowLayout(id: layout.id))

            Button {
                core.windowLayoutCoordinator.runWindowLayout(id: layout.id)
            } label: {
                Image(systemName: "play")
            }
            .buttonStyle(.plain)
            .help("Run this layout")
            .accessibilityLabel("Run \(layout.name)")

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit")
            .accessibilityLabel("Edit \(layout.name)")

            Button {
                core.windowLayoutCoordinator.duplicateWindowLayout(id: layout.id)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.plain)
            .help("Duplicate")
            .accessibilityLabel("Duplicate \(layout.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help("Delete")
            .accessibilityLabel("Delete \(layout.name)")

            Toggle(
                "", isOn: Binding(get: { isVisible }, set: { visibility.setItemVisible($0, for: entry) })
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .launcherVisibilityHelp()
            .accessibilityLabel("Show \(layout.name) in launcher")
        }
    }
}
