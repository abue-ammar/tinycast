import FoundationModels
import Foundation

@MainActor
enum AIProviderFactory {
    /// Chat's route, and the one every existing caller means.
    static func make(
        settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager,
        keyStore: KeychainSecretStore = .aiAPIKeys
    ) throws -> any AIProvider {
        guard let selection = settings.defaultModel else {
            throw AIProviderError.unavailable("Choose a default AI model in Settings.")
        }
        return try make(
            selection: selection, settings: settings, subscription: subscription,
            keyStore: keyStore)
    }

    /// `guardrails` reaches only the on-device model, the one route that filters locally.
    static func make(
        selection: AIModelSelection,
        settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager,
        keyStore: KeychainSecretStore = .aiAPIKeys,
        guardrails: SystemLanguageModel.Guardrails = .default
    ) throws -> any AIProvider {
        switch selection {
        case .appleIntelligence:
            if let message = AppleIntelligenceProvider.status().message {
                throw AIProviderError.unavailable(message)
            }
            return AppleIntelligenceProvider(guardrails: guardrails)
        case .chatGPT(let model, let effort):
            return ChatGPTSubscriptionProvider(
                turns: subscription.turns, model: model, effort: effort)
        case .api(let connectionID, let model):
            guard let connection = settings.connection(id: connectionID) else {
                throw AIProviderError.unavailable("Choose an API connection in Settings.")
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
                throw AIProviderError.unavailable("The API key could not be read from Keychain.")
            }
            guard AIEndpointPolicy.isLoopback(connection.baseURL) || !key.isEmpty else {
                throw AIProviderError.unavailable("Add an API key in Settings.")
            }
            return HTTPAIProvider(
                configuration: AIHTTPConfiguration(
                    provider: connection.provider, baseURL: baseURL, model: model),
                apiKey: key)
        }
    }
}
