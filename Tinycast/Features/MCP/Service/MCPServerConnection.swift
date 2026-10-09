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
            var transport = try makeTransport()
            self.transport = transport
            do {
                try await open(transport, generation: generation)
            } catch MCPTransportError.streamableHTTPUnsupported(let status) {
                // A server from before Streamable HTTP: the same URL speaks the 2024-11-05 shape.
                transport.close()
                guard let legacy = try makeLegacyTransport() else {
                    throw MCPTransportError.streamableHTTPUnsupported(status)
                }
                transport = legacy
                self.transport = legacy
                try await open(legacy, generation: generation)
            }
            if isCurrent(generation) { status = .ready(tools: tools.count) }
        } catch MCPOAuth.Failure.signInRequired {
            guard self.generation == generation else { return }
            requireSignIn()
        } catch {
            guard self.generation == generation else { return }
            // Cancelled mid-handshake: back to stopped, so the row never sticks at "Connecting…".
            if error is CancellationError || Task.isCancelled {
                transport?.close()
                transport = nil
                tools = []
                status = .stopped
                return
            }
            fail(error.localizedDescription)
        }
        if self.generation == generation, status == .connecting {
            transport?.close()
            transport = nil
            tools = []
            status = .stopped
        }
    }

    func call(_ name: String, arguments: JSONValue) async throws -> (String, Bool) {
        guard transport != nil, status.isReady else { throw MCPTransportError.notRunning }
        let params: [String: Any] = ["name": name, "arguments": arguments.jsonObject]
        do {
            let result = try await withSession { transport in
                try await transport.request("tools/call", params)
            }
            return MCPToolOutput.flatten(result)
        } catch MCPOAuth.Failure.signInRequired {
            requireSignIn()
            throw MCPOAuth.Failure.signInRequired
        }
    }

    /// Handshake on a transport: a negotiated version, `initialized` delivered, every tool page.
    private func open(_ transport: any MCPTransport, generation: UUID) async throws {
        try await transport.connect()
        let result = try await transport.request("initialize", Self.handshake)
        try checkCurrent(generation)
        transport.didNegotiate(protocolVersion: MCPProtocol.negotiatedVersion(result))
        try await transport.notify("notifications/initialized", nil)
        try checkCurrent(generation)
        let listed = try await listTools(on: transport)
        try checkCurrent(generation)
        tools = listed
    }

    /// `tools/list` is paginated: a server with many tools hands back a `nextCursor` until done.
    private func listTools(on transport: any MCPTransport) async throws -> [MCPTool] {
        var listed: [MCPTool] = []
        var cursor: String?
        for _ in 0..<MCPProtocol.maxListPages {
            let params: [String: Any]? = cursor.map { ["cursor": $0] }
            let page = try await transport.request("tools/list", params)
            listed += MCPTool.list(
                page, serverID: server.id, serverSlug: server.slug, serverTitle: server.title)
            cursor = MCPProtocol.nextCursor(page)
            if cursor == nil { break }
        }
        return listed
    }

    /// A server that forgot its session gets one fresh `initialize`, then the request again.
    private func withSession(
        _ body: @MainActor (any MCPTransport) async throws -> JSONValue
    ) async throws -> JSONValue {
        guard let transport else { throw MCPTransportError.notRunning }
        do {
            return try await body(transport)
        } catch MCPTransportError.sessionExpired {
            let generation = generation
            try await open(transport, generation: generation)
            guard self.transport === transport else { throw MCPTransportError.notRunning }
            status = .ready(tools: tools.count)
            return try await body(transport)
        }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        self.generation == generation && !Task.isCancelled
    }

    private func checkCurrent(_ generation: UUID) throws {
        guard isCurrent(generation) else { throw CancellationError() }
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
        oauth?.requireSignIn(server)
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
                url: url, headerName: headerName, headerValue: secrets.headerValue,
                authorization: authorization())
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

    /// The 2024-11-05 HTTP+SSE transport, tried only when Streamable HTTP was refused.
    private func makeLegacyTransport() throws -> (any MCPTransport)? {
        guard case .http(let url, let headerName) = server.transport else { return nil }
        let transport = try MCPLegacySSETransport(
            url: url, headerName: headerName, headerValue: secrets.headerValue,
            authorization: authorization())
        transport.onNotification = { [weak self] method, _ in self?.received(method) }
        transport.onClose = { [weak self] message in self?.fail(message) }
        return transport
    }

    private func authorization() -> ((String?) async throws -> String)? {
        guard server.oauth == true else { return nil }
        let server = server
        return { [weak oauth] rejected in
            guard let oauth else { throw MCPOAuth.Failure.signInRequired }
            return try await oauth.accessToken(for: server, rejectedToken: rejected)
        }
    }

    /// A server may add or drop tools while it runs, and only says so by notification.
    private func received(_ method: String) {
        guard method == "notifications/tools/list_changed", listTask == nil, status.isReady else {
            return
        }
        listTask = Task { [weak self] in
            defer { self?.listTask = nil }
            guard let self, let transport = self.transport else { return }
            let generation = self.generation
            do {
                let listed = try await self.listTools(on: transport)
                guard self.generation == generation, !Task.isCancelled else { return }
                self.tools = listed
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
