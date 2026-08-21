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

    func makeURLRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL.absoluteString + "/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            Body(
                model: model,
                stream: false,
                maxTokens: 4096,
                messages: [
                    Body.Message(role: "system", content: Self.systemInstruction(instruction)),
                    Body.Message(role: "user", content: selection)
                ]))
        return request
    }

    /// Appends the no-commentary wrapper, so a chatty model cannot corrupt an in-place replace.
    static func systemInstruction(_ prompt: String) -> String {
        prompt + "\n\nReturn only the transformed text with no commentary, quotes, or code fences."
    }

    /// Mirrors the wire shape every OpenAI-compatible provider accepts; `stream` is spelled out
    /// so a provider default can never turn this into a streaming response.
    private struct Body: Encodable {
        var model: String
        var stream: Bool
        var maxTokens: Int
        var messages: [Message]

        struct Message: Encodable {
            var role: String
            var content: String
        }

        enum CodingKeys: String, CodingKey {
            case model, stream, messages
            case maxTokens = "max_tokens"
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
            // Providers put the human-readable cause in an error body; fall back to the bare status.
            let message = decoded?.error?.message ?? "HTTP \(status)"
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

    static func complete(_ request: AICompletionRequest) async throws -> String {
        guard !request.apiKey.isEmpty, !request.model.isEmpty else {
            throw AIClientError.notConfigured
        }
        do {
            let (data, response) = try await session.data(for: request.makeURLRequest())
            guard let http = response as? HTTPURLResponse else {
                throw AIClientError.network("the server did not return an HTTP response")
            }
            return try parseResponse(data, status: http.statusCode)
        } catch let error as AIClientError {
            throw error
        } catch {
            // Never logs key or text, so the message carries only the transport failure.
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
        // Optional: an error body carries no choices and must still decode far enough to
        // surface the provider's message.
        var choices: [Choice]?

        var error: ErrorBody?

        struct Choice: Decodable {
            var message: Message
        }

        struct Message: Decodable {
            var content: String?
        }

        struct ErrorBody: Decodable {
            var message: String?

            enum CodingKeys: String, CodingKey {
                case message
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // OpenAI nests the message one level down; other providers keep it flat.
                if let nested = try? container.decode(ErrorBody.self, forKey: .message) {
                    message = nested.message
                } else {
                    message = try? container.decode(String.self, forKey: .message)
                }
            }
        }
    }
}
