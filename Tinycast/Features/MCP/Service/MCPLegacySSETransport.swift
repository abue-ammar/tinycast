import Foundation

/// The 2024-11-05 HTTP+SSE transport: a long-lived `GET` stream whose first `endpoint` event names
/// where to POST, after which every answer arrives as a `message` event on that same stream.
/// Only reached when a server refuses Streamable HTTP's first POST.
@MainActor
final class MCPLegacySSETransport: MCPTransport {
    private struct PendingRequest {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeout: Task<Void, Never>
    }

    var onNotification: ((String, JSONValue) -> Void)?
    /// The stream ended on the server's side; Tinycast closing it never calls this.
    var onClose: ((String) -> Void)?

    private let streamURL: URL
    private let headerName: String
    private let headerValue: String
    private let authorization: ((String?) async throws -> String)?
    private var postURL: URL?
    private var session: URLSession?
    private var reader: Task<Void, Never>?
    private var endpointWaiters: [CheckedContinuation<URL, Error>] = []
    private var pending: [Int: PendingRequest] = [:]
    private var nextID = 1
    private var isConnected = false

    /// How long a server may take to announce its POST endpoint after the stream opens.
    private static let endpointTimeout: Duration = .seconds(30)

    init(
        url: String, headerName: String, headerValue: String,
        authorization: ((String?) async throws -> String)? = nil
    ) throws {
        do {
            streamURL = try AIEndpointPolicy.validate(url)
        } catch {
            throw MCPTransportError.invalidEndpoint(error.localizedDescription)
        }
        self.headerName = headerName.trimmingCharacters(in: .whitespaces)
        self.headerValue = headerValue
        self.authorization = authorization
    }

    func connect() async throws {
        if isConnected, postURL != nil { return }
        isConnected = true
        let session = MCPOAuthHTTP.session(followsSameOrigin: true)
        self.session = session
        var request = URLRequest(url: streamURL)
        request.httpMethod = "GET"
        // The stream is meant to stay open; only the endpoint wait below is bounded.
        request.timeoutInterval = 24 * 60 * 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let bytes: URLSession.AsyncBytes
        let response: HTTPURLResponse
        do {
            (bytes, response) = try await authorized(request) { try await session.bytes(for: $0) }
        } catch {
            close()
            throw error
        }
        guard (200...299).contains(response.statusCode),
            response.mimeType == "text/event-stream"
        else {
            close()
            throw MCPTransportError.requestFailed(
                "The server answered HTTP \(response.statusCode) to its event stream.")
        }
        reader = Task { [weak self] in await self?.read(bytes) }
        _ = try await endpoint()
    }

    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue {
        guard isConnected else { throw MCPTransportError.notRunning }
        let target = try await endpoint()
        let id = nextID
        nextID += 1
        let body = try MCPProtocol.request(id: id, method: method, params: params)
        let timeout = MCPProtocol.timeout(for: method)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let watchdog = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.finish(id, with: .failure(MCPTransportError.timedOut))
                }
                pending[id] = PendingRequest(continuation: continuation, timeout: watchdog)
                // The POST is only accepted (202); its answer comes back on the stream.
                Task { [weak self] in
                    do {
                        try await self?.post(body, to: target)
                    } catch {
                        self?.finish(id, with: .failure(error))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, with: .failure(CancellationError())) }
        }
    }

    func notify(_ method: String, _ params: [String: Any]?) async throws {
        guard isConnected else { throw MCPTransportError.notRunning }
        let body = try MCPProtocol.notification(method: method, params: params)
        try await post(body, to: try await endpoint())
    }

    func close() {
        isConnected = false
        reader?.cancel()
        reader = nil
        session?.invalidateAndCancel()
        session = nil
        postURL = nil
        failEverything(MCPTransportError.notRunning)
    }

    // MARK: - The stream

    private func read(_ bytes: URLSession.AsyncBytes) async {
        var stream = MCPEventStream()
        var line = Data()
        do {
            for try await byte in bytes {
                line.append(byte)
                guard byte == 0x0A else { continue }
                for event in stream.feed(line) { handle(event) }
                line.removeAll(keepingCapacity: true)
            }
            for event in stream.feed(line + Data([0x0A, 0x0A])) { handle(event) }
        } catch {}
        guard isConnected, !Task.isCancelled else { return }
        let message = "The server closed its event stream."
        isConnected = false
        failEverything(MCPTransportError.requestFailed(message))
        onClose?(message)
    }

    private func handle(_ event: MCPEventStream.Event) {
        switch event.name {
        case "endpoint":
            // Held to the stream's origin: a credential never follows an endpoint elsewhere.
            guard let url = MCPEventStream.endpoint(event.data, relativeTo: streamURL) else {
                failEndpointWaiters(
                    MCPTransportError.requestFailed(
                        "The server announced an endpoint on another origin."))
                return
            }
            postURL = url
            let waiters = endpointWaiters
            endpointWaiters = []
            for waiter in waiters { waiter.resume(returning: url) }
        case "message":
            switch MCPProtocol.parse(Data(event.data.utf8)) {
            case .response(let id, let result): finish(id, with: .success(result))
            case .failure(let id, let message):
                finish(id, with: .failure(MCPTransportError.requestFailed(message)))
            case .notification(let method, let params): onNotification?(method, params)
            case .request(let id, let method): reply(to: id, method: method)
            case .invalid: break
            }
        default:
            break
        }
    }

    private func endpoint() async throws -> URL {
        if let postURL { return postURL }
        guard isConnected else { throw MCPTransportError.notRunning }
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.endpointTimeout)
            guard !Task.isCancelled else { return }
            self?.failEndpointWaiters(MCPTransportError.timedOut)
        }
        defer { watchdog.cancel() }
        return try await withCheckedThrowingContinuation { endpointWaiters.append($0) }
    }

    private func reply(to id: JSONValue, method: String) {
        guard let postURL, let body = try? MCPProtocol.reply(toRequest: id, method: method) else {
            return
        }
        Task { [weak self] in try? await self?.post(body, to: postURL) }
    }

    // MARK: - Posting

    private func post(_ body: Data, to url: URL) async throws {
        guard let session else { throw MCPTransportError.notRunning }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await authorized(request) { try await session.data(for: $0) }
        guard (200...299).contains(response.statusCode) else {
            throw MCPTransportError.requestFailed("The server answered HTTP \(response.statusCode).")
        }
    }

    /// The header or bearer token on every request, and one refresh when a token is refused.
    private func authorized<Body: Sendable>(
        _ request: URLRequest, _ send: @MainActor (URLRequest) async throws -> (Body, URLResponse)
    ) async throws -> (Body, HTTPURLResponse) {
        var request = request
        let token = try await authorization?(nil)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if !headerName.isEmpty, !headerValue.isEmpty {
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        }
        do {
            let (body, response) = try await send(request)
            guard let response = response as? HTTPURLResponse else {
                throw MCPTransportError.malformedResponse
            }
            guard response.statusCode == 401, let authorization, let token else {
                if [401, 403].contains(response.statusCode) {
                    throw MCPTransportError.requestFailed(
                        "The server rejected Tinycast's credentials.")
                }
                return (body, response)
            }
            let refreshed = try await authorization(token)
            request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
            let (retried, reply) = try await send(request)
            guard let reply = reply as? HTTPURLResponse else {
                throw MCPTransportError.malformedResponse
            }
            if reply.statusCode == 401 { throw MCPOAuth.Failure.signInRequired }
            return (retried, reply)
        } catch let error as URLError {
            throw MCPTransportError.requestFailed(
                error.code == .timedOut
                    ? "The server took too long to respond." : "The request to the server failed.")
        }
    }

    // MARK: - Bookkeeping

    private func finish(_ id: Int, with result: Result<JSONValue, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    private func failEndpointWaiters(_ error: Error) {
        let waiters = endpointWaiters
        endpointWaiters = []
        for waiter in waiters { waiter.resume(throwing: error) }
    }

    private func failEverything(_ error: Error) {
        failEndpointWaiters(error)
        for id in Array(pending.keys) { finish(id, with: .failure(error)) }
    }
}
