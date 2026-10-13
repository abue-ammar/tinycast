import Foundation

struct UninstallTarget: Hashable, Sendable {
    let bundleURL: URL
    let bundleID: String?
    let displayName: String
    /// Some apps name their support folder after `CFBundleName` rather than the display name.
    let bundleName: String?
}

enum UninstallEvidence: String, Hashable, Sendable, CaseIterable {
    case bundle
    case bundleID
    case groupContainer
    case displayName
    case binSymlink

    /// Weak evidence names itself on the row; proof-grade matches stay silent.
    var label: String? {
        switch self {
        case .displayName: return "matched by name"
        case .binSymlink: return "command-line tool"
        case .bundle, .bundleID, .groupContainer: return nil
        }
    }
}

/// Matching-ready form of a target; `make` applies every guard rail up front.
struct UninstallIdentity: Hashable, Sendable {
    /// Case-folded bundle ID, or nil when the target has none.
    let bundleID: String?
    /// False for a two-component ID: prefix-matching `com.adobe` would sweep a whole vendor.
    let allowsBundleIDPrefixMatch: Bool
    /// Other installed apps' folded IDs, so one channel can't claim another's artifacts.
    let otherBundleIDs: Set<String>
    /// Case-folded names safe enough to claim a whole directory.
    let names: [String]
    let bundleURL: URL

    /// Three, not four, so a three-letter app's folder still matches. The guards carry the safety.
    static let minimumNameLength = 3

    /// Standard Library subdirectories, so an app sharing the name can never claim them.
    static let reservedNames: Set<String> = [
        "apple", "application support", "application scripts", "autosave information", "caches",
        "containers", "cookies", "crashreporter", "fonts", "frameworks", "group containers",
        "httpstorages", "keychains", "launchagents", "launchdaemons", "logs", "metadata",
        "mobilesync", "preferences", "privilegedhelpertools", "scripts", "services", "sync",
        "syncservices", "webkit"
    ]

    /// Nil refuses the uninstall; `ownBundleID` is the running identity, so Dev refuses itself.
    static func make(
        target: UninstallTarget, otherAppNames: [String], otherBundleIDs: [String] = [],
        ownBundleID: String?, ownBundleURL: URL
    ) -> UninstallIdentity? {
        if let ownBundleID, let bundleID = target.bundleID,
            folded(bundleID) == folded(ownBundleID)
        {
            return nil
        }
        if target.bundleURL.standardizedFileURL == ownBundleURL.standardizedFileURL { return nil }

        let bundleID = target.bundleID.map(folded).flatMap { $0.isEmpty ? nil : $0 }
        let names = safeNames(
            displayName: target.displayName, bundleName: target.bundleName,
            otherAppNames: otherAppNames)
        guard bundleID != nil || !names.isEmpty else { return nil }

        return UninstallIdentity(
            bundleID: bundleID,
            allowsBundleIDPrefixMatch: (bundleID?.split(separator: ".").count ?? 0) >= 3,
            otherBundleIDs: Set(otherBundleIDs.map(folded)).subtracting([bundleID].compactMap { $0 }),
            names: names,
            bundleURL: target.bundleURL.standardizedFileURL)
    }

    /// Gates a name must clear: long enough, not a macOS folder, not shared with another app.
    static func safeNames(
        displayName: String, bundleName: String?, otherAppNames: [String]
    ) -> [String] {
        let taken = Set(otherAppNames.map(folded))
        var result: [String] = []
        for candidate in [displayName, bundleName].compactMap({ $0 }) {
            let name = folded(candidate)
            guard name.count >= minimumNameLength, !reservedNames.contains(name),
                !taken.contains(name), !result.contains(name)
            else { continue }
            result.append(name)
        }
        return result
    }

    static func folded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
