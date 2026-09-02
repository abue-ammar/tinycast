import SwiftUI

/// AI Chat's own row: a shortcut of its own, and a checkbox for its place in launcher search.
struct AICommandSection: View {
    @Environment(VisibilityStore.self) private var visibility

    private let entry = CommandCatalog.entry(for: .aiChat)

    var body: some View {
        Section {
            if let entry {
                SettingsRow(title: entry.name) {
                    Image(systemName: CommandID.aiChat.sfSymbol)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    ShortcutRecorder(action: .command(.aiChat))
                    Toggle("", isOn: visibilityBinding(entry))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Show \(entry.name) in launcher")
                }
            }
        } header: {
            SettingsSectionHeader(.aiCommands)
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
