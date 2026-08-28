import Foundation
import SQLite3

// Spelled as the C macro in sqlite3.h, which isn't imported into Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Moves the stores that outlive a cache out of `~/Library/Caches`, before anything opens them.
enum StorageRelocation {
    /// The tripwire in `Tests/storage-relocation-test.swift` fails the suite once this date passes.
    static let removeAfter =
        DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: .gmt,
            year: 2026, month: 9, day: 5
        ).date ?? .distantPast

    private static let databaseName = "clipboard.sqlite3"
    private static let imagesName = "images"
    private static let databaseFiles = [databaseName, databaseName + "-wal", databaseName + "-shm"]
    private static let jsonFiles = [
        "calculator-history.json", "launcher-ranking.json", "emoji-frequency.json"
    ]

    /// Idempotent and driven by what is on disk: a "done" flag would be the residue this avoids.
    static func run(
        caches: URL = AppPaths.caches(), support: URL = AppPaths.applicationSupport()
    ) {
        for name in jsonFiles { move(name, from: caches, to: support) }
        let movedImages = moveImages(from: caches, to: support)
        // `map` before `contains`: every file has to move, not just up to the first one that did.
        let movedDatabase = databaseFiles.map { move($0, from: caches, to: support) }.contains(true)
        guard movedImages || movedDatabase else { return }
        rewriteImagePaths(
            in: support.appendingPathComponent(databaseName),
            from: caches.appendingPathComponent(imagesName).path + "/",
            to: support.appendingPathComponent(imagesName).path + "/")
    }

    @discardableResult
    private static func move(_ name: String, from caches: URL, to support: URL) -> Bool {
        let source = caches.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else { return false }
        // A destination that already exists is the live copy; the stale source is left alone.
        return
            (try? FileManager.default.moveItem(
                at: source, to: support.appendingPathComponent(name))) != nil
    }

    /// The one move with a fallback: a rename cannot merge, and giving up orphans every thumbnail.
    private static func moveImages(from caches: URL, to support: URL) -> Bool {
        let source = caches.appendingPathComponent(imagesName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else { return false }
        let destination = support.appendingPathComponent(imagesName, isDirectory: true)
        if (try? FileManager.default.moveItem(at: source, to: destination)) != nil { return true }
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? [] {
            try? FileManager.default.moveItem(
                at: source.appendingPathComponent(name),
                to: destination.appendingPathComponent(name))
        }
        // Only once it has emptied: a blob that could not move is still the only copy.
        if (try? FileManager.default.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: source)
        }
        return true
    }

    /// `image_path` is absolute, so the rows follow the blobs; an external reference stays put.
    private static func rewriteImagePaths(in database: URL, from old: String, to new: String) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return
        }
        defer { sqlite3_close_v2(db) }
        var stmt: OpaquePointer?
        // Prefix-matched with `substr`, not `LIKE`, whose `%` and `_` a home directory may hold.
        let sql = """
            UPDATE items SET image_path = ?1 || substr(image_path, length(?2) + 1)
            WHERE substr(image_path, 1, length(?2)) = ?2
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, new, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, old, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }
}
