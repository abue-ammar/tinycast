import Foundation

/// Streamable HTTP: one POST per message, answered as JSON or as an SSE stream of frames.
@MainActor
final class MCPHTTPTransport: MCPTransport {
    var onNotification: ((String, JSONValue) -> Void)?

    private let endpoint: URL
    private let headerName: String
    private let headerValue: String
    private var sessionID: String?
    private var protocolVersion = MCPProtocol.version
    private var nextID = 1
    private var isConnected = false

    init(url: String, headerName: String, headerValue: String) throws {
        do {
            endpoint = try AIEndpointPolicy.validate(url)
        } catch {
            throw MCPTransportError.invalidEndpoint(error.localizedDescription)
        }
        self.headerName = headerName.trimmingCharacters(in: .whitespaces)
        self.headerValue = headerValue
    }

    func connect() async throws {
        isConnected = true
    }

    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue {
        guard isConnected else { throw MCPTransportError.notRunning }
        let id = nextID
        nextID += 1
        let body = try MCPProtocol.request(id: id, method: method, params: params)
        let timeout: TimeInterval = method == "tools/call" ? 60 : 15
        let (data, response) = try await post(body, timeout: timeout)
        try check(response)
        // The session id arrives on whichever response opens the session, so it is read every time.
        if let header = response.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = header }
        for message in Self.messages(in: data, contentType: response.mimeType) {
            switch message {
            case .response(id, let result): return result
            case .failure(id, let message): throw MCPTransportError.requestFailed(message)
            case .notification(let method, let params): onNotification?(method, params)
            default: continue
            }
        }
        throw MCPTransportError.malformedResponse
    }

    func notify(_ method: String, _ params: [String: Any]?) throws {
        guard isConnected else { throw MCPTransportError.notRunning }
        let body = try MCPProtocol.notification(method: method, params: params)
        // Fire and forget: a notification has no reply to wait for, and 202 is the whole answer.
        Task { [weak self] in _ = try? await self?.post(body, timeout: 15) }
    }

    func close() {
        isConnected = false
        sessionID = nil
    }

    private func post(
        _ body: Data, timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if !headerName.isEmpty, !headerValue.isEmpty {
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        }
        let session = Self.makeSession()
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MCPTransportError.malformedResponse
            }
            return (data, response)
        } catch let error as URLError {
            throw MCPTransportError.requestFailed(Self.networkMessage(error.code))
        }
    }

    private func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 401, 403:
            throw MCPTransportError.requestFailed("The server rejected Tinycast's credentials.")
        // A dropped session is the server's to end; the next request opens a fresh one.
        case 404 where sessionID != nil:
            sessionID = nil
            throw MCPTransportError.requestFailed("The server ended the session.")
        default:
            throw MCPTransportError.requestFailed(
                "The server answered HTTP \(response.statusCode).")
        }
    }

    /// A JSON body is one message; an SSE body is every `data:` frame it carried.
    private static func messages(in data: Data, contentType: String?) -> [MCPProtocol.Message] {
        guard contentType == "text/event-stream" else { return [MCPProtocol.parse(data)] }
        var parser = SSEParser()
        return (parser.feed(data) + parser.finish()).map { MCPProtocol.parse(Data($0.utf8)) }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
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
