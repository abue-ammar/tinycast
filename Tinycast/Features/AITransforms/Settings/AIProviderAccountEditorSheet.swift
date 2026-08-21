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
    @State private var testState: TestState = .idle
    @State private var keyValidationState: KeyValidationState = .unvalidated
    @State private var connectionNote: ConnectionNote?
    @State private var errorMessage: String?
    @State private var forceCustomModel = false

    private enum FocusField: Hashable {
        case name
        case apiKey
    }
    @FocusState private var focusedField: FocusField?

    private enum KeyValidationState: Equatable {
        case unvalidated
        case validating
        case valid
        case invalid(String)
    }

    private enum TestState: Equatable {
        case idle
        case testing
        case success
        case failed
    }

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
        let initialPresetID =
            account?.providerPresetID ?? AIProvider.catalog.first?.id ?? AIProvider.customID
        let initialPreset = AIProvider.catalog.first { $0.id == initialPresetID }
        _name = State(initialValue: account?.name ?? initialPreset?.name ?? "")
        _providerPresetID = State(initialValue: initialPresetID)
        _baseURL = State(initialValue: account?.baseURL ?? initialPreset?.baseURL ?? AIClient.defaultBaseURL)
        _defaultModel = State(
            initialValue: account?.defaultModel
                ?? (initialPresetID == "Google Gemini"
                    ? "gemini-3.7-flash"
                    : (initialPresetID == "ChatGPT (Subscription)" ? "gpt-4o" : AIClient.defaultModel)))
        _defaultReasoning = State(initialValue: account?.defaultReasoning ?? .none)
        _isLocal = State(initialValue: account?.isLocal ?? initialPreset?.isLocal ?? false)
        let isOAuth = account?.isOAuth ?? initialPreset?.isOAuth ?? false
        _isOAuthState = State(initialValue: isOAuth)
        let key = account.flatMap { SecretStore.secret(account: $0.secretAccountKey) } ?? ""
        _keyDraft = State(initialValue: key)
    }
    @State private var isOAuthState: Bool
    private var oauth: ChatGPTOAuthService { ChatGPTOAuthService.shared }

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
                    .focused($focusedField, equals: .name)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Provider Preset")
                    .font(.callout.weight(.medium))
                Picker("Provider Preset", selection: $providerPresetID) {
                    ForEach(AIProvider.catalog) { provider in
                        Label {
                            Text(provider.name)
                        } icon: {
                            AIProviderIcon(preset: provider, size: 14)
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
                        isOAuthState = preset.isOAuth
                        name = preset.name
                        keyValidationState = .unvalidated
                        testState = .idle
                        connectionNote = nil
                        if preset.id == "Google Gemini" {
                            defaultModel = "gemini-3.7-flash"
                        } else if preset.id == "ChatGPT (Subscription)" {
                            defaultModel = "gpt-4o"
                        }
                        if !preset.isOAuth && !preset.isLocal {
                            focusedField = .apiKey
                        }
                    }
                }
            }

            if isOAuthState {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Authentication")
                        .font(.callout.weight(.medium))

                    HStack(spacing: Theme.Spacing.sm) {
                        switch oauth.state {
                        case .authenticated(let email):
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(
                                    email.map { "Signed in as \($0)" }
                                        ?? "Signed in with ChatGPT Subscription"
                                )
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Sign Out", role: .destructive) {
                                oauth.signOut()
                            }
                            .controlSize(.small)

                        case .authenticating:
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for browser login…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") {
                                oauth.cancel()
                            }
                            .controlSize(.small)

                        case .unauthenticated, .failed:
                            Button("Sign in with ChatGPT…") {
                                oauth.startAuthFlow()
                            }
                            .buttonStyle(.borderedProminent)
                            if case .failed(let error) = oauth.state {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Base URL")
                        .font(.callout.weight(.medium))
                    TextField("", text: $baseURL, prompt: Text(AIClient.defaultBaseURL))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text("API Key")
                            .font(.callout.weight(.medium))
                        if case .valid = keyValidationState {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else if case .invalid = keyValidationState {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        SecureField(
                            "", text: $keyDraft, prompt: Text(isLocal ? "Keyless local server" : "sk-…")
                        )
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .disabled(isLocal)
                        .focused($focusedField, equals: .apiKey)
                        .onChange(of: keyDraft) { _, _ in
                            keyValidationState = .unvalidated
                            testState = .idle
                        }

                        if !isLocal {
                            Button {
                                validateKey()
                            } label: {
                                switch keyValidationState {
                                case .validating:
                                    ProgressView()
                                        .controlSize(.small)
                                case .valid:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                case .invalid:
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .foregroundStyle(.red)
                                case .unvalidated:
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .help("Validate API Key")
                            .disabled(
                                keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || keyValidationState == .validating)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Default Model")
                    .font(.callout.weight(.medium))

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

                TextField("", text: $defaultModel, prompt: Text("Model ID (e.g. gemini-2.5-flash)"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .disabled(!isCustomModel)
                    .opacity(isCustomModel ? 1.0 : 0.5)
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: Theme.Spacing.md) {
                if let account {
                    Button(role: .destructive) {
                        core.aiProviderAccounts.remove(id: account.id)
                        dismiss()
                    } label: {
                        Label("Remove Provider", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    testConnection()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        switch testState {
                        case .testing:
                            ProgressView()
                                .controlSize(.small)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(.red)
                        case .idle:
                            Image(systemName: "bolt")
                        }
                        Text("Test")
                    }
                }
                .disabled(testState == .testing || defaultModel.isEmpty)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(action: save) {
                    if account == nil {
                        Label("Add", systemImage: "plus")
                    } else {
                        Label("Save", systemImage: "checkmark")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
        .onAppear {
            if account == nil {
                focusedField = (isOAuthState || isLocal) ? .name : .apiKey
            }
        }
        .task {
            if !keyDraft.isEmpty || isOAuthState {
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
                forceCustomModel = (selection == "custom")
                if selection != "custom" {
                    defaultModel = selection
                    connectionNote = nil
                }
            })
    }

    private func resolveKey() async throws -> String {
        if isOAuthState {
            return try await oauth.validAccessToken()
        }
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isLocal && key.isEmpty {
            throw AIClientError.notConfigured
        }
        return key
    }

    private func refreshModels() {
        isFetchingModels = true
        Task {
            defer { isFetchingModels = false }
            guard let key = try? await resolveKey() else { return }
            fetchedModels = (try? await AIClient.listModels(baseURL: baseURL, apiKey: key)) ?? []
        }
    }

    private func validateKey() {
        keyValidationState = .validating
        Task {
            do {
                let key = try await resolveKey()
                fetchedModels = try await AIClient.listModels(baseURL: baseURL, apiKey: key)
                keyValidationState = .valid
            } catch {
                keyValidationState = .invalid(error.localizedDescription)
            }
        }
    }

    private func testConnection() {
        connectionNote = ConnectionNote(text: "Testing…", isGood: nil)
        testState = .testing
        let started = Date()
        Task {
            do {
                let key = try await resolveKey()
                guard !defaultModel.isEmpty else {
                    connectionNote = ConnectionNote(text: "Set a model to test.", isGood: false)
                    testState = .failed
                    return
                }
                try await AIClient.testConnection(baseURL: baseURL, apiKey: key, model: defaultModel)
                let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                connectionNote = ConnectionNote(text: "Working — responded in \(seconds)s.", isGood: true)
                testState = .success
            } catch {
                connectionNote = ConnectionNote(text: error.localizedDescription, isGood: false)
                testState = .failed
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
            isLocal: isLocal,
            isOAuth: isOAuthState
        )

        do {
            if account == nil {
                try core.aiProviderAccounts.add(draft)
            } else {
                try core.aiProviderAccounts.update(draft)
            }
            if !isOAuthState {
                SecretStore.setSecret(
                    trimmedKey.isEmpty ? nil : trimmedKey, account: draft.secretAccountKey)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
