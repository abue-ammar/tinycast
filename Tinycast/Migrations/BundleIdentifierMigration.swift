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

    /// A path through an old folder however it is spelled: absolute, `~/`, `$HOME`, escaped or a URL.
    struct PathRewrite {
        let legacy: String
        private let expression: NSRegularExpression?
        private let template: String

        init(legacy: String, current: String) {
            self.legacy = legacy
            // A whole path component, since `com.tinycast.app` also starts `com.tinycast.app.beta`.
            expression = try? NSRegularExpression(
                pattern: "(?<=/|%2[Ff])" + NSRegularExpression.escapedPattern(for: legacy)
                    + #"(\.dictation)?(?![A-Za-z0-9._-])"#)
            template = NSRegularExpression.escapedTemplate(for: current) + "$1"
        }

        func rewriting(_ text: String) -> String {
            guard let expression, text.contains(legacy) else { return text }
            return expression.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }

        /// Strings, dictionary keys, and JSON-encoded data such as a custom command's settings.
        func rewriting(value: Any) -> Any {
            switch value {
            case let text as String:
                rewriting(text)
            case let data as Data:
                rewriting(json: data)
            case let list as [Any]:
                list.map { rewriting(value: $0) }
            case let table as [String: Any]:
                Dictionary(
                    table.map { (rewriting($0.key), rewriting(value: $0.value)) },
                    uniquingKeysWith: { _, last in last })
            default:
                value
            }
        }

        /// JSON only: a binary property list would break when a path inside it changes length.
        private func rewriting(json data: Data) -> Data {
            guard let text = String(bytes: data, encoding: .utf8), text.contains(legacy),
                (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
            else { return data }
            return Data(rewriting(text).utf8)
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
        let launchesAtLogin = migrate(
            from: legacy, to: bundleID, library: library,
            settingsFile: AppPaths.settingsFile(bundleID: bundleID), preferences: .standard, now: Date())
        if launchesAtLogin { LaunchAtLogin.set(true) }
    }

    static func legacyIdentifier(of bundleID: String) -> String? {
        guard bundleID == currentPrefix || bundleID.hasPrefix(currentPrefix + ".") else { return nil }
        return legacyPrefix + bundleID.dropFirst(currentPrefix.count)
    }

    /// Moves, never overwrites, backs up what it edits; answers whether the old id opened at login.
    @discardableResult
    static func migrate(
        from legacy: String, to current: String, library: URL, settingsFile: URL?,
        preferences: Preferences, now: Date
    ) -> Bool {
        let files = FileManager.default
        let support = library.appending(path: "Application Support", directoryHint: .isDirectory)
        let caches = library.appending(path: "Caches", directoryHint: .isDirectory)
        let legacyHome = support.appending(path: legacy, directoryHint: .isDirectory)
        let home = support.appending(path: current, directoryHint: .isDirectory)
        let backup = home.appending(path: "Migration Backup", directoryHint: .isDirectory)
        let repointed = backup.appending(path: "paths-repointed")
        let legacyCaches = caches.appending(path: legacy, directoryHint: .isDirectory)
        let legacyHelperCaches = caches.appending(path: legacy + ".dictation", directoryHint: .isDirectory)

        expireBackup(backup, now: now)
        // Preferences move last, so a run cut short leaves them behind and the next launch resumes.
        let pending =
            [legacyHome, legacyCaches, legacyHelperCaches].contains { files.fileExists(atPath: $0.path) }
            || preferences.read(legacy)?.isEmpty == false
        // 0.12.14-beta.141 moved everything but repointed only absolute paths outside data blobs.
        let movedWithoutRepointing =
            files.fileExists(atPath: backup.path) && !files.fileExists(atPath: repointed.path)
        guard pending || movedWithoutRepointing else { return false }

        merge(legacyHome, into: home)
        merge(legacyCaches, into: caches.appending(path: current))
        merge(legacyHelperCaches, into: caches.appending(path: current + ".dictation"))

        let rewrite = PathRewrite(legacy: legacy, current: current)
        let clipboard = home.appending(path: "clipboard.sqlite3")
        repointRows(in: clipboard, table: "items", columns: ["image_path"], rewrite: rewrite, backup: backup)
        repointRows(
            in: clipboard, table: "items", columns: ["text"], where: "kind = 'file'", rewrite: rewrite,
            backup: backup)
        repointRows(
            in: home.appending(path: "quicklinks.sqlite3"), table: "quicklinks",
            columns: ["link", "open_with", "icon"], rewrite: rewrite, backup: backup)
        let contents = files.enumerator(atPath: home.path)
        while let name = contents?.nextObject() as? String {
            if name == backup.lastPathComponent { contents?.skipDescendants() }
            guard name.hasSuffix(".json") else { continue }
            repoint(home.appending(path: name), keptAs: name, rewrite: rewrite, backup: backup)
        }
        if let settingsFile {
            repoint(
                settingsFile.resolvingSymlinksInPath(), keptAs: "settings.json", rewrite: rewrite,
                backup: backup)
        }

        let launchesAtLogin = movePreferences(
            from: legacy, to: current, preferences: preferences, backup: backup)
        repointPreferences(of: current, rewrite: rewrite, preferences: preferences, backup: backup)
        try? files.createDirectory(at: backup, withIntermediateDirectories: true)
        _ = files.createFile(atPath: repointed.path, contents: nil)
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

    /// The first copy only: a later run must never replace what the file held before the move.
    private static func keep(_ data: Data, as name: String, in backup: URL) throws {
        let copy = backup.appending(path: name)
        guard !FileManager.default.fileExists(atPath: copy.path) else { return }
        try FileManager.default.createDirectory(
            at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: copy)
    }

    /// Text replaced as text, so a JSON file keeps its formatting and a symlinked one its link.
    private static func repoint(_ file: URL, keptAs name: String, rewrite: PathRewrite, backup: URL) {
        guard let data = try? Data(contentsOf: file), let text = String(bytes: data, encoding: .utf8) else {
            return
        }
        let repointed = rewrite.rewriting(text)
        guard repointed != text else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        do {
            try keep(data, as: name, in: backup)
            try Data(repointed.utf8).write(to: file, options: .atomic)
            if let permissions = attributes?[.posixPermissions] {
                try FileManager.default.setAttributes(
                    [.posixPermissions: permissions], ofItemAtPath: file.path)
            }
        } catch {
            let reason = error.localizedDescription
            logger.error("Repointing \(name, privacy: .public) failed: \(reason, privacy: .public)")
        }
    }

    // MARK: - Preferences

    private static func movePreferences(
        from legacy: String, to current: String, preferences: Preferences, backup: URL
    ) -> Bool {
        guard var old = preferences.read(legacy), !old.isEmpty else { return false }
        do {
            try keep(plist(old), as: legacy + ".plist", in: backup)
        } catch {
            logger.error("Backing up the preferences failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let launchesAtLogin = old.removeValue(forKey: launchAtLoginKey) as? Bool ?? false
        let kept = preferences.read(current) ?? [:]
        preferences.write(old.merging(kept) { _, kept in kept }, current)
        preferences.remove(legacy)
        return launchesAtLogin
    }

    /// A snippet's hotkey, alias and favorite are keyed by its path; a custom command stores its folder.
    private static func repointPreferences(
        of current: String, rewrite: PathRewrite, preferences: Preferences, backup: URL
    ) {
        guard let stored = preferences.read(current),
            let repointed = rewrite.rewriting(value: stored) as? [String: Any],
            !NSDictionary(dictionary: stored).isEqual(to: repointed)
        else { return }
        do {
            try keep(plist(stored), as: current + ".plist", in: backup)
        } catch {
            logger.error("Backing up the preferences failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        preferences.write(repointed, current)
    }

    private static func plist(_ domain: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
    }

    // MARK: - Databases

    /// Rows naming the old id get `columns` rewritten, after one copy of the whole database.
    private static func repointRows(
        in database: URL, table: String, columns: [String], where condition: String = "1",
        rewrite: PathRewrite, backup: URL
    ) {
        guard FileManager.default.fileExists(atPath: database.path) else { return }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }

        let naming = columns.map { "\($0) LIKE ?1" }.joined(separator: " OR ")
        let select =
            "SELECT rowid, \(columns.joined(separator: ", ")) FROM \(table) WHERE (\(condition)) AND (\(naming))"
        guard let query = prepare(db, select, ["%\(rewrite.legacy)%"]) else { return }
        var changes: [(row: Int64, values: [String?])] = []
        while sqlite3_step(query) == SQLITE_ROW {
            let values = columns.indices.map { index in
                sqlite3_column_text(query, Int32(index + 1)).map { String(cString: $0) }
            }
            let repointed = values.map { $0.map(rewrite.rewriting) }
            if repointed != values { changes.append((sqlite3_column_int64(query, 0), repointed)) }
        }
        sqlite3_finalize(query)
        guard !changes.isEmpty, keepDatabase(db, as: database.lastPathComponent, in: backup) else { return }

        let assignments = columns.enumerated().map { "\($1) = ?\($0 + 1)" }.joined(separator: ", ")
        guard execute(db, "BEGIN IMMEDIATE"),
            let update = prepare(
                db, "UPDATE \(table) SET \(assignments) WHERE rowid = ?\(columns.count + 1)", [])
        else { return }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var succeeded = true
        for change in changes where succeeded {
            sqlite3_reset(update)
            for (index, value) in change.values.enumerated() {
                if let value {
                    sqlite3_bind_text(update, Int32(index + 1), value, -1, transient)
                } else {
                    sqlite3_bind_null(update, Int32(index + 1))
                }
            }
            sqlite3_bind_int64(update, Int32(columns.count + 1), change.row)
            succeeded = sqlite3_step(update) == SQLITE_DONE
        }
        sqlite3_finalize(update)
        guard execute(db, succeeded ? "COMMIT" : "ROLLBACK"), succeeded else {
            logger.error("Repointing \(table, privacy: .public) failed")
            return
        }
    }

    private static func keepDatabase(_ db: OpaquePointer?, as name: String, in backup: URL) -> Bool {
        let copy = backup.appending(path: name)
        if FileManager.default.fileExists(atPath: copy.path) { return true }
        try? FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        guard execute(db, "VACUUM INTO ?1", copy.path) else {
            logger.error("Backing up \(name, privacy: .public) failed; its rows are left as they are")
            return false
        }
        return true
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
