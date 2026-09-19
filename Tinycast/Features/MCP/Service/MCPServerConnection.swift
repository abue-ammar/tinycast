import Foundation
import Observation

/// One configured server, from handshake to tool list to call; the transport under it varies.
@MainActor
@Observable
final class MCPServerConnection {
    private(set) var status: MCPServerStatus = .stopped
    private(set) var tools: [MCPTool] = []

    @ObservationIgnored private let oauth: MCPOAuthManager?
    @ObservationIgnored let server: MCPServer
    @ObservationIgnored private let secrets: MCPSecretStore.Secrets
    @ObservationIgnored private var transport: (any MCPTransport)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var listTask: Task<Void, Never>?

    init(server: MCPServer, secrets: MCPSecretStore.Secrets, oauth: MCPOAuthManager? = nil) {
        self.oauth = oauth
        self.server = server
        self.secrets = secrets
    }

    /// A failed server is startable again: the next visit to chat is where a blip gets retried.
    var isIdle: Bool {
        switch status {
        case .stopped, .failed, .signInRequired: return true
        case .connecting, .ready: return false
        }
    }

    func start() async {
        guard isIdle else { return }
        status = .connecting
        let generation = generation
        do {
            let transport = try makeTransport()
            self.transport = transport
            try await transport.connect()
            _ = try await transport.request("initialize", Self.handshake)
            guard self.generation == generation, !Task.isCancelled else { return }
            try transport.notify("notifications/initialized", nil)
            let result = try await transport.request("tools/list")
            guard self.generation == generation, !Task.isCancelled else { return }
            tools = MCPTool.list(
                result, serverID: server.id,
                serverSlug: server.slug, serverTitle: server.title)
            status = .ready(tools: tools.count)
        } catch MCPOAuth.Failure.signInRequired {
            guard self.generation == generation else { return }
            requireSignIn()
        } catch {
            guard self.generation == generation else { return }
            fail(error.localizedDescription)
        }
    }

    func call(_ name: String, arguments: JSONValue) async throws -> (String, Bool) {
        guard let transport, status.isReady else { throw MCPTransportError.notRunning }
        do {
            let result = try await transport.request(
                "tools/call", ["name": name, "arguments": arguments.jsonObject])
            return MCPToolOutput.flatten(result)
        } catch MCPOAuth.Failure.signInRequired {
            requireSignIn()
            throw MCPOAuth.Failure.signInRequired
        }
    }

    func stop() {
        generation = UUID()
        listTask?.cancel()
        listTask = nil
        transport?.close()
        transport = nil
        tools = []
        status = .stopped
    }

    private func requireSignIn() {
        stop()
        status = .signInRequired
        oauth?.requireSignIn(server.id)
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
            var authorization: ((String?) async throws -> String)?
            if server.oauth == true {
                let server = server
                authorization = { [weak oauth] rejected in
                    guard let oauth else { throw MCPOAuth.Failure.signInRequired }
                    return try await oauth.accessToken(for: server, rejectedToken: rejected)
                }
            }
            let transport = try MCPHTTPTransport(
                url: url, headerName: headerName, headerValue: secrets.headerValue,
                authorization: authorization)
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
            guard let self, let transport = self.transport else { return }
            let generation = self.generation
            do {
                let listed = try await transport.request("tools/list")
                guard self.generation == generation, !Task.isCancelled else { return }
                self.tools = MCPTool.list(
                    listed, serverID: self.server.id, serverSlug: self.server.slug,
                    serverTitle: self.server.title)
                self.status = .ready(tools: self.tools.count)
            } catch MCPOAuth.Failure.signInRequired {
                if self.generation == generation { self.requireSignIn() }
            } catch { return }
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
