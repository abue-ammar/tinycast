import SwiftUI

struct AIConnectionEditorTarget: Identifiable {
    let connection: AIConnection
    let hasStoredKey: Bool
    let headers: [String: String]
    let isNew: Bool
    var id: UUID { connection.id }
}

struct AIConnectionEditorPanel: View {
    let target: AIConnectionEditorTarget
    let onSave: (AIConnection, String, [String: String], Bool) -> String?
    let onCancel: () -> Void

    @State private var connection: AIConnection
    @State private var key = ""
    @State private var headers: [HeaderDraft]
    @FocusState private var focusedHeader: UUID?
    @State private var modelQuery = ""
    @State private var discovery: ModelDiscoveryState = .waitingForKey
    @State private var discoveryRevision = 0
    @State private var error: String?

    private let modelDiscovery = AIModelDiscoveryService()

    private struct HeaderDraft: Identifiable, Equatable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    init(
        target: AIConnectionEditorTarget,
        onSave: @escaping (AIConnection, String, [String: String], Bool) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        _connection = State(initialValue: target.connection)
        _headers = State(
            initialValue: target.headers.sorted { $0.key < $1.key }.map {
                HeaderDraft(name: $0.key, value: $0.value)
            })
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: target.isNew ? "Add API Connection" : "Edit API Connection"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            Form {
                Section {
                    editorField("Name") {
                        TextField(
                            "Name", text: $connection.name, prompt: Text("Optional label")
                        )
                        .settingsEditorTextField()
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
                            prompt: Text(connection.provider.defaultBaseURL)
                        )
                        .settingsEditorTextField()
                    }
                    editorField("API Key") {
                        RevealableSecureField(
                            title: String(localized: "API Key"), text: $key,
                            prompt: Text(apiKeyPlaceholder)
                        )
                        .settingsEditorTextField()
                    }
                    if storedKeyMatchesTarget {
                        Label("A key is already stored in Keychain", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if target.hasStoredKey {
                        Label(
                            """
                            The saved key stays with the endpoint it was saved for. Enter a key for \
                            this one.
                            """,
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                }

                headersSection

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
                        """
                        Search the models available to this key and add one or more. Exact model \
                        IDs remain available when discovery is unsupported.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 620, height: 540)
        .settingsEditorPanelSurface()
        .task(id: discoveryRevision) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await discoverModels()
        }
        .onChange(of: key) { discoveryRevision += 1 }
        .onChange(of: headers) { discoveryRevision += 1 }
        .onChange(of: connection.baseURL) {
            connection.dropDeclaredLevels()
            connection.outputLimits = nil
            discoveryRevision += 1
        }
        .onChange(of: connection.provider) { oldProvider, newProvider in
            if connection.baseURL.isEmpty || connection.baseURL == oldProvider.defaultBaseURL {
                connection.baseURL = newProvider.defaultBaseURL
            }
            connection.reasoningOptions = nil
            connection.outputLimits = nil
            discoveryRevision += 1
        }
    }

    private var headersSection: some View {
        Section {
            LabeledContent {
                Button("Add Header", action: addHeader)
                    .fixedSize()
            } label: {
                Text("Request Headers")
                Text("Sent with every request, replacing a default header of the same name.")
            }
            ForEach($headers) { $header in
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Name", text: $header.name, prompt: Text("Name"))
                        .labelsHidden()
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .frame(width: Theme.Size.aiVariableName)
                        .focused($focusedHeader, equals: header.id)
                    RevealableSecureField(
                        title: String(localized: "Value of \(header.name)"), text: $header.value,
                        prompt: Text("Value")
                    )
                    .labelsHidden()
                    .font(.callout.monospaced())
                    Button {
                        headers.removeAll { $0.id == header.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                    .accessibilityLabel("Remove \(header.name)")
                }
            }
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
                    .settingsEditorTextField()
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
        let isQueryAdded = connection.models.contains {
            $0.caseInsensitiveCompare(query) == .orderedSame
        }
        // A gateway can list dated builds but accept a short alias that a listed ID contains.
        let offersTypedID =
            !query.isEmpty && !isQueryAdded
            && AIModelDiscovery.exactMatch(models, query: query) == nil
        if query.isEmpty {
            Text("Type a model or company name. \(models.count) models available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if matches.isEmpty && isQueryAdded {
            Label("This model is already added.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else if matches.isEmpty {
            Label("No available model matches this key.", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
        }
        ForEach(matches) { model in
            Button {
                addModel(model)
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
        if offersTypedID {
            Button("Use “\(query)” anyway") { addModel(query) }
        }
    }

    private var manualModelField: some View {
        editorField("Model ID") {
            TextField("Model ID", text: $modelQuery, prompt: Text(modelPlaceholder))
                .settingsEditorTextField()
                .onSubmit(addManualModel)
        }
    }

    private func editorField<Content: View>(
        _ title: LocalizedStringResource, @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsEditorField(title, labelFont: .callout.weight(.medium), content: content)
    }

    private func selectedModelRow(_ model: String) -> some View {
        LabeledContent(model) {
            HStack(spacing: Theme.Spacing.md) {
                if connection.takesDeclaredLevels { reasoningLevelsMenu(model) }
                Button {
                    removeModel(model)
                } label: {
                    Image(systemName: "minus.circle").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(model)")
            }
        }
    }

    private func reasoningLevelsMenu(_ model: String) -> some View {
        let declared = connection.declaredLevels(for: model)
        return Menu {
            ForEach(connection.declarableLevels, id: \.self) { level in
                Toggle(
                    ChatGPTSubscription.Effort(id: level, detail: nil).title,
                    isOn: Binding(
                        get: { declared.contains(level) },
                        set: { isOn in
                            var levels = declared
                            if isOn { levels.insert(level) } else { levels.remove(level) }
                            connection.declareLevels(levels, for: model)
                        }))
            }
        } label: {
            Text(declaredLevelsTitle(declared)).font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Reasoning levels for \(model)")
    }

    private func declaredLevelsTitle(_ declared: Set<String>) -> String {
        switch declared.count {
        case 0: return String(localized: "Reasoning levels")
        default: return String(localized: "\(declared.count) levels")
        }
    }

    private var modelPlaceholder: String {
        let example: String
        switch connection.provider {
        case .openAI, .openAICompatible: example = "gpt-5.4-mini"
        case .anthropic: example = "claude-sonnet-4-6"
        case .gemini: example = "gemini-3.7-flash"
        case .openRouter: example = "openai/gpt-5.4-mini"
        }
        return String(localized: "Model ID (e.g. \(example))")
    }

    /// Discovery honours the Save rule: a retarget asks for a key rather than reuse the old host's.
    private var storedKeyMatchesTarget: Bool {
        target.hasStoredKey && AIEndpointPolicy.sameDestination(connection, target.connection)
    }

    private var apiKeyPlaceholder: String {
        if storedKeyMatchesTarget { return String(localized: "Leave blank to keep saved key") }
        if !headers.isEmpty { return String(localized: "Optional with request headers") }
        if AIEndpointPolicy.isLoopback(connection.baseURL) {
            return String(localized: "Optional for local endpoint")
        }
        return String(localized: "Paste API key")
    }

    private var modelSearchPlaceholder: String {
        connection.provider == .openRouter
            ? String(localized: "Search by model or company") : String(localized: "Search available models")
    }

    private func matchingModels(
        in models: [AIModelDiscovery.Model]
    ) -> [AIModelDiscovery.Model] {
        AIModelDiscovery.search(
            models, query: modelQuery, excluding: Set(connection.models), limit: 12)
    }

    private func addExactMatch(from models: [AIModelDiscovery.Model]) {
        guard let match = AIModelDiscovery.exactMatch(models, query: modelQuery) else { return }
        addModel(match)
    }

    private func removeModel(_ model: String) {
        connection.models.removeAll { $0 == model }
        connection.visionModels.removeAll { $0 == model }
        connection.reasoningOptions?[model] = nil
        connection.outputLimits?[model] = nil
    }

    private func discoverModels() async {
        let requestHeaders: [String: String]
        do {
            requestHeaders = try validatedHeaders()
        } catch {
            discovery = .failed(error.localizedDescription, allowsManualEntry: false)
            return
        }
        let enteredKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String
        if !enteredKey.isEmpty {
            apiKey = enteredKey
        } else if storedKeyMatchesTarget {
            do {
                apiKey = try KeychainSecretStore.aiAPIKeys.secret(for: connection.id) ?? ""
            } catch {
                discovery = .failed(
                    String(localized: "The saved key could not be read from Keychain."),
                    allowsManualEntry: false)
                return
            }
        } else if AIEndpointPolicy.isLoopback(connection.baseURL) || !requestHeaders.isEmpty {
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
                    ?? String(localized: "Enter a valid provider base URL."),
                allowsManualEntry: false)
            return
        }
        discovery = .loading
        do {
            let models = try await modelDiscovery.models(
                provider: connection.provider, baseURL: baseURL, apiKey: apiKey,
                headers: requestHeaders)
            guard !Task.isCancelled else { return }
            discovery = .loaded(models)
            connection.adoptCatalog(models)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let catalogError = error as? AIModelDiscovery.DiscoveryError
            discovery = .failed(
                catalogError?.errorDescription
                    ?? String(localized: "The provider could not load models. Enter one manually."),
                allowsManualEntry: catalogError != .rejectedKey)
        }
    }

    private func validatedHeaders() throws -> [String: String] {
        try AIRequestHeaders.validated(headers.map { ($0.name, $0.value) })
    }

    private func addHeader() {
        let draft = HeaderDraft()
        headers.append(draft)
        focusedHeader = draft.id
    }

    private func addManualModel() {
        addModel(modelQuery)
    }

    private func addModel(_ model: AIModelDiscovery.Model) {
        addModel(model.id, acceptsImages: model.acceptsImages)
        connection.adoptCatalog([model])
    }

    private func addModel(_ value: String, acceptsImages: Bool? = nil) {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        if !connection.models.contains(model) { connection.models.append(model) }
        if acceptsImages == true, !connection.visionModels.contains(model) {
            connection.visionModels.append(model)
        }
        modelQuery = ""
    }

    private func save() {
        let requestHeaders: [String: String]
        do {
            requestHeaders = try validatedHeaders()
        } catch {
            self.error = error.localizedDescription
            return
        }
        if case .failed(_, let allowsManualEntry) = discovery, !allowsManualEntry {
            error = String(localized: "Resolve the API key or endpoint error before saving.")
            return
        }
        guard !connection.models.isEmpty else {
            error = String(localized: "Select or add at least one model.")
            return
        }
        do {
            _ = try AIEndpointPolicy.validate(connection.baseURL)
        } catch {
            self.error =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Enter a valid provider base URL.")
            return
        }
        error = onSave(connection, key, requestHeaders, target.isNew)
    }
}

private enum ModelDiscoveryState: Equatable {
    case waitingForKey
    case loading
    case loaded([AIModelDiscovery.Model])
    case failed(String, allowsManualEntry: Bool)
}
