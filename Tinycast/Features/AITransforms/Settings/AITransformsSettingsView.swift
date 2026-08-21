import SwiftUI

/// Provider config plus the preset library: one pane, gated behind the feature switch.
struct AITransformsSettingsView: View {
    @Environment(AITransformStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var editor: EditorTarget?
    @State private var pendingDeletion: AITransform?
    /// Stays empty until the user types; the stored key itself never round-trips through UI.
    @State private var keyDraft = ""

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherItemsSection(
                kind: .aiTransform,
                header: "AI Transforms",
                searchPrompt: "Search AI transforms…")

            FeatureSwitchSection(
                header: "AI Transforms",
                enableTitle: "Enable AI transforms",
                enableSubtitle:
                    "Selected text is sent to the configured provider, and the result replaces it "
                    + "in place.",
                launcherSubtitle: "Find your transforms in launcher search.",
                isEnabled: $settings.aiTransformsEnabled,
                showsInLauncher: $settings.aiTransformsShowInLauncher)

            Section {
                LabeledContent("Base URL") {
                    TextField(AIClient.defaultBaseURL, text: $settings.aiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                LabeledContent("Model") {
                    TextField(AIClient.defaultModel, text: $settings.aiModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                LabeledContent("API Key") {
                    SecureField(hasStoredKey ? "Saved in Keychain" : "sk-…", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        // Write-through on every edit: the pane resigns focus on outside clicks,
                        // so waiting for Return could silently drop a typed key.
                        .onChange(of: keyDraft) { _, draft in
                            SecretStore.setSecret(
                                draft.isEmpty ? nil : draft, account: SecretStore.aiAPIKeyAccount)
                        }
                }
            } footer: {
                Text("The key is stored in your login Keychain and never included in backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.aiTransformsEnabled)

            Section {
                if store.transforms.isEmpty {
                    Text("Add one to make it searchable from the launcher.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTransforms) { transform in
                        AITransformSettingsRow(
                            transform: transform,
                            onEdit: { editor = EditorTarget(transform: transform) },
                            onDelete: { pendingDeletion = transform })
                    }
                }
                Button("Add AI Transform…") { editor = EditorTarget(transform: nil) }
            } footer: {
                Text("Name it, write the instruction, and give it a shortcut if you want one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.aiTransformsEnabled)
        }
        .formStyle(.grouped)
        .releasesFocusOnOutsideClick()
        .sheet(item: $editor) { target in
            AITransformEditorSheet(transform: target.transform)
        }
        .alert(item: $pendingDeletion) { transform in
            Alert(
                title: Text("Delete “\(transform.name)”?"),
                message: Text("Its global shortcut and launcher references will also be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    core.aiTransformCoordinator.deleteTransform(id: transform.id)
                },
                secondaryButton: .cancel())
        }
    }

    private var hasStoredKey: Bool {
        SecretStore.secret(account: SecretStore.aiAPIKeyAccount) != nil
    }

    private var sortedTransforms: [AITransform] {
        store.transforms.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct EditorTarget: Identifiable {
    let id = UUID()
    let transform: AITransform?
}

private struct AITransformSettingsRow: View {
    let transform: AITransform
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: transform.name, subtitle: transform.prompt) {
            Image(systemName: AITransform.sfSymbol)
        } trailing: {
            ShortcutRecorder(action: .aiTransform(id: transform.id))

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Transform")
            .accessibilityLabel("Edit \(transform.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Transform")
            .accessibilityLabel("Delete \(transform.name)")
        }
    }
}
