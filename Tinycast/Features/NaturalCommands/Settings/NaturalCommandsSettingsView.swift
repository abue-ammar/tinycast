import SwiftUI

/// Settings for the opt-in TypeSafe fallback; it never shares AI Chat's provider routing.
struct NaturalCommandsSettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(NaturalCommandSettingsStore.self) private var connection
    @State private var editorPresented = false

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            Section {
                Toggle(isOn: $appSettings.naturalCommandsEnabled) {
                    SettingsRowTitle(.naturalCommandsNaturalCommands, "Enable natural-language commands")
                    Text("Suggests built-in commands when local search finds nothing.")
                }
                SettingsRow(
                    title: "TypeSafe API key", subtitle: connectionSubtitle,
                    anchor: .naturalCommandsConnection
                ) {
                    Button("Manage…") { editorPresented = true }
                }
            } header: {
                SettingsSectionHeader(.naturalCommandsNaturalCommands)
            } footer: {
                Text("TypeSafe receives your search and built-in commands. Confirm before running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.naturalCommands)
        .settingsEditorPanel(isPresented: $editorPresented) {
            NaturalCommandsKeyEditor(onDismiss: { editorPresented = false })
        }
    }

    private var connectionSubtitle: String {
        connection.hasAPIKey ? "Saved in Keychain" : "Required to offer the fallback"
    }
}

private struct NaturalCommandsKeyEditor: View {
    @Environment(NaturalCommandSettingsStore.self) private var connection
    let onDismiss: () -> Void

    @State private var key = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "TypeSafe API Key",
                subtitle: "The key stays in your login Keychain and is used only for natural commands."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            Form {
                Section {
                    SettingsEditorField("API Key", labelFont: .callout.weight(.medium)) {
                        RevealableSecureField(
                            title: "API Key", text: $key,
                            prompt: Text(
                                connection.hasAPIKey ? "Leave blank to keep saved key" : "Paste API key")
                        )
                        .settingsEditorTextField()
                    }
                    if connection.hasAPIKey {
                        Label("A key is already stored in Keychain", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Remove Saved Key", role: .destructive, action: remove)
                    }
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel", action: onDismiss)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 500)
        .settingsEditorPanelSurface()
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || connection.hasAPIKey else {
            error = "Enter a TypeSafe API key."
            return
        }
        guard !trimmed.isEmpty else {
            onDismiss()
            return
        }
        do {
            try connection.saveAPIKey(trimmed)
            onDismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try connection.removeAPIKey()
            key = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
