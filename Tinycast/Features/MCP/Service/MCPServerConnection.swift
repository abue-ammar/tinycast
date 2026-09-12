import Foundation
import Observation

/// One configured server, from handshake to tool list to call; the transport under it varies.
@MainActor
@Observable
final class MCPServerConnection {
    private(set) var status: MCPServerStatus = .stopped
    private(set) var tools: [MCPTool] = []

    @ObservationIgnored let server: MCPServer
    @ObservationIgnored private let secrets: MCPSecretStore.Secrets
    @ObservationIgnored private var transport: (any MCPTransport)?
    @ObservationIgnored private var listTask: Task<Void, Never>?

    init(server: MCPServer, secrets: MCPSecretStore.Secrets) {
        self.server = server
        self.secrets = secrets
    }

    /// A failed server is startable again: the next visit to chat is where a blip gets retried.
    var isIdle: Bool {
        switch status {
        case .stopped, .failed: return true
        case .connecting, .ready: return false
        }
    }

    func start() async {
        guard isIdle else { return }
        status = .connecting
        do {
            let transport = try makeTransport()
            self.transport = transport
            try await transport.connect()
            _ = try await transport.request("initialize", Self.handshake)
            try transport.notify("notifications/initialized", nil)
            tools = MCPTool.list(
                try await transport.request("tools/list"), serverID: server.id,
                serverSlug: server.slug, serverTitle: server.title)
            status = .ready(tools: tools.count)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func call(_ name: String, arguments: JSONValue) async throws -> (String, Bool) {
        guard let transport, status.isReady else { throw MCPTransportError.notRunning }
        let result = try await transport.request(
            "tools/call", ["name": name, "arguments": arguments.jsonObject])
        return MCPToolOutput.flatten(result)
    }

    func stop() {
        listTask?.cancel()
        listTask = nil
        transport?.close()
        transport = nil
        tools = []
        status = .stopped
    }

    private func fail(_ message: String) {
        transport?.close()
        transport = nil
        tools = []
        status = .failed(message)
    }

    private func makeTransport() throws -> any MCPTransport {
        switch server.transport {
        case .http(let url, let headerName):
            let transport = try MCPHTTPTransport(
                url: url, headerName: headerName, headerValue: secrets.headerValue)
            transport.onNotification = { [weak self] method, _ in self?.received(method) }
            return transport
        case .stdio(let command, let arguments, _):
            let transport = MCPStdioTransport(
                command: command, arguments: arguments, environment: secrets.environment)
            transport.onNotification = { [weak self] method, _ in self?.received(method) }
            transport.onExit = { [weak self] message in self?.fail(message) }
            return transport
        }
    }

    /// A server may add or drop tools while it runs, and only says so by notification.
    private func received(_ method: String) {
        guard method == "notifications/tools/list_changed", listTask == nil else { return }
        listTask = Task { [weak self] in
            defer { self?.listTask = nil }
            guard let self, let transport = self.transport,
                let listed = try? await transport.request("tools/list")
            else { return }
            self.tools = MCPTool.list(
                listed, serverID: self.server.id, serverSlug: self.server.slug,
                serverTitle: self.server.title)
            self.status = .ready(tools: self.tools.count)
        }
    }

    private static let handshake: [String: Any] = [
        "protocolVersion": MCPProtocol.version,
        "capabilities": [:],
        "clientInfo": [
            "name": "tinycast",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        ]
    ]
}
