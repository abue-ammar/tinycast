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
        let legacyCaches = caches.appending(path: legacy, directoryHint: .isDirectory)
        let legacyHelperCaches = caches.appending(path: legacy + ".dictation", directoryHint: .isDirectory)

        expireBackup(backup, now: now)
        // Preferences move last, so a run cut short leaves them behind and the next launch resumes.
        guard
            [legacyHome, legacyCaches, legacyHelperCaches].contains(where: {
                FileManager.default.fileExists(atPath: $0.path)
            }) || preferences.read(legacy)?.isEmpty == false
        else { return false }

        merge(legacyHome, into: home)
        merge(legacyCaches, into: caches.appending(path: current))
        merge(legacyHelperCaches, into: caches.appending(path: current + ".dictation"))
        let paths = (old: legacyHome.path + "/", new: home.path + "/")
        repointClipboardImages(in: home, from: paths.old, to: paths.new, backup: backup)
        repointJSONFiles(in: home, from: paths.old, to: paths.new, backup: backup)
        return movePreferences(
            from: legacy, to: current, repointing: paths, preferences: preferences, backup: backup)
    }

    // MARK: - Files

    private static func merge(_ source: URL, into destination: URL) {
        let files = FileManager.default
        guard files.fileExists(atPath: source.path) else { return }
        guard files.fileExists(atPath: destination.path) else {
            do {
                try files.moveItem(at: source, to: destination)
            } catch {
                let reason = error.localizedDescription
                logger.error("Moving \(source.path, privacy: .public) failed: \(reason, privacy: .public)")
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

    /// A snippet's launcher id is its file's path, so its ranking names the old folder too.
    private static func repointJSONFiles(in home: URL, from old: String, to new: String, backup: URL) {
        let escaped = old.replacingOccurrences(of: "/", with: "\\/")
        let files =
            (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                let text = String(data: data, encoding: .utf8),
                text.contains(old) || text.contains(escaped),
                let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                let repointed = try? JSONSerialization.data(
                    withJSONObject: repointing(json, from: old, to: new), options: .fragmentsAllowed)
            else { continue }
            let copy = backup.appending(path: file.lastPathComponent)
            do {
                if !FileManager.default.fileExists(atPath: copy.path) {
                    try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                    try data.write(to: copy)
                }
                try repointed.write(to: file, options: .atomic)
            } catch {
                let reason = error.localizedDescription
                let name = file.lastPathComponent
                logger.error("Repointing \(name, privacy: .public) failed: \(reason, privacy: .public)")
            }
        }
    }

    /// Every string, and every dictionary key, with the old folder's path swapped for the new one.
    private static func repointing(_ value: Any, from old: String, to new: String) -> Any {
        switch value {
        case let text as String:
            text.replacingOccurrences(of: old, with: new)
        case let list as [Any]:
            list.map { repointing($0, from: old, to: new) }
        case let table as [String: Any]:
            Dictionary(
                table.map {
                    (
                        $0.key.replacingOccurrences(of: old, with: new),
                        repointing($0.value, from: old, to: new)
                    )
                },
                uniquingKeysWith: { _, last in last })
        default:
            value
        }
    }

    // MARK: - Preferences

    /// A snippet's hotkey, alias, favorite and visibility are keyed by its file's path.
    private static func movePreferences(
        from legacy: String, to current: String, repointing paths: (old: String, new: String),
        preferences: Preferences, backup: URL
    ) -> Bool {
        guard let stored = preferences.read(legacy), !stored.isEmpty,
            var old = repointing(stored, from: paths.old, to: paths.new) as? [String: Any]
        else { return false }
        let copy = backup.appending(path: legacy + ".plist")
        if !FileManager.default.fileExists(atPath: copy.path) {
            do {
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: stored, format: .binary, options: 0)
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
    private static func repointClipboardImages(in home: URL, from old: String, to new: String, backup: URL) {
        let database = home.appending(path: "clipboard.sqlite3")
        guard FileManager.default.fileExists(atPath: database.path) else { return }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
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
