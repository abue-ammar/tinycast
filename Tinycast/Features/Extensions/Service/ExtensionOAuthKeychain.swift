import Foundation
import Security

/// Secure Keychain storage for Raycast Extension OAuth tokens.
/// Keyed by extension name and provider ID.
final class ExtensionOAuthKeychain: Sendable {
    private static let serviceName = "com.tinycast.extensions.oauth"

    static func accountKey(extensionName: String, providerId: String?) -> String {
        if let providerId, !providerId.isEmpty {
            return "\(extensionName):\(providerId)"
        }
        return extensionName
    }

    /// Retrieve stored tokens JSON string from Keychain.
    static func getTokens(extensionName: String, providerId: String?) -> String? {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Save tokens JSON string into Keychain.
    @discardableResult
    static func setTokens(_ jsonString: String, extensionName: String, providerId: String?) -> Bool {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        guard let data = jsonString.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(newQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    /// Remove stored tokens from Keychain.
    @discardableResult
    static func removeTokens(extensionName: String, providerId: String?) -> Bool {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Remove all OAuth tokens stored for an extension (e.g. on uninstall).
    static func removeAllTokens(extensionName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let items = item as? [[String: Any]] else { return }

        let prefix = "\(extensionName):"
        for attributes in items {
            guard let account = attributes[kSecAttrAccount as String] as? String else { continue }
            if account == extensionName || account.hasPrefix(prefix) {
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: serviceName,
                    kSecAttrAccount as String: account,
                ]
                SecItemDelete(deleteQuery as CFDictionary)
            }
        }
    }
}
