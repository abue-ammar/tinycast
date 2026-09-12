import Foundation
import Observation

@MainActor
@Observable
final class MCPSettingsStore {
    private let defaults: UserDefaults

    private(set) var servers: [MCPServer] {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        servers = Self.decode(defaults.data(forKey: AppSettingsKey.mcpServers.rawValue))
    }

    func server(id: UUID) -> MCPServer? {
        servers.first { $0.id == id }
    }

    func server(slug: String) -> MCPServer? {
        servers.first { $0.slug == slug }
    }

    var enabledServers: [MCPServer] {
        servers.filter(\.isEnabled)
    }

    func save(_ server: MCPServer) {
        let server = normalized(server)
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
    }

    func remove(id: UUID) {
        servers.removeAll { $0.id == id }
    }

    func setTrust(_ trust: MCPTrust, for id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].trust = trust
    }

    /// A slug is derived, never typed, so `@handle` can never name two servers or nothing at all.
    private func normalized(_ server: MCPServer) -> MCPServer {
        var server = server
        server.name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(servers.filter { $0.id != server.id }.map(\.slug))
        let derived = MCPSlug.normalize(server.name.isEmpty ? server.slug : server.name)
        if server.slug != derived || taken.contains(server.slug) {
            server.slug = MCPSlug.make(from: derived, existing: taken)
        }
        return server
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: AppSettingsKey.mcpServers.rawValue)
    }

    private static func decode(_ data: Data?) -> [MCPServer] {
        guard let data, let servers = try? JSONDecoder().decode([MCPServer].self, from: data)
        else { return [] }
        return servers
    }
}
