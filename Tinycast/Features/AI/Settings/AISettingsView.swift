import AppKit
import SwiftUI

struct AISettingsView: View {
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

            FeatureCommandsSection(owner: .ai, anchor: .aiCommands)
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
            return "Apple Intelligence runs on this Mac. No key, no account, and nothing leaves it."
        }
        return settings.defaultModel == nil
            ? "Turn on Apple Intelligence, or add a provider above."
            : "Tinycast contacts only the selected provider when an AI feature runs."
    }

    /// Why the on-device route is missing from the picker, or `nil` when it is there.
    private var appleIntelligenceReason: String? {
        settings.isAppleIntelligenceAvailable() ? nil : AppleIntelligenceProvider.status().message
    }

    private var providerSummary: String {
        var providers: [String] = []
        if subscription.isConnected { providers.append("Codex") }
        for kind in InstalledAIKind.cliKinds
        where installedAI.status(for: kind).isReady {
            providers.append(kind.title)
        }
        if !settings.connections.isEmpty {
            let count = settings.connections.count
            providers.append(count == 1 ? "1 API connection" : "\(count) API connections")
        }
        return providers.isEmpty ? "No external providers ready" : providers.joined(separator: ", ")
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
                ForEach(AIOpensTo.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Opens to")
                Text("What summoning AI Chat lands on.")
            }
            if settings.opensTo == .recent {
                Picker(selection: $settings.newChatAfter) {
                    ForEach(AINewChatAfter.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.aiConversations, "Start a new conversation after")
                    Text("Idle this long and the next summon starts fresh instead.")
                }
            }
            Picker(selection: $settings.retention) {
                ForEach(AIRetention.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Keep conversations")
                Text("Older conversations are deleted permanently.")
            }
            .onChange(of: settings.retention) { core.aiChatCoordinator.applyRetention() }
        } header: {
            SettingsSectionHeader(.aiConversations)
        } footer: {
            Text(
                "Conversations stay on this Mac. Nothing here is carried in a settings backup — which "
                    + "chats a Mac keeps is that Mac's business."
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
                "Your text is sent ahead of every message in every chat, after what Tinycast "
                    + "already tells the model about itself. Both are billed again on each turn."
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
            core.applyInstalledAILifecycle()
        }
    }

    private var installedAISection: some View {
        Section {
            codexConnection
            if let limits = subscription.rateLimits, subscription.isConnected {
                if let primary = limits.primary {
                    quotaRow(primary, fallbackTitle: "Primary window")
                }
                if let secondary = limits.secondary {
                    quotaRow(secondary, fallbackTitle: "Secondary window")
                }
            }
            installedConnection(.claude)
            installedConnection(.grok)
            installedConnection(.openCode)
        } header: {
            SettingsSectionHeader(.aiInstalledAI)
        } footer: {
            Text(
                "Tinycast uses the Codex, Claude, Grok and OpenCode commands already installed and signed "
                    + "in on this Mac. Tinycast never stores or asks for their API keys."
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
                                revealHelp: "Click to reveal the signed-in account",
                                hideHelp: "Click to hide the signed-in account")
                        } else {
                            Text("Codex · Ready")
                        }
                        Text(
                            account.planTitle == "API key" ? "Codex API key" : "ChatGPT \(account.planTitle)")
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
                        status.version.map { "Version \($0) · \(modelCount(status.models))" }
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
            "Enable \(kind.title)",
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
                "OpenAI, Claude, Gemini and OpenRouter are presets. Custom OpenAI-compatible "
                    + "endpoints are supported too. API keys stay in your login Keychain."
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
        for kind in InstalledAIKind.cliKinds {
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
        let outcome = AIConnectionKeyPolicy.resolve(
            enteredKey: key, connection: connection, saved: settings.connection(id: connection.id),
            hasStoredKey: keyStatuses[connection.id] == true)
        do {
            switch outcome {
            case .store(let key): try keyStore.setSecret(key, for: connection.id)
            case .removeStored: try keyStore.removeSecret(for: connection.id)
            case .keep: break
            case .reject(let message): return message
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
        core.showMessage("Copied \(kind.signInCommand)")
    }

    private func modelCount(_ models: [InstalledAIModel]) -> String {
        models.count == 1 ? "1 model" : "\(models.count) models"
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

private struct AIConnectionRow: View {
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
        if AIEndpointPolicy.isLoopback(connection.baseURL), !hasStoredKey { return "No key" }
        return hasStoredKey ? "Keychain" : "Key missing"
    }

    private var modelCount: String {
        connection.models.count == 1 ? "1 model" : "\(connection.models.count) models"
    }
}
