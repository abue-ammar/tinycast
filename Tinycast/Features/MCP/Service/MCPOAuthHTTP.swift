import Foundation

final class MCPOAuthHTTP: NSObject, URLSessionTaskDelegate, Sendable {
    private let followsSameOrigin: Bool

    init(followsSameOrigin: Bool) { self.followsSameOrigin = followsSameOrigin }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard followsSameOrigin, let from = response.url, let to = request.url,
            MCPOAuth.sameOrigin(from, to) else { return completionHandler(nil) }
        // URLSession strips Authorization on a redirect; inside one origin it is safe to restore.
        var next = request
        for (name, value) in task.originalRequest?.allHTTPHeaderFields ?? [:]
        where next.value(forHTTPHeaderField: name) == nil {
            next.setValue(value, forHTTPHeaderField: name)
        }
        completionHandler(next)
    }

    /// OAuth endpoints refuse every redirect; an MCP endpoint may move within its own origin.
    static func session(followsSameOrigin: Bool = false) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(
            configuration: configuration, delegate: MCPOAuthHTTP(followsSameOrigin: followsSameOrigin),
            delegateQueue: nil)
    }

    static func send(_ request: URLRequest, limit: Int = 1_048_576) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw MCPOAuth.Failure.invalidMetadata }
        _ = try MCPOAuth.endpoint(url.absoluteString)
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw MCPOAuth.Failure.network }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw MCPOAuth.Failure.network }
                data.append(byte)
            }
            return (data, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw MCPOAuth.Failure.network
        }
    }

    static func json(_ url: URL, body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await send(request)
        guard (200...299).contains(response.statusCode) else { throw MCPOAuth.Failure.network }
        return data
    }
}
