import FoundationModels
import Foundation

@MainActor
enum AIProviderFactory {
    /// Chat's route, and the one every existing caller means.
    static func make(
        settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager,
        installedAI: InstalledAIManager,
        keyStore: KeychainSecretStore = .aiAPIKeys
    ) throws -> any AIProvider {
        guard let selection = settings.defaultModel else {
            throw AIProviderError.unavailable(String(localized: "Choose a default AI model in Settings.", bundle: .appLanguage))
        }
        return try make(
            selection: selection, settings: settings, subscription: subscription,
            installedAI: installedAI, keyStore: keyStore)
    }

    /// `guardrails` reaches only the on-device model, the one route that filters locally.
    static func make(
        selection: AIModelSelection,
        settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager,
        installedAI: InstalledAIManager,
        keyStore: KeychainSecretStore = .aiAPIKeys,
        guardrails: SystemLanguageModel.Guardrails = .default
    ) throws -> any AIProvider {
        switch selection {
        case .appleIntelligence:
            if let message = AppleIntelligenceProvider.status().message {
                throw AIProviderError.unavailable(message)
            }
            return AppleIntelligenceProvider(guardrails: guardrails)
        case .codex(let model, let effort):
            guard settings.enabledInstalledProviders.contains(.codex) else {
                throw AIProviderError.unavailable(String(localized: "Codex is disabled in AI Settings.", bundle: .appLanguage))
            }
            return CodexInstalledProvider(
                turns: subscription.turns, model: model, effort: effort)
        case .claude(let model, let effort):
            guard settings.enabledInstalledProviders.contains(.claude) else {
                throw AIProviderError.unavailable(String(localized: "Claude is disabled in AI Settings.", bundle: .appLanguage))
            }
            return try installedAI.provider(kind: .claude, model: model, effort: effort)
        case .openCode(let model, let effort):
            guard settings.enabledInstalledProviders.contains(.openCode) else {
                throw AIProviderError.unavailable(String(localized: "OpenCode is disabled in AI Settings.", bundle: .appLanguage))
            }
            return try installedAI.provider(kind: .openCode, model: model, effort: effort)
        case .api(let connectionID, let model, let effort):
            guard let connection = settings.connection(id: connectionID) else {
                throw AIProviderError.unavailable(String(
                    localized: "Choose an API connection in Settings.",
                    bundle: .appLanguage))
            }
            let baseURL: URL
            do {
                baseURL = try AIEndpointPolicy.validate(connection.baseURL)
            } catch let error as AIEndpointPolicy.ValidationError {
                throw AIProviderError.unavailable(error.localizedDescription)
            }
            let key: String
            do {
                key = try keyStore.secret(for: connection.id) ?? ""
            } catch {
                throw AIProviderError.unavailable(String(
                    localized: "The API key could not be read from Keychain.",
                    bundle: .appLanguage))
            }
            guard AIEndpointPolicy.isLoopback(connection.baseURL) || !key.isEmpty else {
                throw AIProviderError.unavailable(String(localized: "Add an API key in Settings.", bundle: .appLanguage))
            }
            return HTTPAIProvider(
                configuration: AIHTTPConfiguration(
                    provider: connection.provider, baseURL: baseURL, model: model, effort: effort),
                apiKey: key)
        }
    }
}
