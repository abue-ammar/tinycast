import SwiftUI

struct FeatureCommandsSection: View {
    let owner: SettingsTab
    let anchor: SettingsAnchor
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        Section {
            ForEach(CommandCatalog.entries(ownedBy: owner)) { entry in
                SettingsRow(title: entry.name) {
                    AppIconView(app: entry)
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                } trailing: {
                    AliasField(entry: entry)
                    if let action = entry.hotKeyAction {
                        ShortcutRecorder(action: action)
                    }
                    Toggle("", isOn: visibilityBinding(entry))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Show \(entry.name) in launcher")
                }
            }
        } header: {
            SettingsSectionHeader(anchor)
        } footer: {
            Text("A shortcut works even when its command is hidden from the launcher.")
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
