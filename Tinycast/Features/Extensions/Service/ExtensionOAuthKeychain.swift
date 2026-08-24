import Foundation
import Security

/// Protocol for OAuth token storage, allowing in-memory testing without touching the Keychain.
protocol ExtensionOAuthTokenStore: Sendable {
    func get(account: String) -> String?
    func set(_ value: String, account: String) -> Bool
    func remove(account: String) -> Bool
    func removeAll(prefix: String, exactMatch: String)
}

/// Default Keychain-backed implementation of `ExtensionOAuthTokenStore`.
struct KeychainOAuthTokenStore: ExtensionOAuthTokenStore {
    private let serviceName = "com.tinycast.extensions.oauth"

    func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            return SecItemAdd(newQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func remove(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func removeAll(prefix: String, exactMatch: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let items = item as? [[String: Any]] else { return }

        for attributes in items {
            guard let account = attributes[kSecAttrAccount as String] as? String else { continue }
            if account == exactMatch || account.hasPrefix(prefix) {
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: serviceName,
                    kSecAttrAccount as String: account
                ]
                SecItemDelete(deleteQuery as CFDictionary)
            }
        }
    }
}

/// Secure token storage for Raycast Extension OAuth tokens.
/// Keyed by extension name and provider ID.
enum ExtensionOAuthKeychain {
    nonisolated(unsafe) static var store: ExtensionOAuthTokenStore = KeychainOAuthTokenStore()

    static func accountKey(extensionName: String, providerId: String?) -> String {
        if let providerId, !providerId.isEmpty {
            return "\(extensionName):\(providerId)"
        }
        return extensionName
    }

    /// Retrieve stored tokens JSON string.
    static func getTokens(extensionName: String, providerId: String?) -> String? {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        return store.get(account: account)
    }

    /// Save tokens JSON string.
    @discardableResult
    static func setTokens(_ jsonString: String, extensionName: String, providerId: String?) -> Bool {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        return store.set(jsonString, account: account)
    }

    /// Remove stored tokens.
    @discardableResult
    static func removeTokens(extensionName: String, providerId: String?) -> Bool {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        return store.remove(account: account)
    }

    /// Remove all OAuth tokens stored for an extension (e.g. on uninstall).
    static func removeAllTokens(extensionName: String) {
        store.removeAll(prefix: "\(extensionName):", exactMatch: extensionName)
    }
}
