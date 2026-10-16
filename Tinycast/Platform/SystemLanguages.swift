import Foundation

/// macOS's own languages; `Locale.preferredLanguages` reads Tinycast's override once one is set.
enum SystemLanguages {
    static var preferred: [String] {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return global?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
    }
}
