import SwiftUI

struct FeatureCommandsSection: View {
    let owner: SettingsTab
    let anchor: SettingsAnchor
    /// Commands the pane draws elsewhere; excluded here rather than listed there, so a command
    /// added to `ownedCommands` later still shows up without a second edit.
    var excluding: Set<CommandID> = []

    var body: some View {
        Section {
            ForEach(CommandCatalog.entries(ownedBy: owner)) { entry in
                if !excluding.contains(where: { $0.rawValue == entry.id }) {
                    FeatureCommandRow(entry: entry)
                }
            }
        } header: {
            SettingsSectionHeader(anchor)
        }
    }
}

struct FeatureCommandRow: View {
    let entry: AppEntry
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        SettingsRow(
            title: entry.name,
            labelOpacity: visibility.isItemVisible(entry) ? 1 : 0.45
        ) {
            AppIconView(app: entry)
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            AliasField(entry: entry)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            }
            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel("Show \(entry.name) in launcher")
        }
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }
}
