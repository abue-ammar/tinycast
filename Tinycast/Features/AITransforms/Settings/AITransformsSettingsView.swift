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
    @State private var forceCustomModel = false
    @State private var isFetchingModels = false
    @State private var isTestingConnection = false
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
                Picker(selection: $settings.aiExecutionMode) {
                    ForEach(AIExecutionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Text("Activation Mode")
                    Text(settings.aiExecutionMode.subtitle)
                }
            }
            .settingsEnabled(settings.aiTransformsEnabled)
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Provider")
                        Text("Select a service or choose Custom for other endpoints.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker(selection: providerSelection) {
                        ForEach(AIProvider.catalog) { provider in
                            Label {
                                Text(provider.name)
                            } icon: {
                                if let iconName = provider.iconName {
                                    Image(iconName)
                                } else {
                                    Image(systemName: provider.symbolFallback)
                                }
                            }
                            .tag(provider.id)
                        }
                        Divider()
                        Label("Custom", systemImage: "slider.horizontal.3").tag(AIProvider.customID)
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 160)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Base URL")
                        Text("OpenAI-compatible root ending before /chat/completions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LeftAlignedTextField(
                        prompt: AIClient.defaultBaseURL,
                        text: $settings.aiBaseURL
                    )
                    .frame(height: 22)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("API Key")
                            Text(keyIsStored ? "Saved securely." : "Required for cloud providers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !keyDraft.isEmpty {
                            Button("Save") { saveKey() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        } else if keyIsStored {
                            Button("Clear", role: .destructive) {
                                SecretStore.setSecret(nil, account: SecretStore.aiAPIKeyAccount)
                                keyDraft = ""
                                keyIsStored = false
                                fetchedModels = []
                            }
                            .controlSize(.small)
                        }
                    }

                    LeftAlignedTextField(
                        prompt: keyIsStored ? "Replace saved key" : "sk-…",
                        text: $keyDraft,
                        isSecure: true
                    )
                    .frame(height: 22)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("Default Model")
                            Text("Used when a transform has no model override.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: Theme.Spacing.sm) {
                            Picker(selection: modelSelection) {
                                Text("Custom…").tag(Self.customModelID)
                                if !fetchedModels.isEmpty {
                                    Divider()
                                    ForEach(fetchedModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                            } label: {
                                EmptyView()
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 160)

                            Button {
                                refreshModels()
                            } label: {
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .help("Fetch models from provider")
                            .disabled(isFetchingModels)
                        }
                    }

                    LeftAlignedTextField(
                        prompt: "Model ID (e.g. gemini-2.5-flash)",
                        text: $settings.aiModel,
                        isEnabled: isCustomModel || fetchedModels.isEmpty
                    )
                    .frame(height: 22)
                }

                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Connection")
                        Text("Verify your API key, base URL, and model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: Theme.Spacing.md) {
                        if let connectionNote {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(
                                    systemName: connectionNote.isGood == true
                                        ? "checkmark.circle.fill"
                                        : (connectionNote.isGood == false
                                            ? "exclamationmark.triangle.fill" : "circle.dotted")
                                )
                                Text(connectionNote.text)
                                    .lineLimit(2)
                            }
                            .font(.caption)
                            .foregroundStyle(connectionNote.tone)
                        }

                        Button {
                            testConnection()
                        } label: {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTestingConnection || settings.aiModel.isEmpty)
                    }
                }
            } footer: {
                Text(
                    "The API key is stored securely with private permissions and never included in backups. "
                        + "The refresh button polls the provider's /models endpoint to populate the dropdown."
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
    /// hand-typed ID) reads as Custom…, which is when the freeform field is enabled.
    private var isCustomModel: Bool {
        forceCustomModel || !fetchedModels.contains(settings.aiModel)
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { isCustomModel ? Self.customModelID : settings.aiModel },
            set: { selection in
                if selection == Self.customModelID {
                    forceCustomModel = true
                } else {
                    forceCustomModel = false
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
        isFetchingModels = true
        Task {
            defer { isFetchingModels = false }
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
        isTestingConnection = true
        let started = Date()
        Task {
            defer { isTestingConnection = false }
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
        SettingsRow(title: transform.name, subtitle: subtitleText) {
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

    private var subtitleText: String {
        if let model = transform.model, !model.isEmpty {
            return "\(transform.prompt) · \(model)"
        }
        return transform.prompt
    }
}

/// Wraps `NSTextField` / `NSSecureTextField` with guaranteed `.left` alignment and standard rounded bezel.
private struct LeftAlignedTextField: NSViewRepresentable {
    var prompt: String = ""
    @Binding var text: String
    var isSecure: Bool = false
    var isEnabled: Bool = true

    func makeNSView(context: Context) -> NSTextField {
        let tf = isSecure ? NSSecureTextField() : NSTextField()
        tf.placeholderString = prompt
        tf.alignment = .left
        tf.bezelStyle = .roundedBezel
        tf.delegate = context.coordinator
        tf.font = .systemFont(ofSize: NSFont.systemFontSize)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.isEnabled = isEnabled
        nsView.alignment = .left
        nsView.placeholderString = prompt
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LeftAlignedTextField
        init(_ parent: LeftAlignedTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField {
                parent.text = tf.stringValue
            }
        }
    }
}
