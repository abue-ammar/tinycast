import AppKit

/// Owns AI transforms: the library, the one run funnel with its gate, and a deletion's cleanup.
@MainActor
final class AITransformCoordinator {
    private static let maxSelectionLength = 20_000

    private let store: AITransformStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: AITransformSession
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let delivery: AITextDelivery
    /// Dialog and message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore

    /// One transform in flight at a time: two overlapping runs would race for the same selection.
    private var isTransforming = false
    init(
        store: AITransformStore,
        settings: AppSettings,
        appIndex: AppIndex,
        session: AITransformSession,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        delivery: AITextDelivery,
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.delivery = delivery
        self.core = core
    }

    // MARK: - Feature presence

    func applyPresence() {
        let visible = settings.aiTransformsEnabled && settings.aiTransformsShowInLauncher
        appIndex.setAITransforms(visible ? store.transforms : [])
    }

    // MARK: - Library

    func addTransform(_ draft: AITransform) throws -> AITransform {
        try store.add(draft)
    }

    func updateTransform(_ draft: AITransform) throws {
        try store.update(draft)
    }

    func deleteTransform(id: UUID) {
        guard let transform = store.transform(id: id) else { return }
        removeTransformReferences(ids: [id], entryIDs: [transform.entryID])
        store.remove(id: id)
    }

    @discardableResult
    func replaceTransforms(_ transforms: [AITransform]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.transforms.map { ($0.id, $0) })
        let count = store.replace(with: transforms)
        let liveIDs = Set(store.transforms.map(\.id))
        let removed = Set(previous.keys).subtracting(liveIDs)
        let removedEntryIDs = Set(removed.compactMap { previous[$0]?.entryID })
        removeTransformReferences(ids: removed, entryIDs: removedEntryIDs)
        return count
    }

    // MARK: - Running

    struct ResolvedConfig {
        let account: AIProviderAccount
        let key: String
        let baseURL: URL
        let model: String
        let reasoning: AIReasoningEffort?
        let mode: AIExecutionMode
        let action: AICompletionAction
    }
    func resolveConfig(for transform: AITransform) async -> ResolvedConfig? {
        guard
            let account = transform.providerAccountID.flatMap(core.aiProviderAccounts.account(id:))
                ?? core.aiProviderAccounts.defaultAccount
        else { return nil }

        let key: String
        if account.isOAuth {
            key = (try? await ChatGPTOAuthService.shared.validAccessToken()) ?? ""
        } else {
            key =
                SecretStore.secret(account: account.secretAccountKey)
                ?? SecretStore.secret(account: SecretStore.aiAPIKeyAccount)
                ?? ""
        }

        guard account.isLocal || !key.isEmpty else { return nil }

        guard
            let baseURL = AICompletionRequest.endpointURL(
                fromBase: account.baseURL, path: "/chat/completions"),
            baseURL.host != nil
        else { return nil }

        let rawModel =
            transform.model
            ?? (account.defaultModel.isEmpty
                ? (settings.aiModel.isEmpty ? AIClient.defaultModel : settings.aiModel)
                : account.defaultModel)
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }

        let reasoning =
            transform.reasoningEffort ?? (account.defaultReasoning == .none ? nil : account.defaultReasoning)
        let mode = transform.activationMode ?? settings.aiExecutionMode
        let action = transform.completionAction ?? settings.aiCompletionAction

        return ResolvedConfig(
            account: account,
            key: key,
            baseURL: baseURL,
            model: model,
            reasoning: reasoning,
            mode: mode,
            action: action
        )
    }

    /// Launcher activation: opens interactive preview window or executes directly based on execution mode setting.
    func launchTransform(id: UUID) {
        runTransform(id: id)
    }

    /// The one funnel for transform execution (interactive window or direct background).
    func runTransform(id: UUID) {
        guard settings.aiTransformsEnabled else { return }
        guard let transform = store.transform(id: id) else { return }
        Task {
            guard let config = await resolveConfig(for: transform) else {
                await presentFailure(.notConfigured, transform: transform)
                return
            }
            if config.mode == .interactive {
                openInteractiveSession(transform: transform, config: config)
            } else {
                runTransformDirect(transform: transform, config: config)
            }
        }
    }

    /// Opens the interactive transformation session inside Tinycast's palette window.
    private func openInteractiveSession(transform: AITransform, config: ResolvedConfig) {
        let target = paletteCoordinator.targetApp
        Permissions.ensureAccessibility()
        let selection = target.flatMap({ AccessibilityText.selection(in: $0) }) ?? ""

        session.begin(
            preset: transform,
            selection: selection,
            targetApp: target,
            defaultModel: config.model,
            reasoning: config.reasoning,
            apiKey: config.key,
            baseURL: config.account.baseURL
        )
        paletteCoordinator.showPalette(mode: .aiTransform)
    }

    private func runTransformDirect(transform: AITransform, config: ResolvedConfig) {
        guard !isTransforming else {
            core.showMessage("Already transforming", tone: .neutral)
            return
        }
        let target = paletteCoordinator.targetApp
        Permissions.ensureAccessibility()
        guard let selection = target.flatMap({ AccessibilityText.selection(in: $0) }),
            !selection.isEmpty
        else {
            core.showMessage("No selection found", tone: .danger)
            return
        }
        guard selection.count <= Self.maxSelectionLength else {
            Task {
                await core.reportFailure(
                    title: "Selection Too Long",
                    message:
                        "AI transforms handle up to \(Self.maxSelectionLength) characters; this "
                        + "selection is \(selection.count).",
                    symbol: AITransform.sfSymbol, recovery: nil)
            }
            return
        }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        core.showMessage("Transforming…", tone: .neutral)
        isTransforming = true
        Task {
            defer { isTransforming = false }
            let result: String
            do {
                result = try await AIClient.complete(
                    AICompletionRequest(
                        baseURL: config.baseURL,
                        apiKey: config.key,
                        model: config.model,
                        instruction: transform.prompt,
                        selection: selection,
                        reasoningEffort: config.reasoning
                    ))
            } catch {
                let aiError = error as? AIClientError ?? .network(error.localizedDescription)
                await presentFailure(aiError, transform: transform)
                return
            }
            let isBoth = config.action == .both
            if config.action == .copyToClipboard || isBoth {
                Paster.copyPlainText(result)
            }

            if config.action == .overwriteSelection || isBoth {
                let outcome = await delivery.replaceSelection(
                    result, originalSelection: selection, in: target)
                switch outcome {
                case .replaced, .pasted:
                    core.showMessage(
                        isBoth ? "“\(transform.name)” applied & copied" : "“\(transform.name)” applied",
                        tone: .neutral)
                case .copiedToClipboard:
                    core.showMessage(
                        isBoth
                            ? "“\(transform.name)” copied to clipboard"
                            : "Couldn’t paste back — result copied",
                        tone: .neutral)
                case .failed(let message):
                    await core.reportFailure(
                        title: "“\(transform.name)” Failed", message: message,
                        symbol: AITransform.sfSymbol, recovery: nil)
                }
            } else {
                core.showMessage("“\(transform.name)” copied to clipboard", tone: .neutral)
            }
        }
    }
    private func removeTransformReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.aiTransform(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    /// Setup and provider failures that the AI pane can fix offer the jump there.
    private func presentFailure(_ error: AIClientError, transform: AITransform) async {
        let offersSettings: Bool
        switch error {
        case .notConfigured, .invalidBaseURL, .unauthorized:
            offersSettings = true
        case .rateLimited, .provider, .emptyResponse, .network:
            offersSettings = false
        }
        guard
            await core.reportFailure(
                title: "“\(transform.name)” Failed", message: error.localizedDescription,
                symbol: AITransform.sfSymbol, recovery: offersSettings ? "Open Settings…" : nil)
        else { return }
        settingsCoordinator.showSettings(tab: .aiTransforms)
    }
}
