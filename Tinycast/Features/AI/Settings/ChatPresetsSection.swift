import SwiftUI

/// Each preset is also a launcher row, so its alias, shortcut and visibility live on its own row.
struct ChatPresetsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(ChatPresetStore.self) private var store
    @Environment(VisibilityStore.self) private var visibility
    @State private var editing: ChatPresetEditRequest?

    private static let iconSize: CGFloat = 14

    var body: some View {
        Section {
            ForEach(store.presets) { preset in
                SettingsRow(title: preset.name, subtitle: modelTitle(of: preset)) {
                    SymbolImage(name: preset.symbol, size: Self.iconSize)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    editButton(for: preset)
                    AliasField(key: preset.entryID, name: preset.name)
                    ShortcutRecorder(action: .chatPreset(id: preset.id), isQuiet: true)
                    Toggle("", isOn: launcherBinding(AppEntry(preset)))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .launcherVisibilityHelp()
                        .accessibilityLabel("Show \(preset.name) in launcher")
                }
            }
            Button {
                editing = ChatPresetEditRequest(preset: nil)
            } label: {
                SettingsRowTitle(.aiChatPresets, "Add Chat Preset")
            }
        } header: {
            SettingsSectionHeader(.aiChatPresets)
        } footer: {
            Text("A preset's instructions replace the system prompt in the chats it starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsEditorPanel(item: $editing) { request in
            ChatPresetEditorPanel(request: request)
        }
    }

    private func editButton(for preset: ChatPreset) -> some View {
        Button {
            editing = ChatPresetEditRequest(preset: preset)
        } label: {
            SymbolImage(name: "pencil", size: Self.iconSize)
        }
        .buttonStyle(.plain)
        .help("Edit \(preset.name)")
        .accessibilityLabel("Edit \(preset.name)")
    }

    private func modelTitle(of preset: ChatPreset) -> String? {
        guard let model = preset.model else { return nil }
        let coordinator = core.aiChatCoordinator
        return coordinator.modelTitle(of: model, among: coordinator.modelOptions)
    }

    private func launcherBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }
}
