import AppKit
import SwiftUI

/// One entry of the Providers list: the on-device model, an installed command, or an API connection.
enum AIProviderRoute: Hashable {
    case appleIntelligence
    case installed(InstalledAIKind)
    case api(UUID)

    var source: AIModelSource {
        switch self {
        case .appleIntelligence: return .appleIntelligence
        case .installed(let kind): return kind.source
        case .api(let id): return .api(id)
        }
    }
}

/// One page of a provider's detail; a route lists only the pages it has something to put on.
enum AIProviderTab: String, CaseIterable, Identifiable {
    case overview
    case models
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .models: return "Models"
        case .advanced: return "Advanced"
        }
    }

    static func tabs(for route: AIProviderRoute) -> [AIProviderTab] {
        switch route {
        case .appleIntelligence: return [.overview]
        case .installed: return [.overview, .models, .advanced]
        case .api: return [.overview, .models]
        }
    }
}

/// Settings → AI → Providers: every route in a list, the selected one's pages beside it.
struct AIProvidersPanel: View {
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    let onDone: () -> Void

    @State private var selection: AIProviderRoute?
    @State private var keyStatuses: [UUID: Bool] = [:]
    @State private var keyError = false
    @State private var editor: AIConnectionEditorTarget?
    @State private var pendingRemoval: AIConnection?
    @State private var modelQuery = ""
    /// Kept across providers, as Mail keeps its tab across accounts; one without it shows Overview.
    @State private var tab = AIProviderTab.overview

    private let keyStore = KeychainSecretStore.aiAPIKeys

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "AI Providers",
                subtitle: "Installed tools, API connections, and the models each one offers."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: Theme.Size.aiProvidersList)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Stated, never intrinsic: selecting a longer provider must not resize the panel.
            .frame(height: Theme.Size.aiProvidersPanel.height)
            Divider()
            HStack {
                Spacer(minLength: 0)
                Button("Done", action: onDone)
                    .buttonStyle(.modalAction(.primary, fillsWidth: false))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .frame(width: Theme.Size.aiProvidersPanel.width)
        .settingsEditorPanelSurface(controlsOnGlass: false)
        .releasesFocusOnOutsideClick()
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
            selection = selection ?? initialSelection
            loadKeyStatuses()
            core.applyInstalledAILifecycle()
        }
        .onChange(of: selection) { modelQuery = "" }
        .onChange(of: settings.connections.map(\.id)) { _, ids in
            if case .api(let id) = selection, !ids.contains(id) { selection = .installed(.codex) }
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("On This Mac") {
                    listRow(.appleIntelligence)
                }
                Section("Installed") {
                    ForEach(InstalledAIKind.allCases) { listRow(.installed($0)) }
                }
                Section("API Connections") {
                    if settings.connections.isEmpty {
                        Text("None yet")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                    ForEach(settings.connections) { listRow(.api($0.id)) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            listActions
        }
    }

    private func listRow(_ route: AIProviderRoute) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            AIProviderTile(icon: icon(for: route))
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(for: route))
                    .lineLimit(1)
                Text(caption(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .tag(route)
    }

    /// Mail's Accounts list: add below the list, and remove whatever it has selected.
    private var listActions: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Menu {
                ForEach(AIProviderKind.allCases) { provider in
                    Button(provider.title) {
                        editor = AIConnectionEditorTarget(
                            connection: AIConnection(provider: provider),
                            hasStoredKey: false, isNew: true)
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add API Connection")
            .accessibilityLabel("Add API Connection")
            Button {
                pendingRemoval = selectedConnection
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(selectedConnection == nil)
            .help("Remove API Connection")
            .accessibilityLabel("Remove API Connection")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .appleIntelligence?:
            detailForm(.appleIntelligence) { _ in appleIntelligenceSections }
        case .installed(let kind)?:
            detailForm(.installed(kind)) { installedSections(kind, tab: $0) }
        case .api(let id)?:
            if let connection = settings.connection(id: id) {
                detailForm(.api(id)) { connectionSections(connection, tab: $0) }
            }
        case nil:
            ContentUnavailableView("Select a provider", systemImage: "sparkles")
        }
    }

    private func detailForm<Content: View>(
        _ route: AIProviderRoute, @ViewBuilder content: (AIProviderTab) -> Content
    ) -> some View {
        let tabs = AIProviderTab.tabs(for: route)
        let shown = tabs.contains(tab) ? tab : .overview
        return VStack(spacing: 0) {
            detailHeader(route)
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.xl)
            if tabs.count > 1 {
                Picker("Page", selection: $tab) {
                    ForEach(tabs) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .padding(.top, Theme.Spacing.xl)
            }
            Form { content(shown) }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
        .id(route)
    }

    private func detailHeader(_ route: AIProviderRoute) -> some View {
        HStack(spacing: Theme.Spacing.xl) {
            AIProviderTile(icon: icon(for: route), size: Theme.Size.settingsRowIcon * 1.5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(for: route))
                    .font(Theme.Typography.panelTitle)
                    .lineLimit(1)
                Text(kindCaption(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.lg)
            switch route {
            case .installed(let kind):
                if let version = installedAI.status(for: kind).version,
                    settings.enabledInstalledProviders.contains(kind)
                {
                    Text("v" + version)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            case .api(let id):
                if let connection = settings.connection(id: id) {
                    Button("Edit…") { edit(connection) }
                }
            case .appleIntelligence:
                EmptyView()
            }
            routeToggle(route)
        }
    }

    // MARK: On this Mac

    @ViewBuilder
    private var appleIntelligenceSections: some View {
        let available = settings.isAppleIntelligenceAvailable()
        if !settings.isRouteEnabled(.appleIntelligence) { turnedOffSection() }
        Section {
            LabeledContent {
                Text(available ? "Ready" : "Unavailable")
                    .foregroundStyle(.secondary)
            } label: {
                Text(AppleIntelligence.title)
                Text(
                    available
                        ? "Runs on this Mac. Nothing leaves it."
                        : AppleIntelligenceProvider.status().message ?? "Not available on this Mac.")
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Choose the default model on the AI pane.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Installed commands

    @ViewBuilder
    private func installedSections(_ kind: InstalledAIKind, tab: AIProviderTab) -> some View {
        let isOn = settings.enabledInstalledProviders.contains(kind)
        switch tab {
        case .advanced:
            AIProviderAdvancedSection(kind: kind, detected: isOn ? executable(for: kind) : nil)
        case .overview, .models:
            if !isOn {
                turnedOffSection(footer: installedFooter(kind))
            } else if tab == .models {
                modelsSection(route: .installed(kind), models: installedModels(kind))
            } else {
                Section {
                    if kind == .codex {
                        codexStatusRows
                    } else {
                        installedStatusRows(kind)
                    }
                } header: {
                    Text("Status")
                } footer: {
                    Text(installedFooter(kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func turnedOffSection(footer: String? = nil) -> some View {
        Section {
            LabeledContent {
                EmptyView()
            } label: {
                Label("Turned off", systemImage: "pause.circle")
                Text("Tinycast leaves it alone, and its models stay out of every model picker.")
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var codexStatusRows: some View {
        switch subscription.phase {
        case .idle, .starting:
            checkingRow("Codex")
        case .signedOut:
            signInRow(.codex, check: { subscription.refresh() })
        case .connected:
            LabeledContent {
                Button("Refresh") { subscription.refresh() }
            } label: {
                Text("Ready")
                Text(modelCount(subscription.models.count) + " available")
            }
            if let account = subscription.account {
                LabeledContent {
                    Text(account.planTitle == "API key" ? "Codex API key" : "ChatGPT \(account.planTitle)")
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Account")
                    if let email = account.email {
                        RedactedText(
                            value: email,
                            revealHelp: "Click to reveal the signed-in account",
                            hideHelp: "Click to hide the signed-in account")
                    }
                }
            }
            if let limits = subscription.rateLimits {
                if let primary = limits.primary { usageRow(primary, fallbackTitle: "Primary window") }
                if let secondary = limits.secondary {
                    usageRow(secondary, fallbackTitle: "Secondary window")
                }
            }
            if let executable = subscription.executable { commandRow(executable) }
        case .unavailable(let message):
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Install Codex CLI…") { NSWorkspace.shared.open(InstalledAIKind.codex.installURL) }
                    Button("Check Again") { subscription.refresh() }
                }
                .fixedSize()
            } label: {
                Text("Not installed")
                Text(message)
            }
        case .failed(let message):
            failedRow(message, retry: { subscription.refresh() })
        }
    }

    @ViewBuilder
    private func installedStatusRows(_ kind: InstalledAIKind) -> some View {
        let status = installedAI.status(for: kind)
        switch status.phase {
        case .idle, .checking:
            checkingRow(kind.title)
        case .ready:
            LabeledContent {
                Button("Refresh") { installedAI.refresh(kind: kind) }
            } label: {
                Text("Ready")
                Text(modelCount(status.models.count) + " available")
            }
            if let account = status.account { accountRow(account, kind: kind) }
        case .signInRequired:
            signInRow(kind, check: { installedAI.refresh(kind: kind) })
        case .notInstalled:
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Install…") { NSWorkspace.shared.open(kind.installURL) }
                    Button("Check Again") { installedAI.refresh(kind: kind) }
                }
                .fixedSize()
            } label: {
                Text("Not installed")
                Text("Tinycast could not find the \(kind.command) command.")
            }
        case .failed(let message):
            failedRow(message, retry: { installedAI.refresh(kind: kind) })
        }
        if let executable = status.executable { commandRow(executable) }
    }

    private func commandRow(_ executable: URL) -> some View {
        LabeledContent("Command") {
            Text((executable.path as NSString).abbreviatingWithTildeInPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func accountRow(_ account: InstalledAIAccount, kind: InstalledAIKind) -> some View {
        LabeledContent {
            if let plan = account.planTitle {
                Text("\(kind.title) \(plan)").foregroundStyle(.secondary)
            }
        } label: {
            Text("Account")
            if let email = account.email {
                RedactedText(
                    value: email,
                    revealHelp: "Click to reveal the signed-in account",
                    hideHelp: "Click to hide the signed-in account")
            }
        }
    }

    private func executable(for kind: InstalledAIKind) -> URL? {
        kind == .codex ? subscription.executable : installedAI.status(for: kind).executable
    }

    private func checkingRow(_ title: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView().controlSize(.small)
            Text("Checking \(title)…").foregroundStyle(.secondary)
        }
    }

    private func signInRow(_ kind: InstalledAIKind, check: @escaping () -> Void) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Button("Copy Sign-In Command") { copySignInCommand(kind) }
                Button("Check Again", action: check)
            }
            .fixedSize()
        } label: {
            Text("Sign in required")
            Text("Run \(kind.signInCommand) in Terminal, then check again.")
        }
    }

    private func failedRow(_ message: String, retry: @escaping () -> Void) -> some View {
        LabeledContent {
            Button("Try Again", action: retry)
        } label: {
            Label("Check failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
        }
    }

    private func usageRow(
        _ window: ChatGPTSubscription.UsageWindow, fallbackTitle: String
    ) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView(value: Double(window.remainingPercent), total: 100)
                    .frame(width: Theme.Size.aiUsageBar)
                Text("\(window.remainingPercent)% left")
                    .monospacedDigit()
            }
        } label: {
            Text(usageTitle(window, fallback: fallbackTitle))
            if let reset = window.resetsAt {
                Text("Resets \(reset, style: .relative)")
            }
        }
    }

    private func installedFooter(_ kind: InstalledAIKind) -> String {
        kind.isolationCaveat(hasManagedMCPPolicy: InstalledAIManager.hasManagedMCPPolicy)
            ?? "Uses the \(kind.command) command signed in on this Mac. Its keys are never stored."
    }

    private func installedModels(_ kind: InstalledAIKind) -> [ProviderModel] {
        if kind == .codex {
            guard subscription.isConnected else { return [] }
            return subscription.models.map { ProviderModel(id: $0.id, name: $0.name) }
        }
        let status = installedAI.status(for: kind)
        guard status.isReady else { return [] }
        return status.models.map { ProviderModel(id: $0.id, name: $0.name) }
    }

    // MARK: API connections

    @ViewBuilder
    private func connectionSections(
        _ connection: AIConnection, tab: AIProviderTab
    ) -> some View {
        if !settings.isRouteEnabled(.api(connection.id)) { turnedOffSection() }
        if tab == .models {
            modelsSection(
                route: .api(connection.id),
                models: connection.models.map { ProviderModel(id: $0, name: $0) })
        } else {
            connectionSection(connection)
        }
    }

    private func connectionSection(_ connection: AIConnection) -> some View {
        Section {
            LabeledContent("Provider", value: connection.provider.title)
            LabeledContent("Base URL") {
                Text(connection.baseURL)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            LabeledContent("API key") {
                Text(keyStatus(connection))
                    .foregroundStyle(
                        keyIsMissing(connection) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            if keyError {
                Label("The login Keychain could not be accessed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Keys stay in your login Keychain, tied to the endpoint they were saved for.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Models

    @ViewBuilder
    private func modelsSection(route: AIProviderRoute, models: [ProviderModel]) -> some View {
        if models.isEmpty {
            Section {
                Text("Models are listed here once \(title(for: route)) is ready.")
                    .foregroundStyle(.secondary)
            }
        } else {
            let source = route.source
            let shownSet = settings.shownModels[source.storageKey].map(Set.init)
            let shownCount = shownSet.map { set in models.count { set.contains($0.id) } } ?? models.count
            let matches = filtered(models)
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Show All") { settings.showAllModels(in: source) }
                            .disabled(shownCount == models.count)
                        Button("Hide All") { settings.hideAllModels(in: source) }
                    }
                    .fixedSize()
                } label: {
                    Text("\(shownCount) of \(modelCount(models.count)) in the model picker")
                }
                if models.count > Self.filterThreshold {
                    SettingsFilterField(prompt: "Filter models", query: $modelQuery)
                }
                if matches.isEmpty {
                    Text("No model matches “\(modelQuery)”.")
                        .foregroundStyle(.secondary)
                }
                if !matches.isEmpty {
                    AIModelChecklist(
                        items: matches.map { model in
                            AIModelChecklist.Item(
                                id: model.id, title: model.name,
                                isOn: shownSet?.contains(model.id) ?? true,
                                isLocked: isDefault(model.id, route: route))
                        },
                        onToggle: { id, isOn in
                            settings.setModel(
                                id, shown: isOn, in: source, available: models.map(\.id))
                        })
                }
            } footer: {
                Text(
                    "Ticked models appear in the model picker. The default model always does; "
                        + "choose it on the AI pane."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Past a screenful, OpenCode alone lists hundreds, so the list gets the Settings filter row.
    private static let filterThreshold = 8

    private func filtered(_ models: [ProviderModel]) -> [ProviderModel] {
        let query = modelQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private func isDefault(_ model: String, route: AIProviderRoute) -> Bool {
        guard let selection = settings.defaultModel else { return false }
        return selection.source == route.source && selection.model == model
    }

    // MARK: - Titles and glyphs

    private func title(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence: return AppleIntelligence.title
        case .installed(let kind): return kind.title
        case .api(let id): return settings.connection(id: id)?.title ?? "API Connection"
        }
    }

    private func kindCaption(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence: return "On this Mac · No account needed"
        case .installed(let kind): return "Installed command · \(kind.command)"
        case .api(let id):
            return "API connection · " + (settings.connection(id: id)?.provider.title ?? "")
        }
    }

    /// The one line a reader scans the list for: is it usable, and if not, why.
    private func caption(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence:
            guard settings.isRouteEnabled(.appleIntelligence) else { return "Off" }
            return settings.isAppleIntelligenceAvailable() ? "Ready · Runs on this Mac" : "Unavailable"
        case .installed(let kind):
            guard settings.enabledInstalledProviders.contains(kind) else { return "Off" }
            return kind == .codex ? codexCaption : installedCaption(kind)
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return "" }
            guard settings.isRouteEnabled(.api(id)) else { return "Off" }
            if keyIsMissing(connection) { return "Key missing" }
            let count = modelCount(connection.models.count)
            return connection.name.isEmpty ? count : "\(connection.provider.title) · \(count)"
        }
    }

    private var codexCaption: String {
        switch subscription.phase {
        case .idle, .starting: return "Checking…"
        case .signedOut: return "Sign in required"
        case .unavailable: return "Not installed"
        case .failed: return "Check failed"
        case .connected:
            let count = modelCount(subscription.models.count)
            guard let account = subscription.account else { return count }
            let plan = account.planTitle == "API key" ? "API key" : "ChatGPT \(account.planTitle)"
            return "\(plan) · \(count)"
        }
    }

    private func installedCaption(_ kind: InstalledAIKind) -> String {
        let status = installedAI.status(for: kind)
        switch status.phase {
        case .idle, .checking: return "Checking…"
        case .ready: return "Ready · " + modelCount(status.models.count)
        case .signInRequired: return "Sign in required"
        case .notInstalled: return "Not installed"
        case .failed: return "Check failed"
        }
    }

    private func icon(for route: AIProviderRoute) -> PopoverMenuIcon {
        switch route {
        case .appleIntelligence: return AIModelOption.appleIntelligenceIcon
        case .installed(.codex): return .asset(AIBrand.openAI.assetName)
        case .installed(.claude): return .asset(AIBrand.claude.assetName)
        case .installed(.grok): return .asset(AIBrand.grok.assetName)
        case .installed(.openCode): return .asset(AIBrand.openCode.assetName)
        case .installed(.cursor): return AIModelOption.cursorIcon
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return .symbol("sparkles") }
            // OpenRouter is its own brand; resolving by model would show whichever vendor came first.
            if connection.provider == .openRouter { return .asset(AIBrand.openRouter.assetName) }
            return AIModelOption.icon(
                AIBrand.resolve(provider: connection.provider, model: connection.models.first ?? ""))
        }
    }

    private func modelCount(_ count: Int) -> String {
        count == 1 ? "1 model" : "\(count) models"
    }

    // MARK: - Actions

    /// Opens on whichever route the default model uses, since that is the one most often checked.
    private var initialSelection: AIProviderRoute {
        switch settings.defaultModel?.source {
        case .appleIntelligence?: return .appleIntelligence
        case .api(let id)?: return .api(id)
        case let source?:
            return source.installedKind.map(AIProviderRoute.installed) ?? .installed(.codex)
        case nil: return .installed(.codex)
        }
    }

    private var selectedConnection: AIConnection? {
        guard case .api(let id) = selection else { return nil }
        return settings.connection(id: id)
    }

    private func routeToggle(_ route: AIProviderRoute) -> some View {
        Toggle(
            "Enable \(title(for: route))",
            isOn: Binding(
                get: { settings.isRouteEnabled(route.source) },
                set: { settings.setRoute(route.source, enabled: $0) })
        )
        .labelsHidden()
        .toggleStyle(.switch)
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } })
    }

    private func keyIsMissing(_ connection: AIConnection) -> Bool {
        keyStatuses[connection.id] != true && !AIEndpointPolicy.isLoopback(connection.baseURL)
    }

    private func keyStatus(_ connection: AIConnection) -> String {
        if keyStatuses[connection.id] == true { return "Stored in Keychain" }
        return AIEndpointPolicy.isLoopback(connection.baseURL) ? "None needed locally" : "Missing"
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
            selection = .api(connection.id)
            loadKeyStatuses()
            settings.reconcile(subscription: subscription, installedAI: installedAI)
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

    private func usageTitle(
        _ window: ChatGPTSubscription.UsageWindow, fallback: String
    ) -> String {
        guard let minutes = window.durationMinutes else { return fallback }
        if minutes >= 1_440 { return "\(minutes / 1_440)-day window" }
        if minutes >= 60 { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
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

/// A model row's content, whichever of the three catalogue shapes it came from.
private struct ProviderModel: Identifiable {
    let id: String
    let name: String
}

/// The list and header glyph: a brand mark or symbol on the tile `SettingsTabIcon` draws.
private struct AIProviderTile: View {
    let icon: PopoverMenuIcon
    var size = Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2

    var body: some View {
        let scale = size / (Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2)
        glyph
            .frame(
                width: Theme.Size.settingsSidebarGlyph * scale,
                height: Theme.Size.settingsSidebarGlyph * scale
            )
            .foregroundStyle(.primary)
            .padding(Theme.Spacing.xs * scale)
            .background(
                Theme.Colors.controlSurface,
                in: RoundedRectangle(
                    cornerRadius: Theme.Radius.thumbnail * scale, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .asset(let name):
            Image(name).resizable().renderingMode(.template).scaledToFit()
        case .symbol(let name):
            Image(systemName: name).resizable().scaledToFit()
        case .file, .thumbnail, .blank:
            Image(systemName: "sparkles").resizable().scaledToFit()
        }
    }
}

extension AISettingsStore {
    /// Moves the default model off any route that just went away, or onto its current catalogue.
    func reconcile(subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager) {
        let enabled = enabledInstalledProviders
        reconcile(
            codexModels: enabled.contains(.codex) ? subscription.models : [],
            isUnavailable: !enabled.contains(.codex) || subscription.phase == .signedOut
                || subscription.phase.isUnavailable)
        for kind in InstalledAIKind.managedCLIKinds {
            let status = installedAI.status(for: kind)
            reconcile(
                installed: kind,
                models: enabled.contains(kind) ? status.models : [],
                isUnavailable: !enabled.contains(kind) || status.phase == .signInRequired
                    || status.phase == .notInstalled)
        }
    }
}
