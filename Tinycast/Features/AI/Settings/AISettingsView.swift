import AppKit
import SwiftUI

struct AISettingsView: View {
    @Environment(AISettingsStore.self) private var settings
    @Environment(AppSettings.self) private var appSettings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription

    @State private var keyStatuses: [UUID: Bool] = [:]
    @State private var keyError = false
    @State private var editor: AIConnectionEditorTarget?
    @State private var pendingRemoval: AIConnection?

    private let keyStore = APIKeyStore()

    var body: some View {
        @Bindable var appSettings = appSettings
        return Form {
            Section {
                Toggle(isOn: $appSettings.aiEnabled) {
                    Text("Enable AI")
                    Text("Chat with the model you choose; nothing is loaded or sent until it is on.")
                }
            } header: {
                Text("AI")
            }

            AICommandSection()
                .settingsEnabled(appSettings.aiEnabled)

            Group {
                defaultModelSection
                chatSection
                chatGPTSection
                apiConnectionsSection
            }
            .settingsEnabled(appSettings.aiEnabled)
        }
        .formStyle(.grouped)
        .sheet(item: $editor) { target in
            AIConnectionEditorSheet(
                target: target,
                onSave: saveConnection,
                onCancel: { editor = nil })
        }
        .confirmationDialog(
            pendingRemoval.map { "Remove “\($0.title)”?" } ?? "Remove connection?",
            isPresented: removalPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Connection", role: .destructive) {
                if let pendingRemoval { removeConnection(pendingRemoval) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its saved API key will also be deleted from Keychain.")
        }
        .onAppear {
            loadKeyStatuses()
            refreshSubscription()
        }
        // Switched on with the pane already open, the ChatGPT section would otherwise stay empty.
        .onChange(of: appSettings.aiEnabled) { refreshSubscription() }
        .onChange(of: subscription.models) { syncSelection() }
        .onChange(of: subscription.phase) { syncSelection() }
    }

    private var defaultModelSection: some View {
        Section {
            if modelGroups.isEmpty {
                Label("No AI provider configured", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            } else {
                Picker(selection: modelBinding) {
                    ForEach(modelGroups) { group in
                        Section(group.title) {
                            ForEach(group.choices) { choice in
                                Text(choice.title).tag(Optional(choice.selection))
                            }
                        }
                    }
                } label: {
                    Text("Default model")
                    Text("Used by Tinycast features unless they ask you to choose another model.")
                }
                if let efforts = selectedSubscriptionModel?.efforts, !efforts.isEmpty {
                    Picker(selection: effortBinding) {
                        ForEach(efforts) { effort in
                            Text(effort.title).tag(effort.id)
                        }
                    } label: {
                        Text("Reasoning effort")
                        Text("Applied when the default model uses your ChatGPT subscription.")
                    }
                }
            }
        } header: {
            Text("Default")
        } footer: {
            Text(
                modelGroups.isEmpty
                    ? "Connect ChatGPT or add an API connection below."
                    : "Tinycast contacts only the selected provider when an AI feature runs."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var chatSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.webSearchEnabled) {
                Text("Web search")
                Text(
                    "Sends prompts on to a search engine when the route offers one — ChatGPT and OpenRouter.")
            }
        } header: {
            Text("Chat")
        } footer: {
            Text("Images pasted into the chat go to any model that accepts them; others never see one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chatGPTSection: some View {
        Section {
            chatGPTConnection
            if let limits = subscription.rateLimits, subscription.isConnected {
                if let primary = limits.primary {
                    quotaRow(primary, fallbackTitle: "Primary window")
                }
                if let secondary = limits.secondary {
                    quotaRow(secondary, fallbackTitle: "Secondary window")
                }
            }
        } header: {
            Text("ChatGPT Subscription")
        } footer: {
            Text(
                "Uses OpenAI’s supported Codex App Server. The sign-in is stored in Tinycast’s "
                    + "private support folder and stays separate from your normal Codex setup."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chatGPTConnection: some View {
        switch subscription.phase {
        case .starting:
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking ChatGPT…").foregroundStyle(.secondary)
            }
        // `.idle` is nothing asked yet — with AI off, no check is coming, so it must not spin.
        case .idle, .signedOut:
            LabeledContent {
                Button("Connect…") { subscription.connect() }
            } label: {
                Text("Not connected")
                Text("Use models included with an eligible ChatGPT subscription.")
            }
        case .waitingForBrowser:
            LabeledContent {
                Button("Open Sign-In Again…") { subscription.connect() }
            } label: {
                Text("Finish signing in in your browser")
                Text("Return to Tinycast after the browser confirms sign-in.")
            }
        case .connected:
            if let account = subscription.account {
                LabeledContent {
                    Button("Refresh") { subscription.refresh() }
                    Button("Disconnect", role: .destructive) { subscription.logout() }
                } label: {
                    Text(account.email ?? "Connected to ChatGPT")
                    Text("ChatGPT \(account.planTitle)")
                }
            }
        case .unavailable(let message):
            LabeledContent {
                Button("Install Codex CLI…") {
                    if let url = URL(string: "https://developers.openai.com/codex/cli") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Check Again") { subscription.refresh() }
            } label: {
                Text("Codex CLI required")
                Text(message)
            }
        case .failed(let message):
            LabeledContent {
                Button("Try Again") { subscription.refresh() }
            } label: {
                Label("ChatGPT connection failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
            }
        }
    }

    private var apiConnectionsSection: some View {
        Section {
            if settings.connections.isEmpty {
                Text("No API connections yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.connections) { connection in
                    AIConnectionRow(
                        connection: connection,
                        isDefault: settings.defaultModel?.source == .api(connection.id),
                        hasStoredKey: keyStatuses[connection.id] == true,
                        onEdit: { edit(connection) },
                        onRemove: { pendingRemoval = connection })
                }
            }
            Button("Add API Connection…", systemImage: "plus") {
                editor = AIConnectionEditorTarget(
                    connection: AIConnection(), hasStoredKey: false, isNew: true)
            }
            if keyError {
                Label("The login Keychain could not be accessed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("API Connections")
        } footer: {
            Text(
                "OpenAI, Claude, Gemini and OpenRouter are presets. Custom OpenAI-compatible "
                    + "endpoints are supported too. API keys stay in your login Keychain."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var modelGroups: [AIModelGroup] {
        var groups: [AIModelGroup] = []
        if subscription.isConnected, !subscription.models.isEmpty {
            groups.append(
                AIModelGroup(
                    id: "chatgpt",
                    title: "ChatGPT",
                    choices: subscription.models.map {
                        AIModelChoice(
                            selection: .chatGPT(model: $0.id, effort: nil), title: $0.name)
                    }))
        }
        for connection in settings.connections where !connection.models.isEmpty {
            groups.append(
                AIModelGroup(
                    id: connection.id.uuidString,
                    title: connection.title,
                    choices: connection.models.map {
                        AIModelChoice(
                            selection: .api(connection: connection.id, model: $0), title: $0)
                    }))
        }
        return groups
    }

    private var selectedSubscriptionModel: ChatGPTSubscription.Model? {
        guard case .chatGPT(let model, _) = settings.defaultModel else { return nil }
        return subscription.models.first { $0.id == model }
    }

    private var modelBinding: Binding<AIModelSelection?> {
        Binding(
            get: {
                guard case .chatGPT(let model, _) = settings.defaultModel else {
                    return settings.defaultModel
                }
                return .chatGPT(model: model, effort: nil)
            },
            set: { selection in
                guard let selection else { return }
                settings.select(withDefaultEffort(selection))
            })
    }

    private var effortBinding: Binding<String> {
        Binding(
            get: {
                guard case .chatGPT(_, let effort) = settings.defaultModel else { return "" }
                return effort ?? ""
            },
            set: { effort in
                guard case .chatGPT(let model, _) = settings.defaultModel else { return }
                settings.select(.chatGPT(model: model, effort: effort))
            })
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } })
    }

    private func withDefaultEffort(_ selection: AIModelSelection) -> AIModelSelection {
        guard case .chatGPT(let model, _) = selection else { return selection }
        let effort = subscription.models.first { $0.id == model }?.resolvedEffort(nil)
        return .chatGPT(model: model, effort: effort)
    }

    private func syncSelection() {
        settings.reconcile(
            chatGPTModels: subscription.models, isSignedOut: subscription.phase == .signedOut)
        if settings.defaultModel == nil, let first = modelGroups.first?.choices.first {
            settings.select(withDefaultEffort(first.selection))
        }
    }

    private func quotaRow(
        _ window: ChatGPTSubscription.UsageWindow, fallbackTitle: String
    ) -> some View {
        LabeledContent(quotaTitle(window, fallback: fallbackTitle)) {
            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text("\(window.remainingPercent)% left")
                if let reset = window.resetsAt {
                    Text("Resets \(reset, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func quotaTitle(
        _ window: ChatGPTSubscription.UsageWindow, fallback: String
    ) -> String {
        guard let minutes = window.durationMinutes else { return fallback }
        if minutes >= 1_440 { return "\(minutes / 1_440)-day window" }
        if minutes >= 60 { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }

    private func edit(_ connection: AIConnection) {
        editor = AIConnectionEditorTarget(
            connection: connection,
            hasStoredKey: keyStatuses[connection.id] == true,
            isNew: false)
    }

    private func saveConnection(
        _ connection: AIConnection, key: String, isNew: Bool
    ) -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let retargeted = keyStatuses[connection.id] == true && pointsSomewhereNew(connection)
            if !key.isEmpty {
                try keyStore.setKey(key, for: connection.id)
            } else if retargeted, AIEndpointPolicy.isLoopback(connection.baseURL) {
                try keyStore.removeKey(for: connection.id)
            } else if retargeted {
                return "Enter an API key for this endpoint — the saved key stays with the old one."
            } else if !AIEndpointPolicy.isLoopback(connection.baseURL)
                && keyStatuses[connection.id] != true
            {
                return "Enter an API key for this remote provider."
            }
            settings.save(connection)
            editor = nil
            loadKeyStatuses()
            syncSelection()
            return nil
        } catch {
            keyError = true
            return isNew
                ? "The key could not be saved to Keychain."
                : "The saved key could not be updated in Keychain."
        }
    }

    /// The same rule where the secret actually persists: a retarget brings its own key, or none.
    private func pointsSomewhereNew(_ connection: AIConnection) -> Bool {
        guard let saved = settings.connection(id: connection.id) else { return false }
        return !AIEndpointPolicy.sameDestination(connection, saved)
    }

    private func removeConnection(_ connection: AIConnection) {
        do {
            try keyStore.removeKey(for: connection.id)
            settings.removeConnection(id: connection.id)
            pendingRemoval = nil
            loadKeyStatuses()
        } catch {
            keyError = true
        }
    }

    /// Opening the pane must not spawn the Codex helper for a feature that is switched off.
    private func refreshSubscription() {
        guard appSettings.aiEnabled, subscription.phase == .idle else { return }
        subscription.refresh()
    }

    private func loadKeyStatuses() {
        var statuses: [UUID: Bool] = [:]
        do {
            for connection in settings.connections {
                statuses[connection.id] = try keyStore.hasKey(for: connection.id)
            }
            keyStatuses = statuses
            keyError = false
        } catch {
            keyStatuses = statuses
            keyError = true
        }
    }
}

private struct AIModelChoice: Identifiable {
    let selection: AIModelSelection
    let title: String
    var id: AIModelSelection { selection }
}

private struct AIModelGroup: Identifiable {
    let id: String
    let title: String
    let choices: [AIModelChoice]
}

private struct AIConnectionEditorTarget: Identifiable {
    let connection: AIConnection
    let hasStoredKey: Bool
    let isNew: Bool
    var id: UUID { connection.id }
}

private struct AIConnectionRow: View {
    let connection: AIConnection
    let isDefault: Bool
    let hasStoredKey: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        SettingsRow(
            title: connection.title,
            subtitle: "\(connection.provider.title) · \(keyStatus) · \(modelCount)"
        ) {
            Image(systemName: "sparkles")
                .foregroundStyle(isDefault ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        } trailing: {
            if isDefault {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .help("Edit \(connection.title)")
                .accessibilityLabel("Edit \(connection.title)")
            Button(action: onRemove) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove \(connection.title)")
            .accessibilityLabel("Remove \(connection.title)")
        }
    }

    private var keyStatus: String {
        if AIEndpointPolicy.isLoopback(connection.baseURL), !hasStoredKey { return "No key" }
        return hasStoredKey ? "Keychain" : "Key missing"
    }

    private var modelCount: String {
        connection.models.count == 1 ? "1 model" : "\(connection.models.count) models"
    }
}

private struct AIConnectionEditorSheet: View {
    let target: AIConnectionEditorTarget
    let onSave: (AIConnection, String, Bool) -> String?
    let onCancel: () -> Void

    @State private var connection: AIConnection
    @State private var key = ""
    @State private var modelQuery = ""
    @State private var discovery: ModelDiscoveryState = .waitingForKey
    @State private var discoveryRevision = 0
    @State private var error: String?

    private let modelDiscovery = AIModelDiscoveryService()

    init(
        target: AIConnectionEditorTarget,
        onSave: @escaping (AIConnection, String, Bool) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        _connection = State(initialValue: target.connection)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    editorField("Name") {
                        TextField(
                            "Name", text: $connection.name, prompt: Text("Optional label"))
                    }
                    editorField("Provider") {
                        Picker("Provider", selection: $connection.provider) {
                            ForEach(AIProviderKind.allCases) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        .labelsHidden()
                    }
                    editorField("Base URL") {
                        TextField(
                            "Base URL", text: $connection.baseURL,
                            prompt: Text(connection.provider.defaultBaseURL))
                    }
                    editorField("API Key") {
                        SecureField(
                            "API Key", text: $key, prompt: Text(apiKeyPlaceholder))
                    }
                    if storedKeyMatchesTarget {
                        Label("A key is already stored in Keychain", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if target.hasStoredKey {
                        Label(
                            "The saved key stays with the endpoint it was saved for. "
                                + "Enter a key for this one.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                } header: {
                    Text(target.isNew ? "Add API Connection" : "Edit API Connection")
                }

                Section {
                    modelDiscoveryContent
                } header: {
                    HStack {
                        Text("Models")
                        Spacer()
                        if !connection.models.isEmpty {
                            Text("\(connection.models.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                } footer: {
                    Text(
                        "Search the models available to this key and add one or more. Exact model "
                            + "IDs remain available when discovery is unsupported."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(width: 620, height: 540)
        .task(id: discoveryRevision) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await discoverModels()
        }
        .onChange(of: key) { discoveryRevision += 1 }
        .onChange(of: connection.baseURL) { discoveryRevision += 1 }
        .onChange(of: connection.provider) { oldProvider, newProvider in
            if connection.baseURL.isEmpty || connection.baseURL == oldProvider.defaultBaseURL {
                connection.baseURL = newProvider.defaultBaseURL
            }
            discoveryRevision += 1
        }
    }

    @ViewBuilder
    private var modelDiscoveryContent: some View {
        switch discovery {
        case .waitingForKey:
            ForEach(connection.models, id: \.self) { model in selectedModelRow(model) }
            if AIEndpointPolicy.isLoopback(connection.baseURL) {
                Label("Checking this local endpoint for models…", systemImage: "network")
                    .foregroundStyle(.secondary)
            } else {
                Label("Enter an API key to search its available models.", systemImage: "key")
                    .foregroundStyle(.secondary)
            }
        case .loading:
            ForEach(connection.models, id: \.self) { model in selectedModelRow(model) }
            HStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.small)
                Text("Loading available models…").foregroundStyle(.secondary)
            }
        case .loaded(let models):
            ForEach(connection.models, id: \.self) { model in selectedModelRow(model) }
            if models.isEmpty {
                Label("No compatible text models were returned.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                manualModelField
            } else {
                editorField("Find a model") {
                    TextField(
                        "Find a model", text: $modelQuery,
                        prompt: Text(modelSearchPlaceholder)
                    )
                    .onSubmit { addExactMatch(from: models) }
                }
                modelSearchResults(models)
            }
        case .failed(let message, let allowsManualEntry):
            LabeledContent {
                Button("Try Again") { discoveryRevision += 1 }
            } label: {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            ForEach(connection.models, id: \.self) { model in
                selectedModelRow(model)
            }
            if allowsManualEntry { manualModelField }
        }
    }

    @ViewBuilder
    private func modelSearchResults(_ models: [AIModelDiscovery.Model]) -> some View {
        let query = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = matchingModels(in: models)
        if query.isEmpty {
            Text("Type a model or company name. \(models.count) models available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if matches.isEmpty {
            if connection.models.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
                Label("This model is already added.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("No available model matches this key.", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
                if connection.provider == .openAICompatible {
                    Button("Use “\(query)” anyway") { addModel(query, acceptsImages: nil) }
                }
            }
        } else {
            ForEach(matches) { model in
                Button {
                    addModel(model.id, acceptsImages: model.acceptsImages)
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(model.name)
                            if model.name != model.id {
                                Text(model.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(model.name)")
            }
        }
    }

    private var manualModelField: some View {
        editorField("Model ID") {
            TextField("Model ID", text: $modelQuery, prompt: Text(modelPlaceholder))
                .onSubmit(addManualModel)
        }
    }

    private func editorField<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent {
            content()
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                // LabeledContent right-aligns its value text, caret and all; a field reads left.
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title).font(.callout.weight(.medium))
        }
    }

    private func selectedModelRow(_ model: String) -> some View {
        LabeledContent(model) {
            Button {
                removeModel(model)
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(model)")
        }
    }

    private var modelPlaceholder: String {
        switch connection.provider {
        case .openAI, .openAICompatible: return "Model ID (e.g. gpt-5.4-mini)"
        case .anthropic: return "Model ID (e.g. claude-sonnet-4-6)"
        case .gemini: return "Model ID (e.g. gemini-3.7-flash)"
        case .openRouter: return "Model ID (e.g. openai/gpt-5.4-mini)"
        }
    }

    /// Discovery reaches the endpoint before Save does, so it honours the same rule: retarget the
    /// connection and it must ask for a key rather than introduce the old one to a new host.
    private var storedKeyMatchesTarget: Bool {
        target.hasStoredKey && AIEndpointPolicy.sameDestination(connection, target.connection)
    }

    private var apiKeyPlaceholder: String {
        if storedKeyMatchesTarget { return "Leave blank to keep saved key" }
        if AIEndpointPolicy.isLoopback(connection.baseURL) { return "Optional for local endpoint" }
        return "Paste API key"
    }

    private var modelSearchPlaceholder: String {
        connection.provider == .openRouter
            ? "Search by model or company" : "Search available models"
    }

    private func matchingModels(
        in models: [AIModelDiscovery.Model]
    ) -> [AIModelDiscovery.Model] {
        AIModelDiscovery.search(
            models, query: modelQuery, excluding: Set(connection.models), limit: 12)
    }

    private func addExactMatch(from models: [AIModelDiscovery.Model]) {
        let query = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let match = models.first(where: {
                $0.id.caseInsensitiveCompare(query) == .orderedSame
                    || $0.name.caseInsensitiveCompare(query) == .orderedSame
            })
        else { return }
        addModel(match.id, acceptsImages: match.acceptsImages)
    }

    private func removeModel(_ model: String) {
        connection.models.removeAll { $0 == model }
        connection.visionModels.removeAll { $0 == model }
    }

    private func discoverModels() async {
        let enteredKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String
        if !enteredKey.isEmpty {
            apiKey = enteredKey
        } else if storedKeyMatchesTarget {
            do {
                apiKey = try APIKeyStore().key(for: connection.id) ?? ""
            } catch {
                discovery = .failed(
                    "The saved key could not be read from Keychain.", allowsManualEntry: false)
                return
            }
        } else if AIEndpointPolicy.isLoopback(connection.baseURL) {
            apiKey = ""
        } else {
            discovery = .waitingForKey
            return
        }

        let baseURL: URL
        do {
            baseURL = try AIEndpointPolicy.validate(connection.baseURL)
        } catch {
            discovery = .failed(
                (error as? LocalizedError)?.errorDescription
                    ?? "Enter a valid provider base URL.",
                allowsManualEntry: false)
            return
        }
        discovery = .loading
        do {
            let models = try await modelDiscovery.models(
                provider: connection.provider, baseURL: baseURL, apiKey: apiKey)
            guard !Task.isCancelled else { return }
            discovery = .loaded(models)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let catalogError = error as? AIModelDiscovery.DiscoveryError
            discovery = .failed(
                catalogError?.errorDescription
                    ?? "The provider could not load models. Enter one manually.",
                allowsManualEntry: catalogError != .rejectedKey)
        }
    }

    private func addManualModel() {
        addModel(modelQuery, acceptsImages: nil)
    }

    private func addModel(_ value: String, acceptsImages: Bool?) {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        if !connection.models.contains(model) { connection.models.append(model) }
        if acceptsImages == true, !connection.visionModels.contains(model) {
            connection.visionModels.append(model)
        }
        modelQuery = ""
    }

    private func save() {
        if case .failed(_, let allowsManualEntry) = discovery, !allowsManualEntry {
            error = "Resolve the API key or endpoint error before saving."
            return
        }
        guard !connection.models.isEmpty else {
            error = "Select or add at least one model."
            return
        }
        do {
            _ = try AIEndpointPolicy.validate(connection.baseURL)
        } catch {
            self.error =
                (error as? LocalizedError)?.errorDescription
                ?? "Enter a valid provider base URL."
            return
        }
        error = onSave(connection, key, target.isNew)
    }
}

private enum ModelDiscoveryState: Equatable {
    case waitingForKey
    case loading
    case loaded([AIModelDiscovery.Model])
    case failed(String, allowsManualEntry: Bool)
}
