import Foundation

enum FileViewerTarget: Equatable, Sendable {
    case finder
    case application(bundleID: String)

    var bundleID: String {
        switch self {
        case .finder: FileViewerPolicy.finderBundleID
        case .application(let bundleID): bundleID
        }
    }
}

enum FileViewerPolicy {
    static let finderBundleID = "com.apple.finder"
    static let configuredBundleIDKey = "fileManagerBundleID"
    static let systemFileViewerKey = "NSFileViewer"

    static func target(configuredBundleID: String?, systemBundleID: String?) -> FileViewerTarget {
        normalized(configuredBundleID).map(target(for:))
            ?? normalized(systemBundleID).map(target(for:))
            ?? .finder
    }

    static func resolvedTarget(
        configuredBundleID: String?, systemBundleID: String?,
        isAvailable: (String) -> Bool
    ) -> FileViewerTarget {
        let preferred = target(
            configuredBundleID: configuredBundleID, systemBundleID: systemBundleID)
        if isAvailable(preferred.bundleID) { return preferred }

        let system = normalized(systemBundleID).map(target(for:)) ?? .finder
        if isAvailable(system.bundleID) { return system }
        return .finder
    }

    static func isConfiguredApplicationMissing(
        configuredBundleID: String?, isAvailable: (String) -> Bool
    ) -> Bool {
        guard let bundleID = normalized(configuredBundleID), target(for: bundleID) != .finder
        else { return false }
        return !isAvailable(bundleID)
    }

    private static func target(for bundleID: String) -> FileViewerTarget {
        bundleID.caseInsensitiveCompare(finderBundleID) == .orderedSame
            ? .finder : .application(bundleID: bundleID)
    }

    private static func normalized(_ bundleID: String?) -> String? {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
