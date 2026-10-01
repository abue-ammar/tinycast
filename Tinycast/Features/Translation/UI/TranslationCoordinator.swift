import Foundation
import Observation

@MainActor
@Observable
final class TranslationCoordinator {
    private struct Configuration: Equatable {
        let provider: TranslationProvider
        let model: AIModelSelection?
        let source: String
        let target: String
        let plan: DeepLPlan
        let connection: AIConnection?
        let routeEnabled: Bool
        let apiKeyRevision: Int
        let deepLKeyRevision: Int
    }

    let settings: TranslationSettingsStore
    let session: TranslationSession
    private(set) var text = ""
    private(set) var isComposing = false
    private(set) var hasDeepLKey = false
    private(set) var isLoadingLanguages = false
    private(set) var languageError: String?
    private(set) var menuRevision = 0

    private let ai: AISettingsStore
    private let subscription: ChatGPTSubscriptionManager
    private let installedAI: InstalledAIManager
    private let keyStore: KeychainSecretStore
    private let deepLService: () -> DeepLTranslationService
    private let showPalette: () -> Void
    private let showSettings: () -> Void
    private let showMessage: (String, DialogTone) -> Void
    private let confirmRemoval: (DeepLPlan) async -> Bool
    private var deepLLanguages: [TranslationLanguage] = []
    private var keyReadError: String?

    @ObservationIgnored private lazy var aiLanguages = TranslationLanguages.ai(locale: .current)
    @ObservationIgnored private var catalogs: [DeepLPlan: [TranslationLanguage]] = [:]
    @ObservationIgnored private var languageTask: Task<Void, Never>?
    @ObservationIgnored private var removalTask: Task<Void, Never>?
    @ObservationIgnored private var languageGeneration = 0
    @ObservationIgnored private var deepLKeyRevision = 0
    @ObservationIgnored private var keyPlan: DeepLPlan?
    @ObservationIgnored private var appliedConfiguration: Configuration?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var resourcesPrepared = false
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var pendingTranslation = false
    @ObservationIgnored private var languageCompletionMayTranslate = false

    init(
        settings: TranslationSettingsStore, session: TranslationSession,
        ai: AISettingsStore, subscription: ChatGPTSubscriptionManager,
        installedAI: InstalledAIManager,
        deepLService: @escaping () -> DeepLTranslationService,
        showPalette: @escaping () -> Void, openSettings: @escaping () -> Void,
        showMessage: @escaping (String, DialogTone) -> Void,
        confirmRemoval: @escaping (DeepLPlan) async -> Bool,
        keyStore: KeychainSecretStore = .translationDeepLKeys
    ) {
        self.settings = settings
        self.session = session
        self.ai = ai
        self.subscription = subscription
        self.installedAI = installedAI
        self.deepLService = deepLService
        self.showPalette = showPalette
        showSettings = openSettings
        self.showMessage = showMessage
        self.confirmRemoval = confirmRemoval
        self.keyStore = keyStore
        appliedConfiguration = configuration
    }

    isolated deinit {
        languageTask?.cancel()
        removalTask?.cancel()
    }

    var sourceLanguages: [TranslationLanguage] { languages.filter(\.usableAsSource) }
    var targetLanguages: [TranslationLanguage] { languages.filter(\.usableAsTarget) }

    var sourceLabel: String {
        guard sourceLanguage == nil else { return languageName(settings.sourceLanguage) }
        guard let detected = matchingResult?.detectedSourceLanguage else { return "Detect Language" }
        return "\(languageName(detected)) (Detected)"
    }

    var targetLabel: String { languageName(settings.targetLanguage) }

    var serviceLabel: String {
        switch settings.provider {
        case .ai: settings.model.map { "AI · \($0.model)" } ?? "AI (BYOK)"
        case .deepl: "DeepL \(settings.deepLPlan.title)"
        }
    }

    var modelGroups: [AIModelOptionGroup] {
        AIModelOption.availableGroups(
            settings: ai, subscription: subscription, installedAI: installedAI
        ).compactMap { group in
            guard case .api = group.source else { return nil }
            var group = group
            let source = group.source
            group.options.removeAll { !ai.isModelShown($0.selection.model, in: source) }
            return group.options.isEmpty ? nil : group
        }
    }

    var efforts: [ChatGPTSubscription.Effort] {
        AIModelOption.efforts(
            for: settings.model, settings: ai, subscription: subscription, installedAI: installedAI)
    }

    var configurationIssue: String? {
        switch settings.provider {
        case .ai:
            guard let model = settings.model else { return Self.setupMessage }
            guard case .api(let id, let name, _) = model,
                ai.connection(id: id)?.models.contains(name) == true,
                ai.isRouteEnabled(.api(id))
            else { return "Choose an available AI model in Translation Settings." }
        case .deepl:
            if let keyReadError { return keyReadError }
            guard keyPlan == settings.deepLPlan, hasDeepLKey else { return Self.setupMessage }
            guard !deepLLanguages.isEmpty else { return nil }
        }
        return TranslationLanguages.supports(request, in: languages)
            ? nil : "Choose a supported language pair."
    }

    var canCopy: Bool { matchingResult != nil }

    var canSwap: Bool { !isComposing && swappedLanguages != nil }

    var canRetry: Bool {
        guard !isComposing, !isLoadingLanguages else { return false }
        if settings.provider == .deepl, hasDeepLKey, languageError != nil { return true }
        guard case .failed = session.state else { return false }
        return hasText && canTranslate
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        appliedConfiguration = configuration
        trackConfiguration()
    }

    func show() { showPalette() }

    func setText(_ text: String, isComposing: Bool) {
        guard self.text != text || self.isComposing != isComposing else { return }
        self.text = text
        self.isComposing = isComposing
        invalidateDraft()
        schedulePending()
    }

    func setSourceLanguage(_ code: String) {
        guard let code = TranslationSettingsStore.sourceCode(code), settings.sourceLanguage != code
        else { return }
        settings.sourceLanguage = code
        reconcileConfiguration()
    }

    func setTargetLanguage(_ code: String) {
        guard let code = TranslationSettingsStore.targetCode(code), settings.targetLanguage != code
        else { return }
        settings.targetLanguage = code
        reconcileConfiguration()
    }

    func selectProvider(_ provider: TranslationProvider) {
        guard settings.provider != provider else { return }
        settings.provider = provider
        reconcileConfiguration()
    }

    func selectModel(_ model: AIModelSelection?) {
        if let model {
            guard case .api = model else { return }
        }
        let selection = resolvedModel(model)
        guard settings.model != selection else { return }
        settings.select(selection)
        reconcileConfiguration()
    }

    func setDeepLPlan(_ plan: DeepLPlan) {
        guard settings.deepLPlan != plan else { return }
        settings.deepLPlan = plan
        reconcileConfiguration()
    }

    @discardableResult
    func saveDeepLKey(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        let plan = settings.deepLPlan
        do {
            try keyStore.setSecret(key, for: plan.account)
        } catch {
            showMessage("The DeepL API key could not be saved to Keychain.", .danger)
            return false
        }
        keyChanged(plan: plan, isPresent: true)
        return true
    }

    func removeDeepLKey() {
        guard removalTask == nil, hasDeepLKey, keyPlan == settings.deepLPlan else { return }
        let plan = settings.deepLPlan
        let revision = deepLKeyRevision
        let confirm = confirmRemoval
        removalTask = Task { [weak self] in
            defer { self?.removalTask = nil }
            guard await confirm(plan), !Task.isCancelled, let self,
                self.settings.deepLPlan == plan, self.deepLKeyRevision == revision,
                self.keyPlan == plan, self.hasDeepLKey
            else { return }
            do {
                try self.keyStore.removeSecret(for: plan.account)
            } catch {
                self.showMessage("The DeepL API key could not be removed from Keychain.", .danger)
                return
            }
            self.keyChanged(plan: plan, isPresent: false)
        }
    }

    func swap() {
        guard !isComposing, let pair = swappedLanguages else { return }
        let translated = matchingResult?.text
        settings.sourceLanguage = pair.source
        settings.targetLanguage = pair.target
        if let translated { text = translated }
        appliedConfiguration = configuration
        invalidateDraft()
        schedulePending()
    }

    func retry() {
        guard canRetry else { return }
        if settings.provider == .deepl, languageError != nil {
            languageError = nil
            pendingTranslation = hasText
            ensureLanguages(allowTranslation: isActive)
            return
        }
        guard isActive else { return }
        scheduleCurrent(immediately: true)
    }

    func clear() {
        text = ""
        isComposing = false
        invalidateDraft()
    }

    func copyTranslation() {
        guard let result = matchingResult else { return }
        Paster.copyPlainText(result.text)
        showMessage("Translation copied.", .success)
    }

    func openSettings() {
        showSettings()
    }

    func prepareSettings() {
        resourcesPrepared = true
        languageCompletionMayTranslate = false
        reconcileConfiguration(schedule: false)
        readKeyPresence()
        ensureLanguages(allowTranslation: false)
    }

    func activate() {
        guard !isActive else { return }
        reconcileConfiguration(schedule: false)
        isActive = true
        resourcesPrepared = true
        if settings.provider == .deepl {
            readKeyPresence()
            ensureLanguages(allowTranslation: true)
        }
        schedulePending()
    }

    func suspend() {
        if session.state == .waiting || session.state == .translating {
            pendingTranslation = hasText
        }
        isActive = false
        session.cancel()
        cancelLanguageLoad()
    }

    func reset() {
        isActive = false
        pendingTranslation = false
        text = ""
        isComposing = false
        session.reset()
        cancelLanguageLoad()
        languageError = nil
        menuRevision += 1
    }

    func chooseServiceModel(_ model: AIModelSelection) {
        guard case .api = model else { return }
        let selection: AIModelSelection?
        if let current = settings.model, current.source == model.source, current.model == model.model {
            selection = current
        } else {
            selection = resolvedModel(model)
        }
        guard settings.provider != .ai || settings.model != selection else { return }
        settings.provider = .ai
        settings.select(selection)
        reconcileConfiguration()
    }

    private static let setupMessage = "Choose an AI model or add a DeepL API key."

    private var sourceLanguage: String? {
        TranslationLanguages.matches(settings.sourceLanguage, "auto") ? nil : settings.sourceLanguage
    }

    private var request: TranslationRequest {
        TranslationRequest(text: text, sourceLanguage: sourceLanguage, targetLanguage: settings.targetLanguage)
    }

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var languages: [TranslationLanguage] {
        settings.provider == .ai ? aiLanguages : deepLLanguages
    }

    private var canTranslate: Bool {
        configurationIssue == nil && TranslationLanguages.supports(request, in: languages)
            && (settings.provider != .deepl || (!isLoadingLanguages && languageError == nil))
    }

    private var matchingResult: TranslationResult? {
        guard !isComposing, session.state == .completed,
            session.successfulRequest == request, session.successfulGeneration != nil,
            appliedConfiguration == configuration, canTranslate
        else { return nil }
        return session.result
    }

    private var swappedLanguages: (source: String, target: String)? {
        TranslationLanguages.swapped(
            source: sourceLanguage, target: settings.targetLanguage,
            detectedSource: matchingResult?.detectedSourceLanguage, in: languages)
    }

    private var configuration: Configuration {
        let connectionID: UUID?
        if settings.provider == .ai, case .api(let id, _, _) = settings.model {
            connectionID = id
        } else {
            connectionID = nil
        }
        return Configuration(
            provider: settings.provider, model: settings.model,
            source: settings.sourceLanguage, target: settings.targetLanguage, plan: settings.deepLPlan,
            connection: connectionID.flatMap { ai.connection(id: $0) },
            routeEnabled: connectionID.map { ai.isRouteEnabled(.api($0)) } ?? false,
            apiKeyRevision: connectionID.flatMap { ai.apiKeyRevisions[$0] } ?? 0,
            deepLKeyRevision: deepLKeyRevision)
    }

    private func resolvedModel(_ model: AIModelSelection?) -> AIModelSelection? {
        guard let model else { return nil }
        guard model.effort == nil,
            settings.model?.source != model.source || settings.model?.model != model.model
        else { return model }
        return AIModelOption.withDefaultEffort(
            model, settings: ai, subscription: subscription, installedAI: installedAI)
    }

    private func languageName(_ code: String) -> String {
        languages.first { TranslationLanguages.matches($0.id, code) }?.name
            ?? Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func trackConfiguration() {
        withObservationTracking {
            _ = settings.provider
            _ = settings.model
            _ = settings.sourceLanguage
            _ = settings.targetLanguage
            _ = settings.deepLPlan
            _ = ai.connections
            _ = ai.disabledRoutes
            _ = ai.shownModels
            _ = ai.apiKeyRevisions
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.trackConfiguration()
                self.menuRevision += 1
                self.reconcileConfiguration()
            }
        }
    }

    private func reconcileConfiguration(schedule: Bool = true) {
        let next = configuration
        guard next != appliedConfiguration else { return }
        let previous = appliedConfiguration
        appliedConfiguration = next
        if previous?.plan != next.plan {
            cancelLanguageLoad()
            deepLLanguages = []
            languageError = nil
            keyPlan = nil
            hasDeepLKey = false
            keyReadError = nil
        } else if previous?.provider != next.provider {
            cancelLanguageLoad()
            languageError = nil
        }
        invalidateDraft()
        if resourcesPrepared {
            if keyPlan != settings.deepLPlan { readKeyPresence() }
            ensureLanguages(allowTranslation: schedule)
        }
        if schedule { schedulePending() }
    }

    private func invalidateDraft() {
        session.reset()
        pendingTranslation = hasText
        menuRevision += 1
    }

    private func schedulePending() {
        guard pendingTranslation, isActive, !isComposing, hasText else { return }
        languageCompletionMayTranslate = true
        guard canTranslate else { return }
        scheduleCurrent(immediately: false)
    }

    private func scheduleCurrent(immediately: Bool) {
        let snapshot = configuration
        let input = request
        pendingTranslation = false
        let operation: @MainActor (TranslationRequest) async throws -> TranslationResult = { [weak self] input in
            guard let self else { throw CancellationError() }
            return try await self.translate(input, configuration: snapshot)
        }
        if immediately {
            session.retry(input, using: operation)
        } else {
            session.schedule(input, using: operation)
        }
    }

    private func translate(
        _ input: TranslationRequest, configuration snapshot: Configuration
    ) async throws -> TranslationResult {
        try Task.checkCancellation()
        guard isActive, !isComposing, request == input, configuration == snapshot, canTranslate
        else { throw CancellationError() }
        if let source = input.sourceLanguage,
            TranslationLanguages.matches(source, input.targetLanguage)
        {
            return TranslationResult(text: input.text, detectedSourceLanguage: source)
        }
        let result: TranslationResult
        switch snapshot.provider {
        case .ai:
            guard let selection = snapshot.model, case .api = selection else {
                throw AIProviderError.unavailable(Self.setupMessage)
            }
            let provider = try AIProviderFactory.make(
                selection: selection, settings: ai, subscription: subscription, installedAI: installedAI)
            result = try await AITranslationService.translate(input, using: provider)
        case .deepl:
            let key = try deepLKey(for: snapshot.plan)
            result = try await deepLService().translate(input, plan: snapshot.plan, apiKey: key)
        }
        try Task.checkCancellation()
        guard isActive, !isComposing, request == input, configuration == snapshot, canTranslate
        else { throw CancellationError() }
        return result
    }

    private func readKeyPresence() {
        let plan = settings.deepLPlan
        do {
            let present = try keyStore.hasSecret(for: plan.account)
            if keyPlan == plan, hasDeepLKey != present {
                catalogs[plan] = nil
                cancelLanguageLoad()
                deepLLanguages = []
                languageError = nil
                invalidateDraft()
            }
            keyPlan = plan
            hasDeepLKey = present
            keyReadError = nil
        } catch {
            keyReadError = "The DeepL API key could not be read from Keychain."
            if settings.provider == .deepl { invalidateDraft() }
        }
        menuRevision += 1
    }

    private func keyChanged(plan: DeepLPlan, isPresent: Bool) {
        resourcesPrepared = true
        deepLKeyRevision += 1
        catalogs[plan] = nil
        cancelLanguageLoad()
        deepLLanguages = []
        languageError = nil
        keyReadError = nil
        keyPlan = plan
        hasDeepLKey = isPresent
        reconcileConfiguration()
    }

    private func deepLKey(for plan: DeepLPlan) throws -> String {
        let key: String?
        do {
            key = try keyStore.secret(for: plan.account)
        } catch {
            throw AIProviderError.unavailable("The DeepL API key could not be read from Keychain.")
        }
        guard let key, !key.isEmpty else {
            throw AIProviderError.unavailable(Self.setupMessage)
        }
        return key
    }

    private func cancelLanguageLoad() {
        languageGeneration += 1
        languageTask?.cancel()
        languageTask = nil
        isLoadingLanguages = false
        languageCompletionMayTranslate = false
    }

    private func ensureLanguages(allowTranslation: Bool) {
        if allowTranslation, isActive { languageCompletionMayTranslate = true }
        guard settings.provider == .deepl, keyPlan == settings.deepLPlan, hasDeepLKey,
            keyReadError == nil, !isLoadingLanguages, languageError == nil
        else { return }
        let plan = settings.deepLPlan
        if let cached = catalogs[plan] {
            if deepLLanguages != cached {
                deepLLanguages = cached
                menuRevision += 1
            }
            return
        }
        let key: String
        do {
            key = try deepLKey(for: plan)
        } catch {
            languageError = error.localizedDescription
            menuRevision += 1
            return
        }
        languageGeneration += 1
        let mine = languageGeneration
        let service = deepLService()
        isLoadingLanguages = true
        menuRevision += 1
        languageTask = Task { [weak self] in
            do {
                let languages = try await service.languages(plan: plan, apiKey: key)
                try Task.checkCancellation()
                guard let self, self.languageGeneration == mine else { return }
                let localized = TranslationLanguages.localized(languages, locale: .current)
                self.catalogs[plan] = localized
                self.deepLLanguages = localized
                self.isLoadingLanguages = false
                self.languageTask = nil
                self.menuRevision += 1
                if self.languageCompletionMayTranslate { self.schedulePending() }
            } catch {
                guard !Task.isCancelled, let self, self.languageGeneration == mine else { return }
                self.languageTask = nil
                self.isLoadingLanguages = false
                if !(error is CancellationError) { self.languageError = error.localizedDescription }
                self.menuRevision += 1
            }
        }
    }
}
