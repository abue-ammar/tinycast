import Foundation

/// Secure local storage for secrets, isolated per channel in Application Support with `0600` permissions.
/// Avoids macOS Security Agent modal password prompts on self-signed debug builds.
enum SecretStore {
    static let aiAPIKeyAccount = "ai.api-key"

    private static var fileURL: URL {
        AppPaths.applicationSupport().appendingPathComponent("secrets.json")
    }

    static func setSecret(_ value: String?, account: String) {
        var map = load()
        if let value, !value.isEmpty {
            map[account] = value
        } else {
            map.removeValue(forKey: account)
        }
        save(map)
    }

    static func secret(account: String) -> String? {
        load()[account]
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
            let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    private static func save(_ map: [String: String]) {
        let url = fileURL
        if map.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
