import Foundation
import Observation

@MainActor
@Observable
final class TranslationSettingsStore {
    private let defaults: UserDefaults

    var provider: TranslationProvider {
        didSet { defaults.set(provider.rawValue, forKey: AppSettingsKey.translationProvider.rawValue) }
    }
    private(set) var model: AIModelSelection? {
        didSet {
            defaults.set(
                model.flatMap { try? JSONEncoder().encode($0) },
                forKey: AppSettingsKey.translationModel.rawValue)
        }
    }
    var sourceLanguage: String {
        didSet { defaults.set(sourceLanguage, forKey: AppSettingsKey.translationSourceLanguage.rawValue) }
    }
    var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: AppSettingsKey.translationTargetLanguage.rawValue) }
    }
    var deepLPlan: DeepLPlan {
        didSet { defaults.set(deepLPlan.rawValue, forKey: AppSettingsKey.translationDeepLPlan.rawValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = defaults.string(forKey: AppSettingsKey.translationProvider.rawValue)
            .flatMap(TranslationProvider.init(rawValue:)) ?? .ai
        let savedModel = defaults.data(forKey: AppSettingsKey.translationModel.rawValue)
            .flatMap { try? JSONDecoder().decode(AIModelSelection.self, from: $0) }
        if case .api = savedModel { model = savedModel } else { model = nil }
        sourceLanguage = defaults.string(forKey: AppSettingsKey.translationSourceLanguage.rawValue)
            .flatMap(Self.sourceCode) ?? "auto"
        targetLanguage = defaults.string(forKey: AppSettingsKey.translationTargetLanguage.rawValue)
            .flatMap(Self.targetCode) ?? "zh-Hans"
        deepLPlan = defaults.string(forKey: AppSettingsKey.translationDeepLPlan.rawValue)
            .flatMap(DeepLPlan.init(rawValue:)) ?? .free
    }

    func select(_ selection: AIModelSelection?) {
        if let selection {
            guard case .api = selection else { return }
        }
        guard model != selection else { return }
        model = selection
    }

    static func sourceCode(_ code: String) -> String? {
        code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : code
    }

    static func targetCode(_ code: String) -> String? {
        guard !TranslationLanguages.matches(code, "auto") else { return nil }
        return sourceCode(code)
    }
}
