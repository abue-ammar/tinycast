import Foundation

/// One server's wire. Both kinds correlate their own requests; only the framing differs.
@MainActor
protocol MCPTransport: AnyObject {
    func connect() async throws
    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue
    func notify(_ method: String, _ params: [String: Any]?) throws
    func close()
}

extension MCPTransport {
    func request(_ method: String) async throws -> JSONValue {
        try await request(method, nil)
    }
}

enum MCPTransportError: LocalizedError, Equatable {
    case notRunning
    case launchFailed(String)
    case invalidEndpoint(String)
    case requestFailed(String)
    case malformedResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notRunning: return "The server is not running."
        case .launchFailed(let detail): return detail
        case .invalidEndpoint(let detail): return detail
        case .requestFailed(let detail): return detail
        case .malformedResponse: return "The server sent a response Tinycast could not read."
        case .timedOut: return "The server did not respond in time."
        }
    }
}

/// What a Settings row shows, and what decides whether a server's tools are on offer.
enum MCPServerStatus: Equatable, Sendable {
    case stopped
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
        case .connecting: return "Connecting…"
        case .ready(let tools): return tools == 1 ? "1 tool" : "\(tools) tools"
        case .failed(let message): return message
        }
    }
}
