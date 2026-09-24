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
                    HStack(spacing: Theme.Spacing.lg) {
                        SettingsTabIcon(
                            systemImage: SettingsTab.ai.systemImage, tint: .accentColor,
                            size: Theme.Size.settingsRowIcon * 1.5)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.aiAI, "Enable AI")
                            Text("Nothing is loaded or sent while it is off.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
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
        .settingsEditorPanel(isPresented: $providersPresented) {
            providersPanel
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
                },
                effortLabel: {
                    SettingsRowTitle(.aiDefault, "Reasoning effort")
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
            return "Apple Intelligence runs on this Mac. Nothing leaves it."
        }
        return settings.defaultModel == nil
            ? "Turn on Apple Intelligence, or add a provider above."
            : "Only the selected provider is contacted."
    }

    /// Why the on-device route is missing from the picker, or `nil` when it is there.
    private var appleIntelligenceReason: String? {
        settings.isAppleIntelligenceAvailable() ? nil : AppleIntelligenceProvider.status().message
    }

    private var providerSummary: String {
        var providers: [String] = []
        if subscription.isConnected { providers.append("Codex") }
        for kind in InstalledAIKind.managedCLIKinds
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
                Text("Codex and OpenRouter only. Prompts go to a search engine.")
            }
            Picker(selection: $settings.toolRounds) {
                ForEach(AIToolRounds.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiChat, "Tool call rounds")
                Text(
                    "A reply stops after this many; Unlimited runs until Stop. "
                        + "API connections, Codex and Claude.")
            }
        } header: {
            SettingsSectionHeader(.aiChat)
        }
    }

    private var conversationsSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.opensTo) {
                ForEach(AIOpensTo.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Quick AI opens to")
            }
            if settings.opensTo == .recent {
                Picker(selection: $settings.newChatAfter) {
                    ForEach(AINewChatAfter.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.aiConversations, "Start a new conversation after")
                }
            }
            Picker(selection: $settings.retention) {
                ForEach(AIRetention.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Keep conversations")
                Text("Older ones are deleted, except pinned chats.")
            }
            .onChange(of: settings.retention) { core.aiChatCoordinator.applyRetention() }
        } header: {
            SettingsSectionHeader(.aiConversations)
        } footer: {
            Text("Conversations stay on this Mac, outside settings backups.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var systemPromptSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.systemPromptEnabled) {
                SettingsRowTitle(.aiSystemPrompt, "Send a system prompt")
                Text("Off also skips Tinycast's own prompt.")
            }
            SystemPromptEditor(text: $settings.systemPrompt)
                .settingsEnabled(settings.systemPromptEnabled)
        } header: {
            SettingsSectionHeader(.aiSystemPrompt)
        } footer: {
            Text("Sent before every message, after Tinycast's own. Both are billed each turn.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var providersPanel: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            SettingsEditorHeader(
                title: "AI Providers",
                subtitle: "Use an installed account or connect an API endpoint."
            )
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)

            Form {
                installedAISection
                apiConnectionsSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack(spacing: Theme.Spacing.md) {
                Button("Done") { providersPresented = false }
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: Theme.Size.editorSheetWidth, height: 600)
        .settingsEditorPanelSurface()
        .settingsEditorPanel(item: $editor) { target in
            AIConnectionEditorPanel(
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
            installedConnection(.cursor)
        } header: {
            SettingsSectionHeader(.aiInstalledAI)
        } footer: {
            Text("Uses the command-line tools signed in on this Mac. Their keys are never stored.")
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
                    Text(readyDetail(kind, status))
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
            Text("Presets or any OpenAI-compatible endpoint. Keys stay in your login Keychain.")
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
        for kind in InstalledAIKind.managedCLIKinds {
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

    private func readyDetail(_ kind: InstalledAIKind, _ status: InstalledAIStatus) -> String {
        var parts: [String] = []
        if let version = status.version { parts.append("Version " + version) }
        parts.append(modelCount(status.models))
        if let caveat = kind.isolationCaveat(
            hasManagedMCPPolicy: InstalledAIManager.hasManagedMCPPolicy)
        {
            parts.append(caveat)
        }
        return parts.joined(separator: " · ")
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
