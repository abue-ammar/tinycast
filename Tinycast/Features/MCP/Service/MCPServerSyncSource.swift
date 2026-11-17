import Foundation

extension RecordSyncSource where Record == MCPServer {
    /// Credentials stay in each Mac's Keychain, and trust is each Mac's own: it never travels.
    static func mcpServers(
        _ servers: @escaping () -> [MCPServer], apply: @escaping (MCPServer) -> Void,
        remove: @escaping (UUID) -> Bool
    ) -> Self {
        Self(
            .mcpServers,
            records: { servers().map(withoutTrust) },
            save: { server in
                apply(server)
                return true
            },
            remove: remove,
            isDuplicate: { $0.name == $1.name && $0.transport == $1.transport })
    }

    private static func withoutTrust(_ server: MCPServer) -> MCPServer {
        var server = server
        server.trust = .ask
        return server
    }
}
