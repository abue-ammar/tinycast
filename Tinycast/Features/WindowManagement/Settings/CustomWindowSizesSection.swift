import SwiftUI

/// The custom-size library, inside the Window Management pane beside the commands it extends.
struct CustomWindowSizesSection: View {
    let onEdit: (CustomWindowSize?) -> Void

    @Environment(CustomWindowSizeStore.self) private var store
    @Environment(AppCore.self) private var core

    var body: some View {
        Section {
            ForEach(store.sizes) { size in
                CustomWindowSizeRow(
                    size: size,
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
        } footer: {
            Text("A custom size resizes and places the window you were last in, like any command.")
        }
    }

    private func delete(_ size: CustomWindowSize) {
        Task { await core.customWindowSizeCoordinator.deleteCustomWindowSize(id: size.id) }
    }
}

/// One size's shortcut, launcher checkbox and actions, shaped like the window-command row.
private struct CustomWindowSizeRow: View {
    let size: CustomWindowSize
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        SettingsRow(title: size.name, subtitle: size.summary) {
            Image(systemName: CustomWindowSize.sfSymbol)
        } trailing: {
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

            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Show in launcher")
                .accessibilityLabel("Show \(size.name) in launcher")
        }
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(AppEntry(size)) },
            set: { visibility.setItemVisible($0, for: AppEntry(size)) })
    }
}
