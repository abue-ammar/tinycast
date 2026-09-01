import Foundation

/// A server's credentials: one Keychain item per server, holding what `UserDefaults` may not.
struct MCPSecretStore: Sendable {
    struct Secrets: Codable, Equatable, Sendable {
        var headerValue: String
        var environment: [String: String]

        init(headerValue: String = "", environment: [String: String] = [:]) {
            self.headerValue = headerValue
            self.environment = environment
        }

        var isEmpty: Bool { headerValue.isEmpty && environment.isEmpty }
    }

    private let keychain: KeychainSecretStore

    init(keychain: KeychainSecretStore = .mcpSecrets) {
        self.keychain = keychain
    }

    /// A read that fails reads as none: a server without its secret fails at connect, not here.
    func secrets(for serverID: UUID) -> Secrets {
        guard let stored = try? keychain.secret(for: serverID),
            let secrets = try? JSONDecoder().decode(Secrets.self, from: Data(stored.utf8))
        else { return Secrets() }
        return secrets
    }

    func save(_ secrets: Secrets, for serverID: UUID) throws {
        guard !secrets.isEmpty else {
            try keychain.removeSecret(for: serverID)
            return
        }
        let data = try JSONEncoder().encode(secrets)
        guard let encoded = String(bytes: data, encoding: .utf8) else {
            throw KeychainSecretStore.StoreError.invalidEncoding
        }
        try keychain.setSecret(encoded, for: serverID)
    }

    func remove(for serverID: UUID) throws {
        try keychain.removeSecret(for: serverID)
    }
}
