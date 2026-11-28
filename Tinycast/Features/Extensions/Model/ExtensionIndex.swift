import Foundation

/// The Store index read against this build: what installs, what updates, and what must stop.
nonisolated struct ExtensionIndex: Sendable {
    /// One installed extension, as the index decisions need it.
    struct Installed: Sendable, Equatable {
        let id: String
        let version: String
        let isPinned: Bool
    }

    enum Status: Sendable, Equatable {
        case current
        case update(ExtensionIndexFile.Entry)
        /// A newer version exists, but Don't Update holds this one; its own Update still works.
        case pinned(ExtensionIndexFile.Entry)
        case needsNewerTinycast
        case revoked
    }

    private let entries: [String: ExtensionIndexFile.Entry]
    private let revoked: [String: Set<String>]
    private let host: ExtensionAPIVersion

    init(_ file: ExtensionIndexFile, host: ExtensionAPIVersion) {
        entries = Dictionary(file.extensions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        revoked = file.revoked.reduce(into: [:]) { $0[$1.id, default: []].formUnion($1.versions) }
        self.host = host
    }

    func canInstall(_ entry: ExtensionIndexFile.Entry) -> Bool {
        host.canRun(entry.api) && !isRevoked(entry.id, version: entry.version)
    }

    /// The decoder drops an entry it cannot read, so a missing one is newer, never removed.
    func status(of installed: Installed) -> Status {
        if isRevoked(installed.id, version: installed.version) { return .revoked }
        guard let entry = entries[installed.id] else { return .needsNewerTinycast }
        guard Self.isVersion(entry.version, newerThan: installed.version),
            !isRevoked(entry.id, version: entry.version)
        else { return .current }
        guard host.canRun(entry.api) else { return .needsNewerTinycast }
        return installed.isPinned ? .pinned(entry) : .update(entry)
    }

    /// What auto-update and Update All install: pinned ones and those needing a newer build stay.
    func updates(for installed: [Installed]) -> [ExtensionIndexFile.Entry] {
        installed.compactMap {
            guard case .update(let entry) = status(of: $0) else { return nil }
            return entry
        }
    }

    private func isRevoked(_ id: String, version: String) -> Bool {
        revoked[id]?.contains(version) == true
    }

    /// `x.y.z` compared part by part as numbers, so 1.10.0 is newer than 1.9.0.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let currentParts = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(candidateParts.count, currentParts.count)
        let padded = { (parts: [Int]) in parts + Array(repeating: 0, count: count - parts.count) }
        return padded(currentParts).lexicographicallyPrecedes(padded(candidateParts))
    }
}
