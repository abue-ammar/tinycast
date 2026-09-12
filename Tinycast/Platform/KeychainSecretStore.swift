import Foundation
import Security

/// Login-Keychain generic passwords, one item per account inside a caller-named scope.
struct KeychainSecretStore: Sendable {
    enum StoreError: Error {
        case invalidEncoding
        case keychain(OSStatus)
    }

    private let service: String

    /// Every scope the app stores under, named here so the whole keychain surface is one list.
    static let aiAPIKeys = KeychainSecretStore(scope: "ai-api-keys")
    static let mcpSecrets = KeychainSecretStore(scope: "mcp-secrets")

    init(scope: String, bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        service = "\(bundleIdentifier ?? "com.tinycast.app").\(scope)"
    }

    func secret(for account: UUID) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query(for: account, returningData: true) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidEncoding
        }
        return secret
    }

    /// Presence check without `kSecReturn*`, so no secret bytes are materialized.
    func hasSecret(for account: UUID) throws -> Bool {
        let status = SecItemCopyMatching(
            query(for: account, returningData: false) as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        return true
    }

    func setSecret(_ secret: String, for account: UUID) throws {
        guard let data = secret.data(using: .utf8) else { throw StoreError.invalidEncoding }
        let lookup = query(for: account, returningData: false)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addition = lookup
            addition[kSecValueData as String] = data
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw StoreError.keychain(status)
        }
    }

    func removeSecret(for account: UUID) throws {
        let status = SecItemDelete(query(for: account, returningData: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    private func query(for account: UUID, returningData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.uuidString
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}
