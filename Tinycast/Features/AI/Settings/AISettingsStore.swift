import Foundation
import Observation

@MainActor
@Observable
final class AISettingsStore {
    private let defaults: UserDefaults

    private(set) var connections: [AIConnection] {
        didSet { persistConnections() }
    }
    private(set) var defaultModel: AIModelSelection? {
        didSet { persistDefaultModel() }
    }
    /// Off by default: a prompt reaches a search engine only once the user has said so.
    var webSearchEnabled: Bool {
        didSet { defaults.set(webSearchEnabled, forKey: AppSettingsKey.aiWebSearch.rawValue) }
    }
    /// Appended to `AIInstructions.preamble` on every turn, so it is billed on every turn.
    var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: AppSettingsKey.aiSystemPrompt.rawValue) }
    }
    /// On by default: without it a model has no idea what app it is answering for.
    var systemPromptEnabled: Bool {
        didSet {
            defaults.set(systemPromptEnabled, forKey: AppSettingsKey.aiSystemPromptEnabled.rawValue)
        }
    }
    /// Forever by default, so upgrading deletes nothing the reader did not ask to lose.
    var retention: AIRetention {
        didSet { defaults.set(retention.rawValue, forKey: AppSettingsKey.aiRetention.rawValue) }
    }
    var opensTo: AIOpensTo {
        didSet { defaults.set(opensTo.rawValue, forKey: AppSettingsKey.aiOpensTo.rawValue) }
    }
    var newChatAfter: AINewChatAfter {
        didSet {
            defaults.set(newChatAfter.rawValue, forKey: AppSettingsKey.aiNewChatAfter.rawValue)
        }
    }
    var enabledInstalledProviders: Set<InstalledAIKind> {
        didSet {
            guard let data = try? JSONEncoder().encode(enabledInstalledProviders.sorted(by: {
                $0.rawValue < $1.rawValue
            })) else { return }
            defaults.set(data, forKey: AppSettingsKey.aiInstalledProviders.rawValue)
        }
    }

    /// Asked each time: the model lands mid-session, and a flag read at launch would never notice.
    @ObservationIgnored let isAppleIntelligenceAvailable: @Sendable () -> Bool

    init(
        defaults: UserDefaults = .standard,
        isAppleIntelligenceAvailable: @escaping @Sendable () -> Bool = { false }
    ) {
        self.defaults = defaults
        self.isAppleIntelligenceAvailable = isAppleIntelligenceAvailable
        connections = Self.decodeConnections(
            defaults.data(forKey: AppSettingsKey.aiConnections.rawValue))
        defaultModel = Self.decodeDefaultModel(
            defaults.data(forKey: AppSettingsKey.aiDefaultModel.rawValue))
        webSearchEnabled =
            defaults.object(forKey: AppSettingsKey.aiWebSearch.rawValue) as? Bool ?? false
        systemPrompt = defaults.string(forKey: AppSettingsKey.aiSystemPrompt.rawValue) ?? ""
        systemPromptEnabled =
            defaults.object(forKey: AppSettingsKey.aiSystemPromptEnabled.rawValue) as? Bool ?? true
        // Unset reads as 0, which no retention case carries — `forever` is negative on purpose.
        retention =
            AIRetention(rawValue: defaults.integer(forKey: AppSettingsKey.aiRetention.rawValue))
            ?? .forever
        opensTo =
            AIOpensTo(rawValue: defaults.integer(forKey: AppSettingsKey.aiOpensTo.rawValue))
            ?? .recent
        newChatAfter =
            AINewChatAfter(
                rawValue: defaults.integer(forKey: AppSettingsKey.aiNewChatAfter.rawValue))
            ?? .fiveMinutes
        enabledInstalledProviders = Self.decodeEnabledInstalledProviders(
            defaults.data(forKey: AppSettingsKey.aiInstalledProviders.rawValue))
        if case .api(let connection, let model, _) = defaultModel,
            !connections.contains(where: { $0.id == connection && $0.models.contains(model) })
        {
            defaultModel = firstAvailableSelection()
        }
        if defaultModel == nil {
            defaultModel = firstAvailableSelection()
        }
    }

    func connection(id: UUID) -> AIConnection? {
        connections.first { $0.id == id }
    }

    func select(_ selection: AIModelSelection) {
        if case .api(let connection, let model, _) = selection {
            guard self.connection(id: connection)?.models.contains(model) == true else { return }
        }
        defaultModel = selection
    }

    func save(_ connection: AIConnection) {
        let connection = normalized(connection)
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        if case .api(connection.id, let model, let effort) = defaultModel {
            if connection.models.contains(model) {
                defaultModel = .api(
                    connection: connection.id, model: model,
                    effort: connection.reasoningOptions?[model]?.resolvedEffort(effort))
            } else {
                defaultModel = connection.models.first.map {
                    .api(
                        connection: connection.id, model: $0,
                        effort: connection.reasoningOptions?[$0]?.resolvedEffort(nil))
                }
            }
        }
        if defaultModel == nil, let model = connection.models.first {
            defaultModel = .api(
                connection: connection.id, model: model,
                effort: connection.reasoningOptions?[model]?.resolvedEffort(nil))
        }
    }

    func removeConnection(id: UUID) {
        connections.removeAll { $0.id == id }
        guard case .api(id, _, _) = defaultModel else { return }
        defaultModel = firstAvailableSelection()
    }

    func reconcile(codexModels models: [ChatGPTSubscription.Model], isUnavailable: Bool) {
        guard case .codex(let model, let effort) = defaultModel else { return }
        if isUnavailable {
            defaultModel = firstAvailableSelection()
            return
        }
        guard !models.isEmpty else { return }
        if let match = models.first(where: { $0.id == model }) {
            let resolved = match.resolvedEffort(effort)
            if resolved != effort { defaultModel = .codex(model: model, effort: resolved) }
            return
        }
        guard let replacement = models.first(where: \.isDefault) ?? models.first else { return }
        defaultModel = .codex(
            model: replacement.id, effort: replacement.resolvedEffort(nil))
    }

    func reconcile(
        installed kind: InstalledAIKind, models: [InstalledAIModel], isUnavailable: Bool
    ) {
        let selectedModel: String
        switch (kind, defaultModel) {
        case (.claude, .claude(let model, _)), (.openCode, .openCode(let model, _)):
            selectedModel = model
        default:
            return
        }
        if isUnavailable {
            defaultModel = firstAvailableSelection()
            return
        }
        guard !models.isEmpty else { return }
        if let match = models.first(where: { $0.id == selectedModel }) {
            let resolved = match.resolvedEffort(defaultModel?.effort)
            if resolved != defaultModel?.effort { defaultModel = defaultModel?.withEffort(resolved) }
            return
        }
        guard let replacement = models.first else { return }
        switch kind {
        case .claude:
            defaultModel = .claude(
                model: replacement.id, effort: replacement.resolvedEffort(nil))
        case .openCode:
            defaultModel = .openCode(
                model: replacement.id, effort: replacement.resolvedEffort(nil))
        case .codex: break
        }
    }

    /// Nothing chosen yet takes the route that needs no account, leaving a real stored selection.
    func resolveDefaultModel() {
        guard defaultModel == nil, let selection = firstAvailableSelection() else { return }
        defaultModel = selection
    }

    func setInstalledProviderEnabled(_ enabled: Bool, for kind: InstalledAIKind) {
        var providers = enabledInstalledProviders
        if enabled {
            providers.insert(kind)
        } else {
            providers.remove(kind)
        }
        enabledInstalledProviders = providers
    }

    func disableInstalledModelSelection(for kind: InstalledAIKind) {
        guard let source = defaultModel?.source else { return }
        let matches = switch (kind, source) {
        case (.codex, .codex), (.claude, .claude), (.openCode, .openCode): true
        default: false
        }
        guard matches else { return }
        defaultModel = firstAvailableSelection()
    }

    /// The on-device model leads: free, private, always configured, so never a surprising landing.
    private func firstAvailableSelection() -> AIModelSelection? {
        if isAppleIntelligenceAvailable() { return .appleIntelligence }
        for connection in connections {
            if let model = connection.models.first {
                return .api(
                    connection: connection.id, model: model,
                    effort: connection.reasoningOptions?[model]?.resolvedEffort(nil))
            }
        }
        return nil
    }

    private func persistConnections() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: AppSettingsKey.aiConnections.rawValue)
    }

    private func persistDefaultModel() {
        guard let defaultModel, let data = try? JSONEncoder().encode(defaultModel) else {
            defaults.removeObject(forKey: AppSettingsKey.aiDefaultModel.rawValue)
            return
        }
        defaults.set(data, forKey: AppSettingsKey.aiDefaultModel.rawValue)
    }

    private func normalized(_ connection: AIConnection) -> AIConnection {
        var connection = connection
        connection.name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        connection.baseURL = connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        connection.models = connection.models.compactMap {
            let model = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty, seen.insert(model).inserted else { return nil }
            return model
        }
        connection.visionModels = connection.visionModels.filter(seen.contains)
        connection.reasoningOptions = connection.reasoningOptions?.filter {
            seen.contains($0.key) && !$0.value.efforts.isEmpty
        }
        if connection.reasoningOptions?.isEmpty == true { connection.reasoningOptions = nil }
        return connection
    }

    private static func decodeConnections(_ data: Data?) -> [AIConnection] {
        guard let data,
            let connections = try? JSONDecoder().decode([AIConnection].self, from: data)
        else { return [] }
        return connections
    }

    private static func decodeDefaultModel(_ data: Data?) -> AIModelSelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AIModelSelection.self, from: data)
    }

    private static func decodeEnabledInstalledProviders(_ data: Data?) -> Set<InstalledAIKind> {
        guard let data,
            let providers = try? JSONDecoder().decode([InstalledAIKind].self, from: data)
        else { return [] }
        return Set(providers)
    }
}
