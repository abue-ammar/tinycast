import Foundation

/// How an app bundle's name is read. Apps ship `CFBundleDisplayName = ""` often enough that a blank
/// value has to read as absent: the empty name it yields draws as nothing and matches no query.
enum AppDisplayName {
    /// The Info.plist value as a name, or nil when it is absent, not a string, or blank.
    static func named(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The name a raw Info.plist carries, for callers holding one without a `Bundle` to open.
    static func inInfo(_ info: [String: Any]) -> String? {
        named(info["CFBundleDisplayName"]) ?? named(info["CFBundleName"])
    }
}

extension Bundle {
    /// The channel-aware display name, from the generated Info.plist.
    var appDisplayName: String {
        infoName("CFBundleDisplayName") ?? infoName("CFBundleName") ?? "Tinycast"
    }

    /// An installed app's name, in Finder's own order, ending at the `.app` filename.
    var installedAppName: String {
        infoName("CFBundleDisplayName") ?? infoName("CFBundleName")
            ?? bundleURL.deletingPathExtension().lastPathComponent
    }

    /// Localized: `object(forInfoDictionaryKey:)` consults `InfoPlist.strings` where the bundle has one.
    private func infoName(_ key: String) -> String? {
        AppDisplayName.named(object(forInfoDictionaryKey: key))
    }
}
