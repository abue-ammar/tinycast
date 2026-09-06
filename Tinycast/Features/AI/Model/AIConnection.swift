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
    struct ReasoningOptions: Codable, Equatable, Sendable {
        let efforts: [String]
        let defaultEffort: String?

        func resolvedEffort(_ preferred: String?) -> String? {
            guard !efforts.isEmpty else { return nil }
            if let preferred, efforts.contains(preferred) { return preferred }
            if let defaultEffort, efforts.contains(defaultEffort) { return defaultEffort }
            return efforts.first
        }
    }

    let id: UUID
    var name: String
    var provider: AIProviderKind
    var baseURL: String
    var models: [String]
    /// Models the catalog marked as taking images — only OpenRouter's says, so only it is gated.
    var visionModels: [String]
    /// OpenRouter's per-model catalog metadata; absent for APIs that do not publish this contract.
    var reasoningOptions: [String: ReasoningOptions]?

    init(
        id: UUID = UUID(), name: String = "", provider: AIProviderKind = .openAI,
        baseURL: String? = nil, models: [String] = [], visionModels: [String] = [],
        reasoningOptions: [String: ReasoningOptions]? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.models = models
        self.visionModels = visionModels
        self.reasoningOptions = reasoningOptions
    }

    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.title : trimmed
    }

    func capabilities(for model: String) -> AIModelCapabilities {
        AIModelCapabilities(
            images: provider != .openRouter || visionModels.contains(model),
            // Only the two shapes whose bodies Tinycast writes; a gateway bills the upload first.
            documents: provider == .openAI || provider == .anthropic,
            webSearch: provider == .openRouter, tools: true)
    }
}

/// What the picker can offer for a model: a vendor API takes images unless its catalog said no.
struct AIModelCapabilities: Equatable, Sendable {
    let images: Bool
    /// A PDF as a native block; four routes have no field for one, so it is refused, never dropped.
    let documents: Bool
    let webSearch: Bool
    /// Only the two HTTP shapes; the Codex route declines tools and the on-device one has none.
    let tools: Bool

    static let none = AIModelCapabilities(
        images: false, documents: false, webSearch: false, tools: false)
    static let chatGPT = AIModelCapabilities(
        images: true, documents: false, webSearch: true, tools: false)
    static let codex = AIModelCapabilities(
        images: true, documents: false, webSearch: true, tools: false)
    /// The on-device model is text-only and reaches nothing, so it offers none of the three.
    static let appleIntelligence = AIModelCapabilities.none
}

enum AIModelSource: Codable, Equatable, Hashable, Sendable {
    case appleIntelligence
    case codex
    case claude
    case openCode
    case api(UUID)
}

enum AIModelSelection: Codable, Equatable, Hashable, Sendable {
    case appleIntelligence
    case codex(model: String, effort: String?)
    case claude(model: String, effort: String?)
    case openCode(model: String, effort: String?)
    case api(connection: UUID, model: String, effort: String?)

    var source: AIModelSource {
        switch self {
        case .appleIntelligence: return .appleIntelligence
        case .codex: return .codex
        case .claude: return .claude
        case .openCode: return .openCode
        case .api(let connection, _, _): return .api(connection)
        }
    }

    var model: String {
        switch self {
        case .appleIntelligence: return AppleIntelligence.modelID
        case .codex(let model, _), .claude(let model, _), .openCode(let model, _),
            .api(_, let model, _):
            return model
        }
    }

    var effort: String? {
        switch self {
        case .codex(_, let effort), .claude(_, let effort), .openCode(_, let effort),
            .api(_, _, let effort):
            return effort
        case .appleIntelligence:
            return nil
        }
    }

    func withEffort(_ effort: String?) -> AIModelSelection {
        switch self {
        case .codex(let model, _): return .codex(model: model, effort: effort)
        case .claude(let model, _): return .claude(model: model, effort: effort)
        case .openCode(let model, _): return .openCode(model: model, effort: effort)
        case .api(let connection, let model, _):
            return .api(connection: connection, model: model, effort: effort)
        case .appleIntelligence: return self
        }
    }

    /// The one route with nothing to bill and nothing to configure, so it needs no capability gate.
    var isOnDevice: Bool { self == .appleIntelligence }

    private enum CodingKeys: String, CodingKey {
        case appleIntelligence
        case codex
        case chatGPT
        case claude
        case openCode
        case api
    }

    private enum ValueKeys: String, CodingKey {
        case model
        case effort
        case connection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.appleIntelligence) {
            self = .appleIntelligence
            return
        }
        if container.contains(.codex) || container.contains(.chatGPT) {
            let key: CodingKeys = container.contains(.codex) ? .codex : .chatGPT
            let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: key)
            self = .codex(
                model: try value.decode(String.self, forKey: .model),
                effort: try value.decodeIfPresent(String.self, forKey: .effort))
            return
        }
        if container.contains(.claude) {
            let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .claude)
            self = .claude(
                model: try value.decode(String.self, forKey: .model),
                effort: try value.decodeIfPresent(String.self, forKey: .effort))
            return
        }
        if container.contains(.openCode) {
            let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .openCode)
            self = .openCode(
                model: try value.decode(String.self, forKey: .model),
                effort: try value.decodeIfPresent(String.self, forKey: .effort))
            return
        }
        let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .api)
        self = .api(
            connection: try value.decode(UUID.self, forKey: .connection),
            model: try value.decode(String.self, forKey: .model),
            effort: try value.decodeIfPresent(String.self, forKey: .effort))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appleIntelligence:
            _ = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .appleIntelligence)
        case .codex(let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .codex)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        case .claude(let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .claude)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        case .openCode(let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .openCode)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        case .api(let connection, let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .api)
            try value.encode(connection, forKey: .connection)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        }
    }
}

struct AIHTTPConfiguration: Equatable, Sendable {
    enum APIShape: String, Sendable {
        case openAICompatible
        case anthropic
    }

    let provider: AIProviderKind
    let baseURL: URL
    let model: String
    let effort: String?

    init(provider: AIProviderKind, baseURL: URL, model: String, effort: String? = nil) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.effort = effort
    }

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
