import Foundation

/// Streamable HTTP: one POST per message, answered as JSON or as an SSE stream of frames.
@MainActor
final class MCPHTTPTransport: MCPTransport {
    var onNotification: ((String, JSONValue) -> Void)?

    private let endpoint: URL
    private let headerName: String
    private let headerValue: String
    private let authorization: ((String?) async throws -> String)?
    private var sessionID: String?
    private var protocolVersion = MCPProtocol.version
    private var nextID = 1
    private var isConnected = false

    init(
        url: String, headerName: String, headerValue: String,
        authorization: ((String?) async throws -> String)? = nil
    ) throws {
        do {
            endpoint = try AIEndpointPolicy.validate(url)
        } catch {
            throw MCPTransportError.invalidEndpoint(error.localizedDescription)
        }
        self.headerName = headerName.trimmingCharacters(in: .whitespaces)
        self.headerValue = headerValue
        self.authorization = authorization
    }

    func connect() async throws {
        isConnected = true
    }

    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue {
        guard isConnected else { throw MCPTransportError.notRunning }
        let id = nextID
        nextID += 1
        let body = try MCPProtocol.request(id: id, method: method, params: params)
        let session = MCPOAuthHTTP.session(followsSameOrigin: true)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await open(
            body, in: session, timeout: MCPProtocol.timeout(for: method))
        try check(response, method: method)
        // The session id arrives on whichever response opens the session, so it is read every time.
        if let header = response.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = header }
        do {
            // An SSE answer is read as it arrives: a server need not close the stream after it.
            if response.mimeType == "text/event-stream" {
                var parser = SSEParser()
                var line = Data()
                for try await byte in bytes {
                    line.append(byte)
                    guard byte == 0x0A else { continue }
                    for payload in parser.feed(line) {
                        if let result = try answer(payload, to: id) { return result }
                    }
                    line.removeAll(keepingCapacity: true)
                }
                for payload in parser.feed(line) + parser.finish() {
                    if let result = try answer(payload, to: id) { return result }
                }
                throw MCPTransportError.malformedResponse
            }
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            if let result = try answer(String(decoding: data, as: UTF8.self), to: id) { return result }
            throw MCPTransportError.malformedResponse
        } catch let error as URLError {
            throw MCPTransportError.requestFailed(Self.networkMessage(error.code))
        }
    }

    /// Ordered rather than fire and forget, and best effort: 202 is the whole answer.
    func notify(_ method: String, _ params: [String: Any]?) async throws {
        guard isConnected else { throw MCPTransportError.notRunning }
        let body = try MCPProtocol.notification(method: method, params: params)
        let session = MCPOAuthHTTP.session(followsSameOrigin: true)
        defer { session.invalidateAndCancel() }
        _ = try? await open(body, in: session, timeout: .seconds(30))
    }

    func didNegotiate(protocolVersion: String) {
        self.protocolVersion = protocolVersion
    }

    func close() {
        isConnected = false
        sessionID = nil
        protocolVersion = MCPProtocol.version
    }

    /// One JSON-RPC message from the reply: the answer, a failure, or something to pass on.
    private func answer(_ payload: String, to id: Int) throws -> JSONValue? {
        switch MCPProtocol.parse(Data(payload.utf8)) {
        case .response(id, let result): return result
        case .failure(id, let message): throw MCPTransportError.requestFailed(message)
        case .notification(let method, let params): onNotification?(method, params)
        case .request(let requestID, let method): reply(to: requestID, method: method)
        default: break
        }
        return nil
    }

    /// A server may ask mid-answer (a `ping`); the reply is its own POST.
    private func reply(to id: JSONValue, method: String) {
        guard let body = try? MCPProtocol.reply(toRequest: id, method: method) else { return }
        Task { [weak self] in
            guard let self else { return }
            let session = MCPOAuthHTTP.session(followsSameOrigin: true)
            defer { session.invalidateAndCancel() }
            _ = try? await self.open(body, in: session, timeout: .seconds(30))
        }
    }

    private func open(
        _ body: Data, in session: URLSession, timeout: Duration
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(timeout.components.seconds)
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        let token = try await authorization?(nil)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if !headerName.isEmpty, !headerValue.isEmpty {
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MCPTransportError.malformedResponse
            }
            if response.statusCode == 401, let authorization, let token {
                let refreshed = try await authorization(token)
                request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
                let (retried, reply) = try await session.bytes(for: request)
                guard let reply = reply as? HTTPURLResponse else {
                    throw MCPTransportError.malformedResponse
                }
                if reply.statusCode == 401 { throw MCPOAuth.Failure.signInRequired }
                return (retried, reply)
            }
            return (bytes, response)
        } catch let error as URLError {
            throw MCPTransportError.requestFailed(Self.networkMessage(error.code))
        }
    }

    private func check(_ response: HTTPURLResponse, method: String) throws {
        // The TypeScript SDK's own fallback rule: a 4xx to the first POST means the 2024-11-05 shape.
        if method == "initialize", sessionID == nil, [400, 404, 405].contains(response.statusCode) {
            throw MCPTransportError.streamableHTTPUnsupported(response.statusCode)
        }
        switch response.statusCode {
        case 200...299: return
        case 401, 403:
            throw MCPTransportError.requestFailed("The server rejected Tinycast's credentials.")
        // A dropped session is the server's to end; the connection re-initializes and retries once.
        case 404 where sessionID != nil:
            sessionID = nil
            throw MCPTransportError.sessionExpired
        default:
            throw MCPTransportError.requestFailed(
                "The server answered HTTP \(response.statusCode).")
        }
    }

    private static func networkMessage(_ code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet: return "No internet connection."
        case .timedOut: return "The server took too long to respond."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "The server could not be reached."
        default: return "The request to the server failed."
        }
    }
}
