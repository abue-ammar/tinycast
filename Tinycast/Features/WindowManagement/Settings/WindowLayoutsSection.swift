import SwiftUI

/// The layout library, inside the Window Management pane: layouts belong to window management.
struct WindowLayoutsSection: View {
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
                Text("Find your layouts in launcher search, beside the window commands.")
            }

            if store.layouts.count > Self.filterThreshold {
                SettingsFilterField(prompt: "Search layouts…", query: $query)
            }

            if results.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { layout in
                    WindowLayoutSettingsRow(layout: layout, onDelete: { onDelete(layout) })
                }
            }

            Button {
                core.windowLayoutCoordinator.editWindowLayout(nil)
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
        } footer: {
            Text("A layout puts named apps at fixed sizes on chosen displays, in one pass.")
        }
    }

    private var results: [WindowLayout] {
        guard !query.isEmpty else { return store.layouts }
        return store.layouts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var emptyMessage: String {
        store.layouts.isEmpty
            ? "Save an arrangement once, then put every window back with one shortcut."
            : "No layout matches “\(query)”."
    }
}

/// One layout's shortcut, launcher checkbox and actions, shaped like the window-command row.
private struct WindowLayoutSettingsRow: View {
    let layout: WindowLayout
    let onDelete: () -> Void

    @Environment(AppCore.self) private var core
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        SettingsRow(title: layout.name, subtitle: layout.summary) {
            SymbolImage(name: layout.symbol, size: 13)
        } trailing: {
            ShortcutRecorder(action: .windowLayout(id: layout.id))

            Button {
                core.windowLayoutCoordinator.runWindowLayout(id: layout.id)
            } label: {
                Image(systemName: "play")
            }
            .buttonStyle(.plain)
            .help("Run this layout")
            .accessibilityLabel("Run \(layout.name)")

            Button {
                core.windowLayoutCoordinator.editWindowLayout(layout)
            } label: {
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

            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Show in launcher")
                .accessibilityLabel("Show \(layout.name) in launcher")
        }
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(AppEntry(layout)) },
            set: { visibility.setItemVisible($0, for: AppEntry(layout)) })
    }
}
