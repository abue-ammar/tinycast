import SwiftUI

struct ChatPresetsSection: View {
    @Environment(AIChatCoordinator.self) private var coordinator
    @Environment(ChatPresetStore.self) private var store
    @State private var editing: ChatPresetEditRequest?
    @State private var pendingDeletion: ChatPreset?

    private static let iconSize: CGFloat = 14

    var body: some View {
        Section {
            ForEach(store.presets) { preset in
                SettingsRow(title: preset.name, subtitle: modelTitle(of: preset)) {
                    SymbolImage(name: preset.symbol, size: Self.iconSize)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    editButton(for: preset)
                    deleteButton(for: preset)
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
        .confirmationDialog(
            pendingDeletion.map { String(localized: "Delete “\($0.name)”?") } ?? "",
            isPresented: deletionBinding, presenting: pendingDeletion
        ) { preset in
            Button("Delete", role: .destructive) {
                coordinator.deleteChatPreset(id: preset.id)
            }
        } message: { _ in
            Text("Chats it started keep their instructions.")
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
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

    private func deleteButton(for preset: ChatPreset) -> some View {
        Button {
            pendingDeletion = preset
        } label: {
            SymbolImage(name: "trash", size: Self.iconSize)
                .foregroundStyle(Theme.Colors.destructive)
        }
        .buttonStyle(.plain)
        .help("Delete \(preset.name)")
        .accessibilityLabel("Delete \(preset.name)")
    }

    private func modelTitle(of preset: ChatPreset) -> String? {
        guard let model = preset.model else { return nil }
        return coordinator.modelTitle(of: model, among: coordinator.modelOptions)
    }
}
