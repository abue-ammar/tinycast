import Foundation

/// One run's scratch tree, in Caches so PNGs hardlink and a crashed run's orphan ages out.
struct BackupStaging: Sendable {
    let root: URL

    init(base: URL = AppPaths.caches()) throws {
        let container = base.appendingPathComponent("backup-staging", isDirectory: true)
        Self.sweep(container)
        root = container.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A run killed mid-flight leaves its tree behind, and nothing else ever reclaims it.
    private static func sweep(_ container: URL) {
        let cutoff = Date().addingTimeInterval(-86_400)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let orphans =
            (try? FileManager.default.contentsOfDirectory(
                at: container, includingPropertiesForKeys: Array(keys))) ?? []
        for url in orphans {
            let modified = (try? url.resourceValues(forKeys: keys))?.contentModificationDate
            if modified ?? .distantPast < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    var bundle: BackupBundle { BackupBundle(root: root) }

    func discard() {
        try? FileManager.default.removeItem(at: root)
    }
}
