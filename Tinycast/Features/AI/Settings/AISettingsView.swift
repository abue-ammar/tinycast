import AppKit
import SwiftUI

struct AISettingsView: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(AppSettings.self) private var appSettings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    @State private var providersPresented = false
    @State private var keyStatuses: [UUID: Bool] = [:]
    @State private var keyError = false
    @State private var editor: AIConnectionEditorTarget?
    @State private var pendingRemoval: AIConnection?

    private let keyStore = KeychainSecretStore.aiAPIKeys

    var body: some View {
        @Bindable var appSettings = appSettings
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $appSettings.aiEnabled) {
                    SettingsRowTitle(.aiAI, "Enable AI")
                    Text("Chat with the model you choose; nothing is loaded or sent until it is on.")
                }
                SettingsRow(
                    title: "Providers", subtitle: providerSummary, anchor: .aiProviders
                ) {
                    Button("Manage…") { providersPresented = true }
                }
            } header: {
                SettingsSectionHeader(.aiAI)
            }

            AICommandSection()
                .settingsEnabled(appSettings.aiEnabled)

            Group {
                defaultModelSection
                chatSection
                conversationsSection
                systemPromptSection
                MCPSettingsSection()
            }
            .settingsEnabled(appSettings.aiEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.ai)
        .sheet(isPresented: $providersPresented) {
            providersSheet
        }
        .onAppear {
            core.applyInstalledAILifecycle()
        }
        // Switched on with the pane already open, provider status would otherwise stay empty.
        .onChange(of: appSettings.aiEnabled) { core.applyInstalledAILifecycle() }
        .onChange(of: settings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            syncSelection()
        }
        .onChange(of: subscription.models) { syncSelection() }
        .onChange(of: subscription.phase) { syncSelection() }
        .onChange(of: installedAI.statuses) { syncSelection() }
    }

    private var defaultModelSection: some View {
        Section {
            // A Mac with nothing configured is the one that needs telling its free route is off.
            if let reason = appleIntelligenceReason {
                Label(reason, systemImage: "apple.intelligence")
                    .foregroundStyle(.secondary)
            }
            AIModelSelectionRows(
                selection: settings.defaultModel,
                select: { $0.map(settings.select) },
                modelLabel: {
                    SettingsRowTitle(.aiDefault, "Default model")
                    Text("Used by Tinycast features unless they ask you to choose another model.")
                },
                effortLabel: {
                    SettingsRowTitle(.aiDefault, "Reasoning effort")
                    Text("Applied when the default model supports reasoning effort.")
                }
            )
        } header: {
            SettingsSectionHeader(.aiDefault)
        } footer: {
            Text(defaultModelFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultModelFooter: String {
        if settings.defaultModel?.isOnDevice == true {
            return String(
                localized: "Apple Intelligence runs on this Mac. No key, no account, and nothing leaves it.",
                bundle: .appLanguage)
        }
        return settings.defaultModel == nil
            ? String(localized: "Turn on Apple Intelligence, or add a provider above.", bundle: .appLanguage)
            : String(localized: "Tinycast contacts only the selected provider when an AI feature runs.", bundle: .appLanguage)
    }

    /// Why the on-device route is missing from the picker, or `nil` when it is there.
    private var appleIntelligenceReason: String? {
        settings.isAppleIntelligenceAvailable() ? nil : AppleIntelligenceProvider.status().message
    }

    private var providerSummary: String {
        var providers: [String] = []
        if subscription.isConnected { providers.append("Codex") }
        for kind in [InstalledAIKind.claude, .openCode]
        where installedAI.status(for: kind).isReady {
            providers.append(kind.title)
        }
        if !settings.connections.isEmpty {
            let count = settings.connections.count
            providers.append(count == 1 ? String(
                localized: "1 API connection",
                bundle: .appLanguage) : String(
                localized: "\(count) API connections",
                bundle: .appLanguage))
        }
        return providers.isEmpty ? String(
            localized: "No external providers ready",
            bundle: .appLanguage) : providers.joined(separator: ", ")
    }

    private var chatSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.webSearchEnabled) {
                SettingsRowTitle(.aiChat, "Web search")
                Text(
                    "Sends prompts on to a search engine when the route offers one — Codex and OpenRouter.")
            }
        } header: {
            SettingsSectionHeader(.aiChat)
        } footer: {
            Text("Images pasted into the chat go to any model that accepts them; others never see one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var conversationsSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.opensTo) {
                ForEach(AIOpensTo.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Opens to")
                Text("What summoning AI Chat lands on.")
            }
            if settings.opensTo == .recent {
                Picker(selection: $settings.newChatAfter) {
                    ForEach(AINewChatAfter.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                } label: {
                    SettingsRowTitle(.aiConversations, "Start a new conversation after")
                    Text("Idle this long and the next summon starts fresh instead.")
                }
            }
            Picker(selection: $settings.retention) {
                ForEach(AIRetention.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Keep conversations")
                Text("Older conversations are deleted permanently.")
            }
            .onChange(of: settings.retention) { core.aiChatCoordinator.applyRetention() }
        } header: {
            SettingsSectionHeader(.aiConversations)
        } footer: {
            Text(
                String(localized: """
                    Conversations stay on this Mac. Nothing here is carried in a settings backup \
                    — which chats a Mac keeps is that Mac's business.
                    """, bundle: .appLanguage)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var systemPromptSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.systemPromptEnabled) {
                SettingsRowTitle(.aiSystemPrompt, "Send a system prompt")
                Text("Off sends nothing ahead of your message, not even what Tinycast says about itself.")
            }
            SystemPromptEditor(text: $settings.systemPrompt)
                .settingsEnabled(settings.systemPromptEnabled)
        } header: {
            SettingsSectionHeader(.aiSystemPrompt)
        } footer: {
            Text(
                String(localized: """
                    Your text is sent ahead of every message in every chat, after what Tinycast \
                    already tells the model about itself. Both are billed again on each turn.
                    """, bundle: .appLanguage)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var providersSheet: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("AI Providers").font(.title2.weight(.bold))
                Text("Use an installed account or connect an API endpoint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.xxl)

            Form {
                installedAISection
                apiConnectionsSection
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { providersPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.xxl)
        }
        .frame(width: Theme.Size.editorSheetWidth, height: 600)
        .sheet(item: $editor) { target in
            AIConnectionEditorSheet(
                target: target,
                onSave: saveConnection,
                onCancel: { editor = nil })
        }
        .confirmationDialog(
            pendingRemoval.map { String(
                localized: "Remove “\($0.title)”?",
                bundle: .appLanguage) } ?? String(
                localized: "Remove connection?",
                bundle: .appLanguage),
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
            core.applyInstalledAILifecycle()
        }
    }

    private var installedAISection: some View {
        Section {
            codexConnection
            if let limits = subscription.rateLimits, subscription.isConnected {
                if let primary = limits.primary {
                    quotaRow(primary, fallbackTitle: String(localized: "Primary window", bundle: .appLanguage))
                }
                if let secondary = limits.secondary {
                    quotaRow(secondary, fallbackTitle: String(localized: "Secondary window", bundle: .appLanguage))
                }
            }
            installedConnection(.claude)
            installedConnection(.openCode)
        } header: {
            SettingsSectionHeader(.aiInstalledAI)
        } footer: {
            Text(
                String(localized: """
                    Tinycast uses the Codex, Claude and OpenCode commands already installed \
                    and signed in on this Mac. Tinycast never stores or asks for their API keys.
                    """, bundle: .appLanguage)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var codexConnection: some View {
        if settings.enabledInstalledProviders.contains(.codex) {
            switch subscription.phase {
            case .starting:
                LabeledContent {
                    providerActions { providerToggle(.codex) }
                } label: {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking Codex…").foregroundStyle(.secondary)
                    }
                }
            case .idle, .signedOut:
                LabeledContent {
                    providerActions {
                        Button("Copy Sign-In Command") { copySignInCommand(.codex) }
                        Button("Check Again") { subscription.refresh() }
                        providerToggle(.codex)
                    }
                } label: {
                    Text("Codex · Sign in required")
                    Text("Run codex login in Terminal, then check again.")
                }
            case .connected:
                if let account = subscription.account {
                    LabeledContent {
                        providerActions {
                            Button("Refresh") { subscription.refresh() }
                            providerToggle(.codex)
                        }
                    } label: {
                        if let email = account.email {
                            RedactedText(
                                value: email,
                                revealHelp: String(localized: "Click to reveal the signed-in account", bundle: .appLanguage),
                                hideHelp: String(localized: "Click to hide the signed-in account", bundle: .appLanguage))
                        } else {
                            Text("Codex · Ready")
                        }
                        Text(
                            account.planTitle == "API key" ? String(
                                localized: "Codex API key",
                                bundle: .appLanguage) : "ChatGPT \(account.planTitle)")
                    }
                }
            case .unavailable(let message):
                LabeledContent {
                    providerActions {
                        Button("Install Codex CLI…") {
                            if let url = URL(string: "https://developers.openai.com/codex/cli") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button("Check Again") { subscription.refresh() }
                        providerToggle(.codex)
                    }
                } label: {
                    Text("Codex · Not installed")
                    Text(message)
                }
            case .failed(let message):
                LabeledContent {
                    providerActions {
                        Button("Try Again") { subscription.refresh() }
                        providerToggle(.codex)
                    }
                } label: {
                    Label("Codex check failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(message)
                }
            }
        } else {
            disabledProvider(.codex)
        }
    }

    @ViewBuilder
    private func installedConnection(_ kind: InstalledAIKind) -> some View {
        let status = installedAI.status(for: kind)
        if settings.enabledInstalledProviders.contains(kind) {
            switch status.phase {
            case .idle, .checking:
                LabeledContent {
                    providerActions { providerToggle(kind) }
                } label: {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking \(kind.title)…").foregroundStyle(.secondary)
                    }
                }
            case .ready:
                LabeledContent {
                    providerActions {
                        Button("Refresh") {
                            installedAI.refresh(kind: kind)
                        }
                        providerToggle(kind)
                    }
                } label: {
                    Text("\(kind.title) · Ready")
                    Text(
                        status.version.map { String(
                            localized: "Version \($0) · \(modelCount(status.models))",
                            bundle: .appLanguage) }
                            ?? modelCount(status.models))
                }
            case .signInRequired:
                LabeledContent {
                    providerActions {
                        Button("Copy Sign-In Command") { copySignInCommand(kind) }
                        Button("Check Again") {
                            installedAI.refresh(kind: kind)
                        }
                        providerToggle(kind)
                    }
                } label: {
                    Text("\(kind.title) · Sign in required")
                    Text("Run \(kind.signInCommand) in Terminal, then check again.")
                }
            case .notInstalled:
                LabeledContent {
                    providerActions {
                        Button("Install…") { NSWorkspace.shared.open(kind.installURL) }
                        Button("Check Again") {
                            installedAI.refresh(kind: kind)
                        }
                        providerToggle(kind)
                    }
                } label: {
                    Text("\(kind.title) · Not installed")
                    Text("Tinycast could not find the \(kind.command) command.")
                }
            case .failed(let message):
                LabeledContent {
                    providerActions {
                        Button("Try Again") {
                            installedAI.refresh(kind: kind)
                        }
                        providerToggle(kind)
                    }
                } label: {
                    Label("\(kind.title) check failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(message)
                }
            }
        } else {
            disabledProvider(kind)
        }
    }

    private func disabledProvider(_ kind: InstalledAIKind) -> some View {
        LabeledContent {
            providerActions { providerToggle(kind) }
        } label: {
            Text(kind.title)
            Text("Disabled")
        }
    }

    private func providerActions<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func providerToggle(_ kind: InstalledAIKind) -> some View {
        Toggle(
            String(localized: "Enable \(kind.title)", bundle: .appLanguage),
            isOn: Binding(
                get: { settings.enabledInstalledProviders.contains(kind) },
                set: { settings.setInstalledProviderEnabled($0, for: kind) })
        )
        .labelsHidden()
        .toggleStyle(.switch)
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
                        hasStoredKey: keyStatuses[connection.id] == true,
                        onEdit: { edit(connection) },
                        onRemove: { pendingRemoval = connection })
                }
            }
            Button {
                editor = AIConnectionEditorTarget(
                    connection: AIConnection(), hasStoredKey: false, isNew: true)
            } label: {
                Label {
                    SettingsRowTitle(.aiAPIConnections, "Add API Connection")
                } icon: {
                    Image(systemName: "plus")
                }
            }
            if keyError {
                Label("The login Keychain could not be accessed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            SettingsSectionHeader(.aiAPIConnections)
        } footer: {
            Text(
                String(localized: """
                    OpenAI, Claude, Gemini and OpenRouter are presets. Custom OpenAI-compatible \
                    endpoints are supported too. API keys stay in your login Keychain.
                    """, bundle: .appLanguage)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } })
    }

    private func syncSelection() {
        let enabledProviders = settings.enabledInstalledProviders
        settings.reconcile(
            codexModels: enabledProviders.contains(.codex) ? subscription.models : [],
            isUnavailable: !enabledProviders.contains(.codex) || subscription.phase == .signedOut
                || subscription.phase.isUnavailable)
        for kind in [InstalledAIKind.claude, .openCode] {
            let status = installedAI.status(for: kind)
            settings.reconcile(
                installed: kind,
                models: enabledProviders.contains(kind) ? status.models : [],
                isUnavailable: !enabledProviders.contains(kind) || status.phase == .signInRequired
                    || status.phase == .notInstalled)
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
        if minutes >= 1_440 { return String(localized: "\(minutes / 1_440)-day window", bundle: .appLanguage) }
        if minutes >= 60 { return String(localized: "\(minutes / 60)-hour window", bundle: .appLanguage) }
        return String(localized: "\(minutes)-minute window", bundle: .appLanguage)
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
                try keyStore.setSecret(key, for: connection.id)
            } else if retargeted, AIEndpointPolicy.isLoopback(connection.baseURL) {
                try keyStore.removeSecret(for: connection.id)
            } else if retargeted {
                return String(
                    localized: "Enter an API key for this endpoint — the saved key stays with the old one.",
                    bundle: .appLanguage)
            } else if !AIEndpointPolicy.isLoopback(connection.baseURL)
                && keyStatuses[connection.id] != true
            {
                return String(localized: "Enter an API key for this remote provider.", bundle: .appLanguage)
            }
            settings.save(connection)
            editor = nil
            loadKeyStatuses()
            syncSelection()
            return nil
        } catch {
            keyError = true
            return isNew
                ? String(localized: "The key could not be saved to Keychain.", bundle: .appLanguage)
                : String(localized: "The saved key could not be updated in Keychain.", bundle: .appLanguage)
        }
    }

    /// The same rule where the secret actually persists: a retarget brings its own key, or none.
    private func pointsSomewhereNew(_ connection: AIConnection) -> Bool {
        guard let saved = settings.connection(id: connection.id) else { return false }
        return !AIEndpointPolicy.sameDestination(connection, saved)
    }

    private func removeConnection(_ connection: AIConnection) {
        do {
            try keyStore.removeSecret(for: connection.id)
            settings.removeConnection(id: connection.id)
            pendingRemoval = nil
            loadKeyStatuses()
        } catch {
            keyError = true
        }
    }

    private func copySignInCommand(_ kind: InstalledAIKind) {
        Paster.copyPlainText(kind.signInCommand)
        core.showMessage(String(localized: "Copied \(kind.signInCommand)", bundle: .appLanguage))
    }

    private func modelCount(_ models: [InstalledAIModel]) -> String {
        models.count == 1 ? "1 model" : String(localized: "\(models.count) models", bundle: .appLanguage)
    }

    private func loadKeyStatuses() {
        var statuses: [UUID: Bool] = [:]
        do {
            for connection in settings.connections {
                statuses[connection.id] = try keyStore.hasSecret(for: connection.id)
            }
            keyStatuses = statuses
            keyError = false
        } catch {
            keyStatuses = statuses
            keyError = true
        }
    }
}

private struct AIConnectionEditorTarget: Identifiable {
    let connection: AIConnection
    let hasStoredKey: Bool
    let isNew: Bool
    var id: UUID { connection.id }
}

private struct AIConnectionRow: View {
    @Environment(\.locale) private var localizationLocale
    let connection: AIConnection
    let hasStoredKey: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        SettingsRow(
            title: connection.title,
            subtitle: "\(connection.provider.title) · \(keyStatus) · \(modelCount)"
        ) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
        } trailing: {
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
        if AIEndpointPolicy.isLoopback(connection.baseURL), !hasStoredKey { return String(
            localized: "No key",
            bundle: .appLanguage) }
        return hasStoredKey ? String(
            localized: "Keychain",
            bundle: .appLanguage) : String(
            localized: "Key missing",
            bundle: .appLanguage)
    }

    private var modelCount: String {
        connection.models.count == 1 ? "1 model" : String(localized: "\(connection.models.count) models", bundle: .appLanguage)
    }
}

private struct AIConnectionEditorSheet: View {
    @Environment(\.locale) private var localizationLocale
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
                    editorField(String(localized: "Name", bundle: .appLanguage)) {
                        TextField(
                            "Name", text: $connection.name, prompt: Text("Optional label"))
                    }
                    editorField(String(localized: "Provider", bundle: .appLanguage)) {
                        Picker("Provider", selection: $connection.provider) {
                            ForEach(AIProviderKind.allCases) { provider in
                                Text(LocalizedStringKey(provider.title)).tag(provider)
                            }
                        }
                        .labelsHidden()
                    }
                    editorField(String(localized: "Base URL", bundle: .appLanguage)) {
                        TextField(
                            "Base URL", text: $connection.baseURL,
                            prompt: Text(connection.provider.defaultBaseURL))
                    }
                    editorField(String(localized: "API Key", bundle: .appLanguage)) {
                        SecureField(
                            "API Key", text: $key, prompt: Text(apiKeyPlaceholder))
                    }
                    if storedKeyMatchesTarget {
                        Label("A key is already stored in Keychain", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if target.hasStoredKey {
                        Label(
                            String(
                                localized:
                                    "The saved key stays with the endpoint it was saved for. Enter a key for this one.",
                                bundle: .appLanguage
                            ),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                } header: {
                    Text(target.isNew ? String(
                        localized: "Add API Connection",
                        bundle: .appLanguage) : String(
                        localized: "Edit API Connection",
                        bundle: .appLanguage))
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
                        String(localized: """
                            Search the models available to this key and add one or more. Exact model \
                            IDs remain available when discovery is unsupported.
                            """, bundle: .appLanguage)
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
            connection.reasoningOptions = nil
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
                editorField(String(localized: "Find a model", bundle: .appLanguage)) {
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
                    Button("Use “\(query)” anyway") { addModel(query) }
                }
            }
        } else {
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
        }
    }

    private var manualModelField: some View {
        editorField(String(localized: "Model ID", bundle: .appLanguage)) {
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
        case .openAI, .openAICompatible: return String(localized: "Model ID (e.g. gpt-5.4-mini)", bundle: .appLanguage)
        case .anthropic: return String(localized: "Model ID (e.g. claude-sonnet-4-6)", bundle: .appLanguage)
        case .gemini: return String(localized: "Model ID (e.g. gemini-3.7-flash)", bundle: .appLanguage)
        case .openRouter: return String(localized: "Model ID (e.g. openai/gpt-5.4-mini)", bundle: .appLanguage)
        }
    }

    /// Discovery honours the Save rule: a retarget asks for a key rather than reuse the old host's.
    private var storedKeyMatchesTarget: Bool {
        target.hasStoredKey && AIEndpointPolicy.sameDestination(connection, target.connection)
    }

    private var apiKeyPlaceholder: String {
        if storedKeyMatchesTarget { return String(localized: "Leave blank to keep saved key", bundle: .appLanguage) }
        if AIEndpointPolicy.isLoopback(connection.baseURL) { return String(
            localized: "Optional for local endpoint",
            bundle: .appLanguage) }
        return String(localized: "Paste API key", bundle: .appLanguage)
    }

    private var modelSearchPlaceholder: String {
        connection.provider == .openRouter
            ? String(
                localized: "Search by model or company",
                bundle: .appLanguage) : String(
                localized: "Search available models",
                bundle: .appLanguage)
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
        addModel(match)
    }

    private func removeModel(_ model: String) {
        connection.models.removeAll { $0 == model }
        connection.visionModels.removeAll { $0 == model }
        connection.reasoningOptions?[model] = nil
    }

    private func discoverModels() async {
        let enteredKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String
        if !enteredKey.isEmpty {
            apiKey = enteredKey
        } else if storedKeyMatchesTarget {
            do {
                apiKey = try KeychainSecretStore.aiAPIKeys.secret(for: connection.id) ?? ""
            } catch {
                discovery = .failed(
                    String(
                        localized: "The saved key could not be read from Keychain.",
                        bundle: .appLanguage), allowsManualEntry: false)
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
                    ?? String(localized: "Enter a valid provider base URL.", bundle: .appLanguage),
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
                    ?? String(localized: "The provider could not load models. Enter one manually.", bundle: .appLanguage),
                allowsManualEntry: catalogError != .rejectedKey)
        }
    }

    private func addManualModel() {
        addModel(modelQuery)
    }

    private func addModel(_ model: AIModelDiscovery.Model) {
        addModel(
            model.id, acceptsImages: model.acceptsImages,
            reasoningOptions: model.reasoningOptions)
    }

    private func addModel(
        _ value: String, acceptsImages: Bool? = nil,
        reasoningOptions: AIConnection.ReasoningOptions? = nil
    ) {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        if !connection.models.contains(model) { connection.models.append(model) }
        if acceptsImages == true, !connection.visionModels.contains(model) {
            connection.visionModels.append(model)
        }
        if connection.provider == .openRouter, let reasoningOptions,
            !reasoningOptions.efforts.isEmpty
        {
            if connection.reasoningOptions == nil { connection.reasoningOptions = [:] }
            connection.reasoningOptions?[model] = reasoningOptions
        }
        modelQuery = ""
    }

    private func save() {
        if case .failed(_, let allowsManualEntry) = discovery, !allowsManualEntry {
            error = String(localized: "Resolve the API key or endpoint error before saving.", bundle: .appLanguage)
            return
        }
        guard !connection.models.isEmpty else {
            error = String(localized: "Select or add at least one model.", bundle: .appLanguage)
            return
        }
        do {
            _ = try AIEndpointPolicy.validate(connection.baseURL)
        } catch {
            self.error =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Enter a valid provider base URL.", bundle: .appLanguage)
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
