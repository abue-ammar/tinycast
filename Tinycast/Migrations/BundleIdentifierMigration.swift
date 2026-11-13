import Foundation
import SQLite3
import os

/// Carries what a `com.tinycast.app` channel left behind over to this build's bundle id.
enum BundleIdentifierMigration {
    /// The handoff writes it under the old id, so it arrives here with the old preferences.
    static let launchAtLoginKey = "BundleIdentifierHandoff.launchAtLogin"

    /// The named preference domains; a harness passes its own, since macOS never forgets a real one.
    struct Preferences {
        var read: (String) -> [String: Any]?
        var write: ([String: Any], String) -> Void
        var remove: (String) -> Void

        static var standard: Preferences {
            Preferences(
                read: UserDefaults.standard.persistentDomain(forName:),
                write: UserDefaults.standard.setPersistentDomain(_:forName:),
                remove: UserDefaults.standard.removePersistentDomain(forName:))
        }
    }

    private static let currentPrefix = "com.abueammar.tinycast"
    private static let legacyPrefix = "com.tinycast.app"
    private static let backupLifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let logger = Logger(subsystem: "com.tinycast", category: "Migration")

    static func run() {
        guard let bundleID = Bundle.main.bundleIdentifier, let legacy = legacyIdentifier(of: bundleID)
        else { return }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        if migrate(from: legacy, to: bundleID, library: library, preferences: .standard, now: Date()) {
            LaunchAtLogin.set(true)
        }
    }

    static func legacyIdentifier(of bundleID: String) -> String? {
        guard bundleID == currentPrefix || bundleID.hasPrefix(currentPrefix + ".") else { return nil }
        return legacyPrefix + bundleID.dropFirst(currentPrefix.count)
    }

    /// Moves, never overwrites, backs up what it edits; answers whether the old id opened at login.
    @discardableResult
    static func migrate(
        from legacy: String, to current: String, library: URL, preferences: Preferences, now: Date
    ) -> Bool {
        let support = library.appending(path: "Application Support", directoryHint: .isDirectory)
        let caches = library.appending(path: "Caches", directoryHint: .isDirectory)
        let legacyHome = support.appending(path: legacy, directoryHint: .isDirectory)
        let home = support.appending(path: current, directoryHint: .isDirectory)
        let backup = home.appending(path: "Migration Backup", directoryHint: .isDirectory)

        merge(legacyHome, into: home)
        merge(caches.appending(path: legacy), into: caches.appending(path: current))
        merge(
            caches.appending(path: legacy + ".dictation"),
            into: caches.appending(path: current + ".dictation"))
        repointClipboardImages(in: home, from: legacyHome, backup: backup)
        let launchesAtLogin = movePreferences(
            from: legacy, to: current, preferences: preferences, backup: backup)
        expireBackup(backup, now: now)
        return launchesAtLogin
    }

    // MARK: - Files

    private static func merge(_ source: URL, into destination: URL) {
        let files = FileManager.default
        guard files.fileExists(atPath: source.path) else { return }
        guard files.fileExists(atPath: destination.path) else {
            do {
                try files.moveItem(at: source, to: destination)
            } catch {
                logger.error(
                    "Moving \(source.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        for entry in (try? files.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [] {
            let target = destination.appending(path: entry.lastPathComponent)
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: target.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { merge(entry, into: target) }
            } else {
                try? files.moveItem(at: entry, to: target)
            }
        }
        if (try? files.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
            try? files.removeItem(at: source)
        }
    }

    private static func expireBackup(_ backup: URL, now: Date) {
        guard let created = (try? backup.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
            now.timeIntervalSince(created) > backupLifetime
        else { return }
        try? FileManager.default.removeItem(at: backup)
    }

    // MARK: - Preferences

    private static func movePreferences(
        from legacy: String, to current: String, preferences: Preferences, backup: URL
    ) -> Bool {
        guard var old = preferences.read(legacy), !old.isEmpty else { return false }
        let copy = backup.appending(path: legacy + ".plist")
        if !FileManager.default.fileExists(atPath: copy.path) {
            do {
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: old, format: .binary, options: 0)
                    .write(to: copy)
            } catch {
                logger.error(
                    "Backing up the preferences failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        let launchesAtLogin = old.removeValue(forKey: launchAtLoginKey) as? Bool ?? false
        let kept = preferences.read(current) ?? [:]
        preferences.write(old.merging(kept) { _, kept in kept }, current)
        preferences.remove(legacy)
        return launchesAtLogin
    }

    // MARK: - Clipboard

    /// Each image row holds an absolute path, and that path still names the old folder.
    private static func repointClipboardImages(in home: URL, from legacyHome: URL, backup: URL) {
        let database = home.appending(path: "clipboard.sqlite3")
        guard FileManager.default.fileExists(atPath: database.path) else { return }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        let old = legacyHome.path + "/"
        let new = home.path + "/"
        let matching = "FROM items WHERE substr(image_path, 1, length(?1)) = ?1"
        guard (integer(db, "SELECT COUNT(*) \(matching)", old) ?? 0) > 0 else { return }

        let copy = backup.appending(path: "clipboard.sqlite3")
        if !FileManager.default.fileExists(atPath: copy.path) {
            try? FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            guard execute(db, "VACUUM INTO ?1", copy.path) else {
                logger.error("Backing up the clipboard history failed; its image paths are left as they are")
                return
            }
        }
        let update = """
            UPDATE items SET image_path = ?2 || substr(image_path, length(?1) + 1) \
            WHERE substr(image_path, 1, length(?1)) = ?1
            """
        if !execute(db, update, old, new) {
            logger.error("Repointing the clipboard images failed")
        }
    }

    private static func integer(_ db: OpaquePointer?, _ sql: String, _ values: String...) -> Int? {
        guard let statement = prepare(db, sql, values) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func execute(_ db: OpaquePointer?, _ sql: String, _ values: String...) -> Bool {
        guard let statement = prepare(db, sql, values) else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private static func prepare(_ db: OpaquePointer?, _ sql: String, _ values: [String]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        return statement
    }
}
