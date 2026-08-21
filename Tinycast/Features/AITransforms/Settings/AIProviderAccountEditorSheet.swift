import SwiftUI

/// Add / edit modal sheet for configuring an AI provider account.
struct AIProviderAccountEditorSheet: View {
    let account: AIProviderAccount?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core

    @State private var name: String
    @State private var providerPresetID: String
    @State private var baseURL: String
    @State private var keyDraft: String
    @State private var defaultModel: String
    @State private var defaultReasoning: AIReasoningEffort
    @State private var isLocal: Bool
    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels = false
    @State private var isTestingConnection = false
    @State private var connectionNote: ConnectionNote?
    @State private var errorMessage: String?
    @State private var forceCustomModel = false
    @FocusState private var nameFocused: Bool

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

    init(account: AIProviderAccount?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _providerPresetID = State(
            initialValue: account?.providerPresetID ?? AIProvider.catalog.first?.id ?? AIProvider.customID)
        _baseURL = State(initialValue: account?.baseURL ?? AIClient.defaultBaseURL)
        _defaultModel = State(initialValue: account?.defaultModel ?? AIClient.defaultModel)
        _defaultReasoning = State(initialValue: account?.defaultReasoning ?? .none)
        _isLocal = State(initialValue: account?.isLocal ?? false)
        let key = account.flatMap { SecretStore.secret(account: $0.secretAccountKey) } ?? ""
        _keyDraft = State(initialValue: key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(account == nil ? "Add Provider Account" : "Edit Provider Account")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Account Label")
                    .font(.callout.weight(.medium))
                TextField("", text: $name, prompt: Text("e.g. Google Gemini (Personal), OpenAI (Work)"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Provider Preset")
                    .font(.callout.weight(.medium))
                Picker("Provider Preset", selection: $providerPresetID) {
                    ForEach(AIProvider.catalog) { provider in
                        Label {
                            Text(provider.name)
                        } icon: {
                            if let icon = provider.iconName {
                                Image(icon)
                            } else {
                                Image(systemName: provider.symbolFallback)
                            }
                        }
                        .tag(provider.id)
                    }
                    Divider()
                    Label("Custom", systemImage: "slider.horizontal.3").tag(AIProvider.customID)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: providerPresetID) { _, newID in
                    if let preset = AIProvider.catalog.first(where: { $0.id == newID }) {
                        baseURL = preset.baseURL
                        isLocal = preset.isLocal
                        if name.isEmpty || AIProvider.catalog.contains(where: { $0.name == name }) {
                            name = preset.name
                        }
                        if preset.id == "Google Gemini" {
                            defaultModel = "gemini-3.7-flash"
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Base URL")
                    .font(.callout.weight(.medium))
                TextField("", text: $baseURL, prompt: Text(AIClient.defaultBaseURL))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("API Key")
                    .font(.callout.weight(.medium))
                SecureField("", text: $keyDraft, prompt: Text(isLocal ? "Keyless local server" : "sk-…"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .disabled(isLocal)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text("Default Model")
                        .font(.callout.weight(.medium))
                    Spacer()
                    HStack(spacing: Theme.Spacing.sm) {
                        Picker(selection: modelSelection) {
                            Text("Custom…").tag("custom")
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

                TextField("", text: $defaultModel, prompt: Text("Model ID (e.g. gemini-2.5-flash)"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .disabled(!isCustomModel && !fetchedModels.isEmpty)
                    .opacity((!isCustomModel && !fetchedModels.isEmpty) ? 0.5 : 1.0)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Default Reasoning Effort")
                    .font(.callout.weight(.medium))
                Picker("Default Reasoning Effort", selection: $defaultReasoning) {
                    ForEach(AIReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            HStack {
                Button("Test Connection") { testConnection() }
                    .disabled(isTestingConnection || defaultModel.isEmpty)

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

                Spacer()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                if let account {
                    Button("Delete Account", role: .destructive) {
                        core.aiProviderAccounts.remove(id: account.id)
                        dismiss()
                    }
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
        .onAppear {
            if account == nil { nameFocused = true }
        }
        .task {
            if !keyDraft.isEmpty {
                refreshModels()
            }
        }
    }

    private var isCustomModel: Bool {
        forceCustomModel || !fetchedModels.contains(defaultModel)
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { isCustomModel ? "custom" : defaultModel },
            set: { selection in
                if selection == "custom" {
                    forceCustomModel = true
                } else {
                    forceCustomModel = false
                    defaultModel = selection
                    connectionNote = nil
                }
            })
    }

    private func refreshModels() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLocal || !key.isEmpty else { return }
        isFetchingModels = true
        Task {
            defer { isFetchingModels = false }
            do {
                fetchedModels = try await AIClient.listModels(baseURL: baseURL, apiKey: key)
            } catch {
                fetchedModels = []
            }
        }
    }

    private func testConnection() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLocal || !key.isEmpty else {
            connectionNote = ConnectionNote(text: "Enter an API key first.", isGood: false)
            return
        }
        guard !defaultModel.isEmpty else {
            connectionNote = ConnectionNote(text: "Set a model to test.", isGood: false)
            return
        }
        connectionNote = ConnectionNote(text: "Testing…", isGood: nil)
        isTestingConnection = true
        let started = Date()
        Task {
            defer { isTestingConnection = false }
            do {
                try await AIClient.testConnection(baseURL: baseURL, apiKey: key, model: defaultModel)
                let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                connectionNote = ConnectionNote(text: "Working — responded in \(seconds)s.", isGood: true)
            } catch {
                connectionNote = ConnectionNote(text: error.localizedDescription, isGood: false)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        let draft = AIProviderAccount(
            id: account?.id ?? UUID(),
            name: trimmedName,
            providerPresetID: providerPresetID,
            baseURL: trimmedURL,
            defaultModel: trimmedModel,
            defaultReasoning: defaultReasoning,
            isLocal: isLocal
        )

        do {
            if account == nil {
                let created = try core.aiProviderAccounts.add(draft)
                SecretStore.setSecret(
                    trimmedKey.isEmpty ? nil : trimmedKey, account: created.secretAccountKey)
            } else {
                try core.aiProviderAccounts.update(draft)
                SecretStore.setSecret(trimmedKey.isEmpty ? nil : trimmedKey, account: draft.secretAccountKey)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
