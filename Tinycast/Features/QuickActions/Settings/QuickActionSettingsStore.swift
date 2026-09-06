import Foundation
import Observation

/// Apart from `AISettingsStore`: a peer of chat, with its own switch, route and settings pane.
@MainActor
@Observable
final class QuickActionSettingsStore {
    private let defaults: UserDefaults

    var settings: QuickActionSettings {
        didSet { persistSettings() }
    }
    /// A grammar fix fires far oftener than a chat turn, so billing it per press is no default.
    private(set) var model: AIModelSelection? {
        didSet { persistModel() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = QuickActionSettings()
        loaded.storedPreviewChoices =
            defaults.dictionary(forKey: AppSettingsKey.quickActionPreviews.rawValue)
            as? [String: Bool] ?? [:]
        loaded.targetLanguage =
            defaults.string(forKey: AppSettingsKey.quickActionLanguage.rawValue) ?? ""
        loaded.storedInstructionOverrides =
            defaults.dictionary(forKey: AppSettingsKey.quickActionInstructions.rawValue)
            as? [String: String] ?? [:]
        settings = loaded
        model = Self.decodeModel(
            defaults.data(forKey: AppSettingsKey.quickActionModel.rawValue))
    }

    func select(_ selection: AIModelSelection?) {
        model = selection
    }

    /// Nothing chosen takes the route that needs no account, the way chat's own default resolves.
    func resolveModel(appleIntelligenceAvailable: Bool, fallback: AIModelSelection?) {
        guard model == nil else { return }
        model = appleIntelligenceAvailable ? .appleIntelligence : fallback
    }

    /// A connection the reader removed must not leave this pointing at a route that cannot answer.
    func repairModel(against connections: [AIConnection], fallback: AIModelSelection?) {
        guard case .api(let id, let name, _) = model,
            !connections.contains(where: { $0.id == id && $0.models.contains(name) })
        else { return }
        model = fallback
    }

    func repairInstalledModel(
        available: [AIModelSelection], unavailableSources: Set<AIModelSource>,
        fallback: AIModelSelection?
    ) {
        guard let model, model.source.installedKind != nil else { return }
        let sourceModels = available.filter { $0.source == model.source }
        if sourceModels.contains(where: { $0.model == model.model }) { return }
        if let replacement = sourceModels.first {
            self.model = replacement
            return
        }
        guard unavailableSources.contains(model.source) else { return }
        guard let fallback, !unavailableSources.contains(fallback.source), fallback != model else {
            self.model = nil
            return
        }
        self.model = fallback
    }

    private func persistSettings() {
        defaults.set(
            settings.storedPreviewChoices, forKey: AppSettingsKey.quickActionPreviews.rawValue)
        defaults.set(settings.targetLanguage, forKey: AppSettingsKey.quickActionLanguage.rawValue)
        defaults.set(
            settings.storedInstructionOverrides,
            forKey: AppSettingsKey.quickActionInstructions.rawValue)
    }

    private func persistModel() {
        guard let model, let data = try? JSONEncoder().encode(model) else {
            defaults.removeObject(forKey: AppSettingsKey.quickActionModel.rawValue)
            return
        }
        defaults.set(data, forKey: AppSettingsKey.quickActionModel.rawValue)
    }

    private static func decodeModel(_ data: Data?) -> AIModelSelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AIModelSelection.self, from: data)
    }
}
