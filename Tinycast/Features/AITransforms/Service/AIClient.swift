import Foundation

/// One OpenAI-compatible chat completion. Pure value; building it must not touch the network.
struct AICompletionRequest: Sendable {
    /// e.g. https://api.openai.com/v1 — the endpoint is baseURL + "/chat/completions".
    var baseURL: URL
    var apiKey: String
    var model: String
    /// Preset prompt, wrapped as the system message.
    var instruction: String
    /// The highlighted text, sent as the user message.
    var selection: String
    /// Reasoning level for reasoning-capable models (e.g. o3-mini, Gemini 2.5/3.7, DeepSeek-R1).
    var reasoningEffort: AIReasoningEffort? = nil

    func makeURLRequest() -> URLRequest {
        // The user pastes the base URL; tolerate a trailing slash and a full endpoint pasted
        // wholesale, both of which otherwise double a path segment and 404 opaquely.
        let endpoint = Self.endpointURL(fromBase: baseURL.absoluteString) ?? baseURL
        var request = URLRequest(url: endpoint)

        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Reasoning models (o1, o3, etc.) reject `max_tokens` and require `max_completion_tokens`.
        let isReasoning =
            model.lowercased().hasPrefix("o1")
            || model.lowercased().hasPrefix("o3")
            || (reasoningEffort != nil && reasoningEffort != .none)

        request.httpBody = try? JSONEncoder().encode(
            Body(
                model: model,
                stream: false,
                maxTokens: isReasoning ? nil : 4096,
                maxCompletionTokens: isReasoning ? 4096 : nil,
                messages: [
                    Body.Message(role: "system", content: Self.systemInstruction(instruction)),
                    Body.Message(role: "user", content: selection)
                ],
                reasoningEffort: reasoningEffort?.wireValue
            ))
        return request
    }

    /// Appends the strict output contract, guaranteeing that the returned text replaces the selection cleanly.
    static func systemInstruction(_ prompt: String) -> String {
        """
        \(prompt)

        CRITICAL OUTPUT INSTRUCTIONS:
        Unless explicitly requested otherwise by the prompt above:
        - Output ONLY the transformed text directly.
        - Do NOT include any preamble, introduction, greetings, or conversational filler (e.g. "Here is...", "Sure!").
        - Do NOT include any commentary, explanation, breakdown of changes, notes, or concluding remarks.
        - Do NOT include follow-up questions, suggestions, or engagement hooks.
        - Do NOT enclose the entire output in quotes or markdown code blocks unless code formatting was explicitly requested.
        - The returned output will replace the highlighted selection in place on the user's screen; output nothing except the replacement text.
        """
    }

    /// Joins whatever the user configured into a provider endpoint: whitespace and trailing
    /// slashes go, and a base URL that already ends in the path keeps working. The suffix strip
    /// is case-insensitive and keyed on the last path segment pair, so `/models` against a base
    /// that was pasted as a chat endpoint still lands where the user meant.
    static func endpointURL(
        fromBase baseURLString: String, path: String = "/chat/completions"
    )
        -> URL?
    {
        var trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        let chatSuffix = "/chat/completions"
        if trimmed.lowercased().hasSuffix(chatSuffix) {
            trimmed.removeLast(chatSuffix.count)
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
        } else if trimmed.lowercased().hasSuffix(path.lowercased()) {
            trimmed.removeLast(path.count)
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
        }
        return URL(string: trimmed + path)
    }

    /// Mirrors the wire shape every OpenAI-compatible provider accepts; `stream` is spelled out
    /// so a provider default can never turn this into a streaming response.
    struct Body: Encodable {
        var model: String
        var stream: Bool
        var maxTokens: Int?
        var maxCompletionTokens: Int?
        var messages: [Message]
        var reasoningEffort: String?

        struct Message: Encodable {
            var role: String
            var content: String
        }

        enum CodingKeys: String, CodingKey {
            case model, stream, messages
            case maxTokens = "max_tokens"
            case maxCompletionTokens = "max_completion_tokens"
            case reasoningEffort = "reasoning_effort"
        }
    }
}

enum AIClientError: LocalizedError, Equatable {
    /// Missing key or model.
    case notConfigured
    case invalidBaseURL(String)
    /// 401/403.
    case unauthorized
    /// 429.
    case rateLimited
    case provider(status: Int, message: String)
    case emptyResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set a model and an API key in AI Transforms settings."
        case .invalidBaseURL(let url):
            return "The provider URL “\(url)” is not a valid URL."
        case .unauthorized:
            return "The provider rejected the API key. Check your API key in AI Transforms settings."
        case .rateLimited:
            return "Rate limited by the provider. Wait a moment and try again."
        case .provider(let status, let message):
            return "The provider returned an error (\(status)): \(message)"
        case .emptyResponse:
            return "The provider returned an empty response."
        case .network(let message):
            return "Could not reach the provider: \(message)"
        }
    }
}

enum AIClient {
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"
    static let requestTimeout: TimeInterval = 60

    /// Decodes `choices[0].message.content`, mapping error bodies and status codes to friendly
    /// errors. The trimmed content is what replaces the selection, so surrounding whitespace a
    /// model pads on is stripped here rather than pasted.
    static func parseResponse(_ data: Data, status: Int) throws -> String {
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        guard (200..<300).contains(status) else {
            // Providers put the human-readable cause in an error body; a non-JSON body (an HTML
            // 404 page from a wrong base URL, most often) degrades to a bounded raw snippet.
            var message = failureMessage(in: data) ?? "HTTP \(status)"
            if status == 404 {
                message +=
                    " — the endpoint was not found. Check the base URL: it must be the provider's"
                    + " OpenAI-compatible root, ending before “/chat/completions” (Gemini's is"
                    + " https://generativelanguage.googleapis.com/v1beta/openai)."
            }
            switch status {
            case 401, 403: throw AIClientError.unauthorized
            case 429: throw AIClientError.rateLimited
            default: throw AIClientError.provider(status: status, message: message)
            }
        }
        guard
            let content = decoded?.choices?.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty
        else { throw AIClientError.emptyResponse }
        return content
    }

    /// Fishes the human-readable cause out of any error shape: OpenAI and Gemini nest it at
    /// `error.message`, some providers keep a flat `message`, and anything else survives only
    /// as a bounded snippet so an HTML error page can't flood the dialog.
    private static func failureMessage(in data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let error = object["error"]
            let candidate =
                (error as? [String: Any])?["message"] ?? (error as? String) ?? object["message"]
            if let message = candidate as? String, !message.isEmpty { return message }
        }
        guard
            let raw = String(data: data.prefix(160), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return nil }
        return raw
    }

    static func complete(_ request: AICompletionRequest) async throws -> String {
        guard !request.apiKey.isEmpty, !request.model.isEmpty else {
            throw AIClientError.notConfigured
        }
        let (data, http) = try await send(request.makeURLRequest())
        return try parseResponse(data, status: http.statusCode)
    }

    /// The settings pane's model poller: GET `/models`, the one listing route every
    /// OpenAI-compatible root serves. Returns sorted, de-duplicated model IDs.
    static func listModels(baseURL: String, apiKey: String) async throws -> [String] {
        guard let endpoint = AICompletionRequest.endpointURL(fromBase: baseURL, path: "/models")
        else { throw AIClientError.invalidBaseURL(baseURL) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw AIClientError.provider(
                status: http.statusCode,
                message: failureMessage(in: data) ?? "HTTP \(http.statusCode)")
        }
        return parseModelList(data)
    }

    /// Reads model IDs out of any listing shape: the OpenAI envelope (`data[].id`), a bare
    /// array, or objects carrying `name` instead. Empty, never an error — a provider that
    /// serves chat but lists nothing still lets the user type a model by hand.
    static func parseModelList(_ data: Data) -> [String] {
        func id(of entry: Any) -> String? {
            if let id = entry as? String { return id }
            if let object = entry as? [String: Any] {
                return (object["id"] ?? object["name"]) as? String
            }
            return nil
        }
        let object = try? JSONSerialization.jsonObject(with: data)
        let entries = (object as? [String: Any])?["data"] as? [Any] ?? (object as? [Any]) ?? []
        return Set(entries.compactMap(id(of:))).sorted()
    }

    /// The probe request: one user message, a token-few ceiling, Bearer auth — everything the
    /// Test button needs to prove the chain without spending real tokens.
    static func makeTestURLRequest(endpoint: URL, apiKey: String, model: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isReasoning = model.lowercased().hasPrefix("o1") || model.lowercased().hasPrefix("o3")
        request.httpBody = try? JSONEncoder().encode(
            AICompletionRequest.Body(
                model: model,
                stream: false,
                maxTokens: isReasoning ? nil : 16,
                maxCompletionTokens: isReasoning ? 16 : nil,
                messages: [AICompletionRequest.Body.Message(role: "user", content: "Reply with the word OK.")]
            ))
        return request
    }

    /// One tiny completion, purely so the pane's Test button can prove the whole chain —
    /// URL, key, and model — before the user commits a transform to it.
    static func testConnection(baseURL: String, apiKey: String, model: String) async throws {
        guard !apiKey.isEmpty, !model.isEmpty else { throw AIClientError.notConfigured }
        guard let endpoint = AICompletionRequest.endpointURL(fromBase: baseURL)
        else { throw AIClientError.invalidBaseURL(baseURL) }
        let (data, http) = try await send(
            makeTestURLRequest(endpoint: endpoint, apiKey: apiKey, model: model))
        _ = try parseResponse(data, status: http.statusCode)
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIClientError.network("the server did not return an HTTP response")
            }
            return (data, http)
        } catch let error as AIClientError {
            throw error
        } catch {
            throw AIClientError.network(error.localizedDescription)
        }
    }
    /// Cacheless, never `URLSession.shared`, so neither the key nor a completion lingers anywhere.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: config)
    }()

    private struct Response: Decodable {
        // Optional: an error status carries no choices; the success path only needs the first.
        var choices: [Choice]?

        struct Choice: Decodable {
            var message: Message
        }

        struct Message: Decodable {
            var content: String?
        }
    }
}
