import Foundation
import Security

/// Generic-password Keychain wrapper for small secrets. Service name is the bundle identifier so
/// Dev/stable channels never share secrets.
///
/// Uses an open `SecAccess` on creation so rebuilds and debug runs do not trigger the macOS login
/// keychain password access prompt.
enum SecretStore {
    static let aiAPIKeyAccount = "ai.api-key"

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.tinycast.app"
    }

    static func setSecret(_ value: String?, account: String) {
        let query = baseQuery(account: account)
        guard let value, !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        switch SecItemUpdate(query as CFDictionary, update as CFDictionary) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            return
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        var access: SecAccess?
        if SecAccessCreate("Tinycast" as CFString, nil, &access) == errSecSuccess, let access {
            addQuery[kSecAttrAccess as String] = access
        }
        SecItemAdd(addQuery as CFDictionary, nil)
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
