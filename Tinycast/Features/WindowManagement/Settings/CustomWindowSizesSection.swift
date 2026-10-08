import SwiftUI

/// The custom-size library, inside the Window Management pane beside the commands it extends.
struct CustomWindowSizesSection: View {
    let onEdit: (CustomWindowSize?) -> Void

    @Environment(CustomWindowSizeStore.self) private var store
    @Environment(CustomWindowSizeCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            ForEach(store.sizes) { size in
                CustomWindowSizeRow(
                    size: size,
                    showsInLauncher: settings.windowManagementShowInLauncher,
                    onEdit: { onEdit(size) },
                    onDelete: { delete(size) })
            }
            Button {
                onEdit(nil)
            } label: {
                SettingsRowTitle(.windowManagementCustomSizes, "New Custom Size")
            }
        } header: {
            SettingsSectionHeader(.windowManagementCustomSizes)
        }
    }

    private func delete(_ size: CustomWindowSize) {
        Task { await coordinator.deleteCustomWindowSize(id: size.id) }
    }
}

/// One size's alias, shortcut, launcher checkbox and actions, shaped like the window-command row.
private struct CustomWindowSizeRow: View {
    let size: CustomWindowSize
    let showsInLauncher: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        let entry = AppEntry(size)
        let isVisible = visibility.isItemVisible(entry)
        SettingsRow(title: size.name, subtitle: size.summary) {
            Image(systemName: CustomWindowSize.sfSymbol)
        } trailing: {
            AliasField(entry: entry)
                .settingsEnabled(showsInLauncher && isVisible)

            ShortcutRecorder(action: .customWindowSize(id: size.id))

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit")
            .accessibilityLabel("Edit \(size.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help("Delete")
            .accessibilityLabel("Delete \(size.name)")

            Toggle(
                "", isOn: Binding(get: { isVisible }, set: { visibility.setItemVisible($0, for: entry) })
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .launcherVisibilityHelp()
            .accessibilityLabel("Show \(size.name) in launcher")
        }
    }
}
