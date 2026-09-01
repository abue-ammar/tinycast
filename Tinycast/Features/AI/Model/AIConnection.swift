import Foundation

enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI
    case anthropic
    case gemini
    case openRouter
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return "OpenAI API"
        case .anthropic: return "Anthropic Claude"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .openAICompatible: return "OpenAI Compatible"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openAICompatible: return "https://api.openai.com/v1"
        }
    }

    var apiShape: AIHTTPConfiguration.APIShape {
        self == .anthropic ? .anthropic : .openAICompatible
    }
}

struct AIConnection: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var provider: AIProviderKind
    var baseURL: String
    var models: [String]
    /// Models the catalog marked as taking images — only OpenRouter's says, so only it is gated.
    var visionModels: [String]

    init(
        id: UUID = UUID(), name: String = "", provider: AIProviderKind = .openAI,
        baseURL: String? = nil, models: [String] = [], visionModels: [String] = []
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.models = models
        self.visionModels = visionModels
    }

    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.title : trimmed
    }

    func capabilities(for model: String) -> AIModelCapabilities {
        AIModelCapabilities(
            images: provider != .openRouter || visionModels.contains(model),
            webSearch: provider == .openRouter, tools: true)
    }
}

/// What the picker can offer for a model: a vendor API takes images unless its catalog said no.
struct AIModelCapabilities: Equatable, Sendable {
    let images: Bool
    let webSearch: Bool
    /// Only the two HTTP shapes; the Codex route declines tools and the on-device one has none.
    let tools: Bool

    static let none = AIModelCapabilities(images: false, webSearch: false, tools: false)
    static let chatGPT = AIModelCapabilities(images: true, webSearch: true, tools: false)
    /// The on-device model is text-only and reaches nothing, so it offers none of the three.
    static let appleIntelligence = AIModelCapabilities.none
}

enum AIModelSource: Codable, Equatable, Hashable, Sendable {
    case appleIntelligence
    case chatGPT
    case api(UUID)
}

enum AIModelSelection: Codable, Equatable, Hashable, Sendable {
    case appleIntelligence
    case chatGPT(model: String, effort: String?)
    case api(connection: UUID, model: String)

    var source: AIModelSource {
        switch self {
        case .appleIntelligence: return .appleIntelligence
        case .chatGPT: return .chatGPT
        case .api(let connection, _): return .api(connection)
        }
    }

    var model: String {
        switch self {
        case .appleIntelligence: return AppleIntelligence.modelID
        case .chatGPT(let model, _), .api(_, let model): return model
        }
    }

    /// The one route with nothing to bill and nothing to configure, so it needs no capability gate.
    var isOnDevice: Bool { self == .appleIntelligence }
}

struct AIHTTPConfiguration: Equatable, Sendable {
    enum APIShape: String, Sendable {
        case openAICompatible
        case anthropic
    }

    let provider: AIProviderKind
    let baseURL: URL
    let model: String

    var shape: APIShape { provider.apiShape }

    var endpointURL: URL {
        switch shape {
        case .openAICompatible:
            if baseURL.path.hasSuffix("/chat/completions") { return baseURL }
            return baseURL.appending(path: "chat/completions")
        case .anthropic:
            if baseURL.path.hasSuffix("/messages") { return baseURL }
            return baseURL.appending(path: "v1/messages")
        }
    }
}

enum AIEndpointPolicy {
    enum ValidationError: LocalizedError, Equatable {
        case invalidURL
        case insecureRemoteURL

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Enter a valid provider base URL."
            case .insecureRemoteURL: return "Remote AI providers require an HTTPS base URL."
            }
        }
    }

    static func validate(_ value: String) throws -> URL {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only the two schemes the transport speaks: `ftp://localhost` was once a valid provider.
        guard let url = URL(string: value), let host = url.host(),
            url.scheme == "https" || url.scheme == "http"
        else {
            throw ValidationError.invalidURL
        }
        guard url.scheme == "https" || isLoopback(host: host) else {
            throw ValidationError.insecureRemoteURL
        }
        return url
    }

    /// A key is issued for one endpoint, so a changed provider or base URL leaves it behind.
    static func sameDestination(_ connection: AIConnection, _ other: AIConnection) -> Bool {
        connection.provider == other.provider && connection.baseURL == other.baseURL
    }

    static func isLoopback(_ value: String) -> Bool {
        guard let host = URL(string: value)?.host() else { return false }
        return isLoopback(host: host)
    }

    private static func isLoopback(host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }
}
