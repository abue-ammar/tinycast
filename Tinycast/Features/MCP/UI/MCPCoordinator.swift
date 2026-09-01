import Foundation

/// MCP's action surface: what is running, what the model may call, and who is asked first.
@MainActor
final class MCPCoordinator {
    private let settings: AppSettings
    private let store: MCPSettingsStore
    private let manager: MCPServerManager
    private unowned let core: AppCore

    /// Servers this conversation has already been asked about; a new chat asks again.
    private var chatGrants: (chat: UUID, servers: Set<UUID>) = (UUID(), [])

    init(
        settings: AppSettings, store: MCPSettingsStore, manager: MCPServerManager, core: AppCore
    ) {
        self.settings = settings
        self.store = store
        self.manager = manager
        self.core = core
    }

    var isActive: Bool { settings.aiEnabled && settings.mcpEnabled }

    /// Off means off: no connection, no resident process, and nothing offered to a model.
    func applyEnabled() {
        guard isActive else {
            manager.stop()
            return
        }
        manager.reconcile(store.enabledServers)
    }

    /// Connecting on the way into chat, so the first send does not wait on every handshake.
    func warmUp() {
        guard isActive else { return }
        manager.reconcile(store.enabledServers)
    }

    var slugs: Set<String> {
        guard isActive else { return [] }
        return Set(store.enabledServers.map(\.slug))
    }

    func server(slug: String) -> MCPServer? {
        guard isActive else { return nil }
        return store.enabledServers.first { $0.slug == slug }
    }

    /// What this turn may reach: everything enabled, or one server when `@slug` named it.
    func tools(scopedTo slug: String?) -> [AITool] {
        guard isActive else { return [] }
        return manager.tools
            .filter { tool in
                guard slug == nil || tool.serverSlug == slug else { return false }
                return store.server(id: tool.serverID)?.trust != .never
            }
            .map(\.aiTool)
    }

    func invoke(_ call: AIToolCall, in chat: UUID) async -> AIToolResult {
        guard let route = MCPToolName.parse(call.name),
            let server = server(slug: route.slug),
            let connection = manager.connection(slug: route.slug)
        else {
            return .failure(call.id, "That tool is no longer connected.")
        }
        guard await isPermitted(server, tool: route.tool, in: chat) else {
            return .failure(call.id, "The user declined this tool call.")
        }
        manager.markUsed()
        do {
            let (content, isError) = try await connection.call(
                route.tool, arguments: JSONValue(data: Data(call.arguments.utf8)) ?? .object([:]))
            return AIToolResult(callID: call.id, content: content, isError: isError)
        } catch {
            return .failure(call.id, error.localizedDescription)
        }
    }

    private func isPermitted(_ server: MCPServer, tool: String, in chat: UUID) async -> Bool {
        if chatGrants.chat != chat { chatGrants = (chat, []) }
        switch MCPTrustPolicy.decide(
            trust: server.trust, isGrantedForChat: chatGrants.servers.contains(server.id))
        {
        case .allow: return true
        case .refuse: return false
        case .ask: break
        }
        switch await ask(server, tool: tool) {
        case .always:
            store.setTrust(.always, for: server.id)
            return true
        case .thisChat:
            chatGrants.servers.insert(server.id)
            return true
        case .refuse:
            return false
        }
    }

    /// Escape refuses this one call: a dialog can grant a server, only Settings can withhold one.
    private func ask(_ server: MCPServer, tool: String) async -> MCPTrustChoice {
        let choices: [MCPTrustChoice] = [.always, .thisChat, .refuse]
        let index = await core.choose(
            title: "Let \(server.title) run its tools?",
            message: "The model wants to call \u{201C}\(tool)\u{201D}. Tinycast did not write this "
                + "server and cannot vouch for what it does.",
            symbol: "wrench.and.screwdriver",
            options: [
                DialogAction(title: "Always Allow"),
                DialogAction(title: "Allow This Chat"),
                DialogAction(title: "Don't Allow", role: .cancel)
            ],
            defaultIndex: 1)
        return choices.indices.contains(index) ? choices[index] : .refuse
    }
}
