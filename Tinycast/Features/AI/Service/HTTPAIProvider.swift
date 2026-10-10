import Foundation

struct HTTPAIProvider: AIProvider {
    private let configuration: AIHTTPConfiguration
    private let apiKey: String

    init(configuration: AIHTTPConfiguration, apiKey: String) {
        self.configuration = configuration
        self.apiKey = apiKey
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            // Detached on purpose: the byte loop and JSON decoding never touch the main actor.
            let task = Task.detached {
                let session = Self.makeSession()
                defer { session.invalidateAndCancel() }
                do {
                    let urlRequest = try makeURLRequest(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let response = response as? HTTPURLResponse else {
                        throw AIProviderError.responseFailed(
                            "The provider returned an invalid HTTP response.")
                    }
                    guard response.statusCode == 200 else {
                        let body = await Self.body(of: bytes)
                        try Task.checkCancellation()
                        throw AIProviderError.responseFailed(
                            AIProviderFailure.description(
                                status: response.statusCode, body: body,
                                retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                                secrets: [apiKey]))
                    }
                    var decoder = AIStreamDecoder(shape: configuration.shape, secrets: [apiKey])
                    var chunk = Data()
                    chunk.reserveCapacity(2_048)
                    // Per line, not per 2 KB: a short reply must show before the stream closes.
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunk.append(byte)
                        if byte == 0x0A {
                            for event in try decoder.feed(chunk) { continuation.yield(event) }
                            chunk.removeAll(keepingCapacity: true)
                            if decoder.isTerminal { break }
                        }
                    }
                    if !chunk.isEmpty, !decoder.isTerminal {
                        for event in try decoder.feed(chunk) { continuation.yield(event) }
                    }
                    if !decoder.isTerminal {
                        for event in try decoder.finish() { continuation.yield(event) }
                    }
                    guard decoder.isTerminal else {
                        throw AIProviderError.responseFailed(
                            "The connection closed before the response completed.")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(
                        throwing: AIProviderError.responseFailed(Self.networkMessage(error.code)))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeURLRequest(_ input: AIRequest) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyAuthentication(to: &request)
        request.httpBody = try JSONSerialization.data(
            withJSONObject: AIRequestBody.make(input, configuration: configuration))
        return request
    }

    /// Every route's credential and its own identifying headers; the body knows none of this.
    private func applyAuthentication(to request: inout URLRequest) {
        switch configuration.shape {
        case .openAICompatible:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if configuration.provider == .gemini {
                request.setValue(Self.googleClientHeader, forHTTPHeaderField: "x-goog-api-client")
            } else if configuration.provider == .openRouter {
                request.setValue(Bundle.main.appDisplayName, forHTTPHeaderField: "X-OpenRouter-Title")
            }
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
    }

    private static var googleClientHeader: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "tinycast-oai/\(version)"
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }

    /// A refusal's body comes with its headers; the status is never held longer than this for one.
    private static let bodyWait: Duration = .seconds(5)

    /// What arrived by the end, the cap or the wait; a broken-off body still leaves the status.
    private static func body(of bytes: URLSession.AsyncBytes) async -> Data {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                var body = Data()
                var iterator = bytes.makeAsyncIterator()
                while body.count < AIProviderFailure.bodyLimit, let byte = try? await iterator.next() {
                    body.append(byte)
                }
                return body
            }
            group.addTask {
                try? await Task.sleep(for: bodyWait)
                return nil
            }
            var body = Data()
            // Whichever ends first stops the other; a reader stopped early hands over its part.
            for await read in group {
                if let read { body = read }
                group.cancelAll()
            }
            return body
        }
    }

    private static func networkMessage(_ code: URLError.Code) -> String {
        switch code {
        case .networkConnectionLost: return "The network connection was lost."
        case .notConnectedToInternet: return "No internet connection."
        case .timedOut: return "The provider took too long to respond."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "The provider could not be reached."
        default: return "The network request failed."
        }
    }
}
