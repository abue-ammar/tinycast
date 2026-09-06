import Foundation

enum AIModelDiscovery {
    struct Model: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        /// `nil` when the catalog doesn't say; OpenRouter lists `text`, `image`, `file`, `audio`.
        var inputModalities: [String]? = nil
        var reasoningOptions: AIConnection.ReasoningOptions?

        init(
            id: String, name: String, inputModalities: [String]? = nil,
            reasoningOptions: AIConnection.ReasoningOptions? = nil
        ) {
            self.id = id
            self.name = name
            self.inputModalities = inputModalities
            self.reasoningOptions = reasoningOptions
        }

        var acceptsImages: Bool? { inputModalities?.contains("image") }
    }

    struct Query: Sendable {
        enum ResponseShape: Sendable {
            case openAI
            case gemini
        }

        let request: URLRequest
        let responseShape: ResponseShape
    }

    enum DiscoveryError: LocalizedError, Equatable {
        case malformedResponse
        case rejectedKey
        case unavailable
        case unsupported

        var errorDescription: String? {
            switch self {
            case .malformedResponse:
                return "The provider returned an unreadable model list. Enter a model ID manually."
            case .rejectedKey:
                return "The API key was rejected. Check it and try again."
            case .unavailable:
                return "The provider could not load models right now. Try again or enter one manually."
            case .unsupported:
                return "This endpoint does not expose a model list. Enter a model ID manually."
            }
        }
    }

    static func query(
        provider: AIProviderKind, baseURL: URL, apiKey: String, appTitle: String
    ) throws -> Query {
        let usesNativeGemini =
            provider == .gemini
            && baseURL.host() == URL(string: AIProviderKind.gemini.defaultBaseURL)?.host()
        guard
            let endpoint = catalogURL(
                provider: provider, baseURL: baseURL, usesNativeGemini: usesNativeGemini)
        else { throw DiscoveryError.unsupported }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if provider == .anthropic {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if usesNativeGemini {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        } else if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if provider == .openRouter {
            request.setValue(appTitle, forHTTPHeaderField: "X-OpenRouter-Title")
        }
        return Query(request: request, responseShape: usesNativeGemini ? .gemini : .openAI)
    }

    static func decode(_ data: Data, shape: Query.ResponseShape) throws -> [Model] {
        switch shape {
        case .openAI:
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return normalized(
                response.data.map {
                    Model(
                        id: $0.id, name: $0.name ?? $0.displayName ?? $0.id,
                        inputModalities: $0.architecture?.inputModalities,
                        reasoningOptions: $0.reasoning.map {
                            AIConnection.ReasoningOptions(
                                efforts: $0.supportedEfforts ?? [],
                                defaultEffort: $0.defaultEffort)
                        })
                })
        case .gemini:
            let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
            return normalized(
                response.models.compactMap { model in
                    guard model.supportedGenerationMethods.contains("generateContent") else {
                        return nil
                    }
                    let id =
                        model.name.hasPrefix("models/")
                        ? String(model.name.dropFirst("models/".count)) : model.name
                    return Model(id: id, name: model.displayName ?? id)
                })
        }
    }

    static func search(
        _ models: [Model], query: String, excluding: Set<String> = [], limit: Int = 12
    ) -> [Model] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        return models.enumerated()
            .filter {
                !excluding.contains($0.element.id)
                    && ($0.element.id.localizedCaseInsensitiveContains(query)
                        || $0.element.name.localizedCaseInsensitiveContains(query))
            }
            .sorted {
                let left = searchRank($0.element, query: query)
                let right = searchRank($1.element, query: query)
                return left == right ? $0.offset < $1.offset : left < right
            }
            .prefix(limit)
            .map(\.element)
    }

    private static func catalogURL(
        provider: AIProviderKind, baseURL: URL, usesNativeGemini: Bool
    ) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var path = components.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }
        if path.hasSuffix("/chat/completions") {
            path.removeLast("/chat/completions".count)
        } else if path.hasSuffix("/v1/messages") {
            path.removeLast("/v1/messages".count)
        } else if path.hasSuffix("/messages") {
            path.removeLast("/messages".count)
        }

        if usesNativeGemini {
            if path.hasSuffix("/openai") { path.removeLast("/openai".count) }
            components.path = path + "/models"
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "pageSize" }
            queryItems.append(URLQueryItem(name: "pageSize", value: "1000"))
            components.queryItems = queryItems
        } else if provider == .anthropic {
            components.path = path + "/v1/models"
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "limit" }
            queryItems.append(URLQueryItem(name: "limit", value: "1000"))
            components.queryItems = queryItems
        } else if provider == .openRouter {
            components.path = path + "/models/user"
        } else {
            components.path = path + "/models"
        }
        return components.url
    }

    private static func normalized(_ models: [Model]) -> [Model] {
        var seen = Set<String>()
        return models.compactMap { model in
            let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return Model(
                id: id, name: name.isEmpty ? id : name,
                inputModalities: model.inputModalities,
                reasoningOptions: model.reasoningOptions)
        }
    }

    private static func searchRank(_ model: Model, query: String) -> Int {
        if model.id.compare(query, options: .caseInsensitive) == .orderedSame { return 0 }
        if model.name.compare(query, options: .caseInsensitive) == .orderedSame { return 1 }
        if model.id.range(of: query, options: [.caseInsensitive, .anchored]) != nil { return 2 }
        if model.name.range(of: query, options: [.caseInsensitive, .anchored]) != nil { return 3 }
        if model.id.localizedCaseInsensitiveContains(query) { return 4 }
        return 5
    }

    private struct OpenAIResponse: Decodable {
        struct Architecture: Decodable {
            let inputModalities: [String]?

            enum CodingKeys: String, CodingKey {
                case inputModalities = "input_modalities"
            }
        }

        struct Reasoning: Decodable {
            let supportedEfforts: [String]?
            let defaultEffort: String?

            enum CodingKeys: String, CodingKey {
                case supportedEfforts = "supported_efforts"
                case defaultEffort = "default_effort"
            }
        }

        struct Model: Decodable {
            let id: String
            let name: String?
            let displayName: String?
            let architecture: Architecture?
            let reasoning: Reasoning?

            enum CodingKeys: String, CodingKey {
                case id, name, architecture, reasoning
                case displayName = "display_name"
            }
        }

        let data: [Model]
    }

    private struct GeminiResponse: Decodable {
        struct Model: Decodable {
            let name: String
            let displayName: String?
            let supportedGenerationMethods: [String]
        }

        let models: [Model]
    }
}
