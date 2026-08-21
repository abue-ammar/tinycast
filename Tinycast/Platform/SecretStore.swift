import Foundation
import Security

/// Generic-password Keychain wrapper for small secrets. Service name is the bundle identifier so
/// Dev/stable channels never share secrets.
enum SecretStore {
    static let aiAPIKeyAccount = "ai.api-key"

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.tinycast.app"
    }

    static func setSecret(_ value: String?, account: String) {
        var query = baseQuery(account: account)
        guard let value, !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        // Update first: adding without checking would duplicate the item on every save.
        let update: [String: Any] = [kSecValueData as String: data]
        switch SecItemUpdate(query as CFDictionary, update as CFDictionary) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            return
        }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func secret(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
