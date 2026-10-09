import Foundation

/// One server's wire. Both kinds correlate their own requests; only the framing differs.
@MainActor
protocol MCPTransport: AnyObject {
    func connect() async throws
    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue
    /// Awaited, so `notifications/initialized` is on the server before `tools/list` is sent.
    func notify(_ method: String, _ params: [String: Any]?) async throws
    /// The version `initialize` settled on; HTTP has to name it on every later request.
    func didNegotiate(protocolVersion: String)
    func close()
}

extension MCPTransport {
    func request(_ method: String) async throws -> JSONValue {
        try await request(method, nil)
    }

    func didNegotiate(protocolVersion: String) {}
}

enum MCPTransportError: LocalizedError, Equatable {
    case notRunning
    case launchFailed(String)
    case invalidEndpoint(String)
    case requestFailed(String)
    case malformedResponse
    case timedOut
    /// The server forgot the `Mcp-Session-Id`; the spec's answer is a fresh `initialize`.
    case sessionExpired
    /// A 400/404/405 to the first POST: a server from before Streamable HTTP, reached over SSE.
    case streamableHTTPUnsupported(Int)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "The server is not running."
        case .launchFailed(let detail): return detail
        case .invalidEndpoint(let detail): return detail
        case .requestFailed(let detail): return detail
        case .malformedResponse: return "The server sent a response Tinycast could not read."
        case .timedOut: return "The server did not respond in time."
        case .sessionExpired: return "The server ended the session."
        case .streamableHTTPUnsupported(let status): return "The server answered HTTP \(status)."
        }
    }
}

/// What a Settings row shows, and what decides whether a server's tools are on offer.
enum MCPServerStatus: Equatable, Sendable {
    case stopped
    case signInRequired
    case connecting
    case ready(tools: Int)
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .signInRequired: return "Sign-in required"
        case .connecting: return "Connecting…"
        case .ready(let tools): return tools == 1 ? "1 tool" : "\(tools) tools"
        case .failed(let message): return message
        }
    }
}
