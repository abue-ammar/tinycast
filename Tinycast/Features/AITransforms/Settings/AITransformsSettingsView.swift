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
    /// Mirrors Keychain presence so the row can say plainly whether a key is saved.
    @State private var keyIsStored = false
    /// Model IDs the provider listed; empty until polled, which keeps the dropdown on Custom…
    /// for anyone who never asks for it.
    @State private var fetchedModels: [String] = []
    @State private var connectionNote: ConnectionNote?

    /// Inline progress/result line under the poll and test buttons: green when proven,
    /// red when the provider refused, neutral while in flight.
    private struct ConnectionNote: Equatable {
        let text: String
        let isGood: Bool?

        var tone: Color {
            switch isGood {
            case .some(true): .green
            case .some(false): .red
            case .none: .secondary
            }
        }
    }

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
                LabeledContent("Provider") {
                    Picker(selection: providerSelection) {
                        ForEach(AIProvider.catalog) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                        Text("Custom").tag(AIProvider.customID)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
                LabeledContent("Base URL") {
                    // `prompt:`, not the title argument: inside a Form the title renders as a
                    // second label beside the field. See SettingsFilterField.
                    TextField(
                        "", text: $settings.aiBaseURL, prompt: Text(AIClient.defaultBaseURL)
                    )
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: 340)
                }
                SettingsRow(
                    title: "API Key",
                    subtitle: keyIsStored
                        ? "A key is saved in your login Keychain." : "No key saved."
                ) {
                    HStack(spacing: Theme.Spacing.sm) {
                        SecureField("", text: $keyDraft, prompt: Text("New key"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 180)
                        Button("Save") { saveKey() }
                            .disabled(keyDraft.isEmpty)
                        if keyIsStored {
                            Button("Remove", role: .destructive) {
                                SecretStore.setSecret(nil, account: SecretStore.aiAPIKeyAccount)
                                keyDraft = ""
                                keyIsStored = false
                                fetchedModels = []
                            }
                        }
                    }
                }
                LabeledContent("Model") {
                    HStack(spacing: Theme.Spacing.sm) {
                        Picker(selection: modelSelection) {
                            Text("Custom…").tag(Self.customModelID)
                            ForEach(fetchedModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                        .disabled(fetchedModels.isEmpty)
                        if isCustomModel {
                            TextField("", text: $settings.aiModel, prompt: Text("model id"))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .frame(width: 170)
                        }
                    }
                }
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        refreshModels()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Fetch the models this provider serves")
                    Button("Test Connection") { testConnection() }
                    if let connectionNote {
                        Text(connectionNote.text)
                            .font(.caption)
                            .foregroundStyle(connectionNote.tone)
                            .lineLimit(2)
                    }
                }
            } footer: {
                Text(
                    "The key is stored in your login Keychain and never included in backups. "
                        + "Picking a provider fills the base URL; Custom takes any "
                        + "OpenAI-compatible root, ending before “/chat/completions”. "
                        + "The arrow polls the provider's model list; Test Connection sends a "
                        + "one-word completion to prove the whole chain."
                )
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
        .onAppear { keyIsStored = SecretStore.secret(account: SecretStore.aiAPIKeyAccount) != nil }
        .task {
            // One polite poll when the pane opens with everything configured; never a retry
            // loop, and only when there is something to poll with.
            if settings.aiTransformsEnabled, fetchedModels.isEmpty, storedKey() != nil {
                refreshModels()
            }
        }
        .formStyle(.grouped)
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

    /// Reads back which provider the base URL came from, so hand-edited URLs read as Custom;
    /// picking a provider writes its root into the field, where it stays editable.
    private var providerSelection: Binding<String> {
        Binding(
            get: {
                AIProvider.matching(baseURL: settings.aiBaseURL)?.id ?? AIProvider.customID
            },
            set: { selection in
                if let provider = AIProvider.catalog.first(where: { $0.id == selection }) {
                    settings.aiBaseURL = provider.baseURL
                }
            })
    }

    private func storedKey() -> String? {
        SecretStore.secret(account: SecretStore.aiAPIKeyAccount)
    }

    private func saveKey() {
        SecretStore.setSecret(
            keyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            account: SecretStore.aiAPIKeyAccount)
        keyDraft = ""
        keyIsStored = true
    }

    // MARK: Model list and connection test

    private static let customModelID = "custom"

    /// A model the provider listed is chosen in the dropdown; anything else (including a
    /// hand-typed ID) reads as Custom…, which is when the freeform field shows.
    private var isCustomModel: Bool { !fetchedModels.contains(settings.aiModel) }

    private var modelSelection: Binding<String> {
        Binding(
            get: { isCustomModel ? Self.customModelID : settings.aiModel },
            set: { selection in
                if selection != Self.customModelID {
                    settings.aiModel = selection
                    connectionNote = nil
                }
            })
    }

    private func refreshModels() {
        guard let key = storedKey(), !key.isEmpty else {
            connectionNote = ConnectionNote(text: "Save an API key first.", isGood: false)
            return
        }
        connectionNote = ConnectionNote(text: "Fetching models…", isGood: nil)
        Task {
            do {
                let models = try await AIClient.listModels(
                    baseURL: settings.aiBaseURL, apiKey: key)
                fetchedModels = models
                connectionNote = ConnectionNote(
                    text: models.isEmpty
                        ? "The provider listed no models — type one by hand."
                        : "\(models.count) models available.",
                    isGood: models.isEmpty ? false : true)
            } catch {
                fetchedModels = []
                connectionNote = ConnectionNote(text: error.localizedDescription, isGood: false)
            }
        }
    }

    private func testConnection() {
        guard let key = storedKey(), !key.isEmpty else {
            connectionNote = ConnectionNote(text: "Save an API key first.", isGood: false)
            return
        }
        guard !settings.aiModel.isEmpty else {
            connectionNote = ConnectionNote(text: "Set a model to test.", isGood: false)
            return
        }
        connectionNote = ConnectionNote(text: "Testing…", isGood: nil)
        let started = Date()
        Task {
            do {
                try await AIClient.testConnection(
                    baseURL: settings.aiBaseURL, apiKey: key, model: settings.aiModel)
                let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                connectionNote = ConnectionNote(
                    text: "Working — responded in \(seconds)s.", isGood: true)
            } catch {
                connectionNote = ConnectionNote(text: error.localizedDescription, isGood: false)
            }
        }
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
