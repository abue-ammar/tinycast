import Foundation

/// One run's scratch tree, in Caches so PNGs hardlink and a crashed run's orphan ages out.
struct BackupStaging: Sendable {
    let root: URL

    init(base: URL = AppPaths.caches()) throws {
        root =
            base
            .appendingPathComponent("backup-staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var bundle: BackupBundle { BackupBundle(root: root) }

    func discard() {
        try? FileManager.default.removeItem(at: root)
    }
}
