import Foundation

/// The one fixed, cacheless route from Tinycast to TypeSafe System One.
struct NaturalCommandClient: Sendable {
    enum ClientError: LocalizedError {
        case rejectedKey
        case rateLimited
        case unavailable
        case rejectedRequest
        case invalidResponse
        case network(URLError.Code)

        var errorDescription: String? {
            switch self {
            case .rejectedKey: return "The TypeSafe API key was rejected."
            case .rateLimited: return "TypeSafe is rate-limiting requests. Try again shortly."
            case .unavailable: return "TypeSafe is temporarily unavailable."
            case .rejectedRequest: return "TypeSafe rejected the command request."
            case .invalidResponse: return "TypeSafe returned an invalid command response."
            case .network(let code):
                switch code {
                case .networkConnectionLost: return "The network connection was lost."
                case .notConnectedToInternet: return "No internet connection."
                case .timedOut: return "TypeSafe took too long to respond."
                case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                    return "TypeSafe could not be reached."
                default: return "The TypeSafe request failed."
                }
            }
        }
    }

    private static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    private static let retryDelay: Duration = .milliseconds(500)

    func interpret(
        query: String, candidates: [NaturalCommand.Candidate], apiKey: String
    ) async throws -> NaturalCommand.ChoiceAnswer {
        let request = try makeRequest(query: query, candidates: candidates, apiKey: apiKey)
        let session = Self.makeSession()
        defer { session.invalidateAndCancel() }

        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw ClientError.invalidResponse
                }
                switch response.statusCode {
                case 200:
                    do {
                        return try NaturalCommand.decodeChoiceAnswer(from: data)
                    } catch {
                        throw ClientError.invalidResponse
                    }
                case 401, 403: throw ClientError.rejectedKey
                case 422: throw ClientError.rejectedRequest
                case 429 where attempt == 0, 529 where attempt == 0:
                    try await Task.sleep(for: Self.retryDelay)
                case 429: throw ClientError.rateLimited
                case 500...599: throw ClientError.unavailable
                default: throw ClientError.rejectedRequest
                }
            } catch let error as URLError {
                throw ClientError.network(error.code)
            }
        }
        throw ClientError.unavailable
    }

    private func makeRequest(
        query: String, candidates: [NaturalCommand.Candidate], apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try NaturalCommand.requestData(query: query, candidates: candidates)
        return request
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }
}
