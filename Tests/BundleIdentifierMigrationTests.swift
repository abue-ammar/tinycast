import Foundation
import SQLite3

@main
@MainActor
struct BundleIdentifierMigrationTests {
    static var failures = 0
    static var passes = 0

    static func check(_ name: String, _ condition: Bool) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }

    static func main() throws {
        mapsIdentifiers()
        try movesEverythingOnce()
        try keepsWhatTheNewHomeAlreadyHas()
        try expiresTheBackup()
        try handsOnTheLoginItemOnlyWhenItWasOn()
        try followsSnippetsToTheirNewPath()
        try repointsEverySpellingOfTheOldFolders()
        try repairsAnEarlierMove()
        leavesAFreshInstallAlone()

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func mapsIdentifiers() {
        let mapping = [
            ("com.abueammar.tinycast", "com.tinycast.app"),
            ("com.abueammar.tinycast.beta", "com.tinycast.app.beta"),
            ("com.abueammar.tinycast.dev", "com.tinycast.app.dev")
        ]
        for (current, legacy) in mapping {
            check(
                "\(current) moves from \(legacy)",
                BundleIdentifierMigration.legacyIdentifier(of: current) == legacy)
        }
        check(
            "a fork has nothing to move from",
            BundleIdentifierMigration.legacyIdentifier(of: "org.example.cast") == nil)
        check(
            "a lookalike prefix is not a channel",
            BundleIdentifierMigration.legacyIdentifier(of: "com.abueammar.tinycaster") == nil)
    }

    static func movesEverythingOnce() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let files = FileManager.default
        let legacyImage = fixture.legacyHome.appending(path: "images/a.png").path
        try fixture.write("png", to: fixture.legacyHome.appending(path: "images/a.png"))
        try fixture.write("# Note", to: fixture.legacyHome.appending(path: "Notes/Groceries.md"))
        try fixture.write("{}", to: fixture.caches.appending(path: fixture.legacy + "/rates.json"))
        try fixture.write("model", to: fixture.caches.appending(path: fixture.legacy + ".dictation/m"))
        try fixture.makeClipboard(imagePaths: [legacyImage, "/Users/someone/Desktop/shot.png", nil])
        fixture.domains.values[fixture.legacy] = [
            "clipboardEnabled": false, "shared": "old", BundleIdentifierMigration.launchAtLoginKey: true
        ]
        fixture.domains.values[fixture.current] = ["shared": "new"]

        check("the old id's login item is handed on", fixture.migrate())

        check("the old home is gone", !files.fileExists(atPath: fixture.legacyHome.path))
        check(
            "the new home holds the old files",
            files.fileExists(atPath: fixture.home.appending(path: "images/a.png").path)
                && files.fileExists(atPath: fixture.home.appending(path: "Notes/Groceries.md").path))
        check(
            "the caches move",
            files.fileExists(atPath: fixture.caches.appending(path: fixture.current + "/rates.json").path)
                && !files.fileExists(atPath: fixture.caches.appending(path: fixture.legacy).path))
        check(
            "the dictation helper's caches move",
            files.fileExists(
                atPath: fixture.caches.appending(path: fixture.current + ".dictation/m").path))

        let newImage = fixture.home.appending(path: "images/a.png").path
        let paths = fixture.imagePaths(in: fixture.home.appending(path: "clipboard.sqlite3"))
        check("an image row names the moved file", paths.contains(newImage))
        check("an image row outside the home is untouched", paths.contains("/Users/someone/Desktop/shot.png"))
        check("a row with no image stays without one", paths.contains(nil))
        check(
            "the backup keeps the clipboard as it was",
            fixture.imagePaths(in: fixture.backup.appending(path: "clipboard.sqlite3")).contains(legacyImage))

        let preferences = fixture.domains.values[fixture.current] ?? [:]
        check("a preference moves", preferences["clipboardEnabled"] as? Bool == false)
        check("a preference the new id already has wins", preferences["shared"] as? String == "new")
        check(
            "the handoff's flag stays out of the new preferences",
            preferences[BundleIdentifierMigration.launchAtLoginKey] == nil)
        check("the old domain is removed", fixture.domains.values[fixture.legacy] == nil)
        let backedUp = NSDictionary(contentsOf: fixture.backup.appending(path: fixture.legacy + ".plist"))
        check("the backup keeps the old preferences", backedUp?["shared"] as? String == "old")

        let before = try files.contentsOfDirectory(atPath: fixture.backup.path).sorted()
        let registersAgain = fixture.migrate()
        let after = try files.contentsOfDirectory(atPath: fixture.backup.path).sorted()
        check(
            "a second run changes nothing",
            !registersAgain
                && fixture.imagePaths(in: fixture.home.appending(path: "clipboard.sqlite3")).contains(
                    newImage)
                && after == before
                && (fixture.domains.values[fixture.current]?["shared"] as? String) == "new")
    }

    static func keepsWhatTheNewHomeAlreadyHas() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("old", to: fixture.legacyHome.appending(path: "Notes/Groceries.md"))
        try fixture.write("old", to: fixture.legacyHome.appending(path: "Notes/Ideas.md"))
        try fixture.write("old", to: fixture.legacyHome.appending(path: "onboarded"))
        try fixture.write("new", to: fixture.home.appending(path: "Notes/Groceries.md"))

        fixture.migrate()

        check(
            "a file the new home has is never overwritten",
            (try? String(contentsOf: fixture.home.appending(path: "Notes/Groceries.md"), encoding: .utf8))
                == "new")
        check(
            "what the new home lacks moves in, into folders it already has",
            FileManager.default.fileExists(atPath: fixture.home.appending(path: "Notes/Ideas.md").path)
                && FileManager.default.fileExists(atPath: fixture.home.appending(path: "onboarded").path))
        check(
            "the old copy of a conflicting file stays where it was",
            FileManager.default.fileExists(
                atPath: fixture.legacyHome.appending(path: "Notes/Groceries.md").path))
    }

    static func expiresTheBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.domains.values[fixture.legacy] = ["shared": "old"]
        fixture.migrate()
        check("a fresh backup is kept", FileManager.default.fileExists(atPath: fixture.backup.path))

        fixture.migrate(now: Date().addingTimeInterval(29 * 24 * 60 * 60))
        check("a backup within a month is kept", FileManager.default.fileExists(atPath: fixture.backup.path))
        fixture.migrate(now: Date().addingTimeInterval(31 * 24 * 60 * 60))
        check(
            "a backup past a month is removed", !FileManager.default.fileExists(atPath: fixture.backup.path))
    }

    static func handsOnTheLoginItemOnlyWhenItWasOn() throws {
        let off = try Fixture()
        defer { off.remove() }
        off.domains.values[off.legacy] = ["shared": "old", BundleIdentifierMigration.launchAtLoginKey: false]
        check("an old id that did not open at login registers nothing", !off.migrate())

        let unknown = try Fixture()
        defer { unknown.remove() }
        unknown.domains.values[unknown.legacy] = ["shared": "old"]
        check("preferences without the handoff's flag register nothing", !unknown.migrate())
    }
}

extension BundleIdentifierMigrationTests {
    /// A snippet's launcher id is its path, so every record keyed by it must follow the move.
    static func followsSnippetsToTheirNewPath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let oldSnippet = fixture.legacyHome.appending(path: "Snippets/Sign-off.md").path
        let newSnippet = fixture.home.appending(path: "Snippets/Sign-off.md").path
        try fixture.write("Thanks", to: URL(filePath: oldSnippet))
        fixture.domains.values[fixture.legacy] = [
            "hotkey.snippet." + oldSnippet: "{\"keyCode\":1}",
            "boundSnippetIDs": [oldSnippet],
            "aliases": ["snippet:" + oldSnippet: "so"],
            "favorites": ["snippet:" + oldSnippet, "app:com.apple.Safari"]
        ]
        struct Visit: Codable { let count: Int }
        let ranking = try JSONEncoder().encode(["snippet:" + oldSnippet: Visit(count: 3)])
        try ranking.write(to: fixture.legacyHome.appending(path: "launcher-ranking.json"))

        fixture.migrate()

        let preferences = fixture.domains.values[fixture.current] ?? [:]
        check(
            "a snippet's hotkey keeps its binding",
            preferences["hotkey.snippet." + newSnippet] as? String == "{\"keyCode\":1}")
        check("no preference names the old folder", !"\(preferences)".contains(fixture.legacyHome.path))
        check("the bound snippet list follows", preferences["boundSnippetIDs"] as? [String] == [newSnippet])
        check(
            "a snippet's alias follows",
            (preferences["aliases"] as? [String: String])?["snippet:" + newSnippet] == "so")
        check(
            "a favorite follows and the others stay",
            preferences["favorites"] as? [String] == ["snippet:" + newSnippet, "app:com.apple.Safari"])

        let moved = try Data(contentsOf: fixture.home.appending(path: "launcher-ranking.json"))
        let visits = try JSONDecoder().decode([String: Visit].self, from: moved)
        check("the launch ranking follows", visits["snippet:" + newSnippet]?.count == 3 && visits.count == 1)
        check(
            "the backup keeps the ranking as it was",
            (try? Data(contentsOf: fixture.backup.appending(path: "launcher-ranking.json"))) == ranking)
    }
}

extension BundleIdentifierMigrationTests {
    struct Command: Codable, Equatable {
        let command: String
        let workingDirectory: String?
    }

    /// A path a user typed or picked can be absolute, `~/`, a `file://` URL, or JSON inside a setting.
    static func repointsEverySpellingOfTheOldFolders() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let tilde = (
            old: "~/Library/Application Support/\(fixture.legacy)/tinycastscripts",
            new: "~/Library/Application Support/\(fixture.current)/tinycastscripts"
        )
        let script = (
            old: fixture.legacyHome.appending(path: "tinycastscripts/run.sh").path,
            new: fixture.home.appending(path: "tinycastscripts/run.sh").path
        )
        let link = (
            old: "file://" + fixture.encoded(fixture.legacyHome) + "/Read%20Me.pdf",
            new: "file://" + fixture.encoded(fixture.home) + "/Read%20Me.pdf"
        )
        try fixture.write("#!/bin/sh", to: URL(filePath: script.old))
        let shell = (
            old:
                #"cd ~/Library/Application\ Support/\#(fixture.legacy) && "$HOME/Library/Caches/\#(fixture.legacy)/x""#,
            new:
                #"cd ~/Library/Application\ Support/\#(fixture.current) && "$HOME/Library/Caches/\#(fixture.current)/x""#
        )
        let commands = try JSONEncoder().encode([
            Command(command: "sh '\(script.old)'", workingDirectory: tilde.old),
            Command(command: shell.old, workingDirectory: nil)
        ])
        let archived = try PropertyListSerialization.data(
            fromPropertyList: ["path": script.old], format: .binary, options: 0)
        let lookalike = "~/Library/Application Support/\(fixture.legacy)x/keep"
        fixture.domains.values[fixture.legacy] = [
            "customCommands": commands,
            "fileSearchScopes": [tilde.old, "~/Documents"],
            "archived": archived,
            "lookalike": lookalike,
            "plist": "~/Library/Preferences/\(fixture.legacy).plist",
            "models": "~/Library/Caches/\(fixture.legacy).dictation/models"
        ]
        let escaped = tilde.old.replacingOccurrences(of: "/", with: "\\/")
        try fixture.write(
            #"{"preferences":{"folder":"\#(escaped)"}}"#,
            to: fixture.legacyHome.appending(path: "extension-data/files.json"))
        let support = "extensions/files/support/cache.json"
        try fixture.write(#"{"root":"\#(script.old)"}"#, to: fixture.legacyHome.appending(path: support))
        try fixture.sqlite(
            fixture.legacyHome.appending(path: "quicklinks.sqlite3"),
            """
            CREATE TABLE quicklinks(id TEXT, link TEXT, open_with TEXT, icon TEXT);
            INSERT INTO quicklinks VALUES('a', '\(link.old)', NULL, NULL);
            """)
        try fixture.sqlite(
            fixture.legacyHome.appending(path: "clipboard.sqlite3"),
            """
            CREATE TABLE items(id TEXT, kind TEXT, text TEXT, image_path TEXT);
            INSERT INTO items VALUES('f', 'file', '\(script.old)', NULL);
            INSERT INTO items VALUES('t', 'text', '\(script.old)', NULL);
            """)
        try fixture.write(#"{"snippets":{"folder":"\#(tilde.old)"}}"#, to: fixture.settingsFile)

        fixture.migrate()

        let preferences = fixture.domains.values[fixture.current] ?? [:]
        let moved = (preferences["customCommands"] as? Data).flatMap {
            try? JSONDecoder().decode([Command].self, from: $0)
        }
        check(
            "a custom command's folder and command follow, though stored as JSON data",
            moved?.first == Command(command: "sh '\(script.new)'", workingDirectory: tilde.new))
        check("a shell-escaped or $HOME path in a command follows", moved?.last?.command == shell.new)
        check(
            "a ~/ path in a setting follows",
            preferences["fileSearchScopes"] as? [String] == [tilde.new, "~/Documents"])
        check("a binary property list is left alone", preferences["archived"] as? Data == archived)
        check(
            "a longer id that only starts like the old one is left alone",
            preferences["lookalike"] as? String == lookalike)
        check(
            "the old preferences file is a different file, and is left alone",
            preferences["plist"] as? String == "~/Library/Preferences/\(fixture.legacy).plist")
        check(
            "a path into the Dictation helper's caches follows",
            preferences["models"] as? String == "~/Library/Caches/\(fixture.current).dictation/models")

        let storage = try Data(contentsOf: fixture.home.appending(path: "extension-data/files.json"))
        let folder = (try JSONSerialization.jsonObject(with: storage) as? [String: [String: String]])?[
            "preferences"]?["folder"]
        check("an extension's stored preference follows", folder == tilde.new)
        let cache = try String(contentsOf: fixture.home.appending(path: support), encoding: .utf8)
        check("a JSON file an extension wrote in its own folder follows", cache.contains(script.new))
        check(
            "the extension's file is backed up",
            FileManager.default.fileExists(
                atPath: fixture.backup.appending(path: "extension-data/files.json").path))
        let quicklinks = fixture.home.appending(path: "quicklinks.sqlite3")
        check(
            "a quicklink's file:// link follows",
            fixture.column(in: quicklinks, "SELECT link FROM quicklinks") == [link.new])
        check(
            "a quicklink's empty columns stay empty",
            fixture.column(in: quicklinks, "SELECT open_with FROM quicklinks") == [nil])
        let clipboard = fixture.home.appending(path: "clipboard.sqlite3")
        check(
            "a copied file in the old folder follows",
            fixture.column(in: clipboard, "SELECT text FROM items WHERE kind = 'file'") == [script.new])
        check(
            "copied text that mentions the path is content, and stays",
            fixture.column(in: clipboard, "SELECT text FROM items WHERE kind = 'text'") == [script.old])
        let settings = try String(contentsOf: fixture.settingsFile, encoding: .utf8)
        check("settings.json follows, or it would undo the move at launch", settings.contains(tilde.new))
        check(
            "settings.json is backed up",
            (try? String(contentsOf: fixture.backup.appending(path: "settings.json"), encoding: .utf8))?
                .contains(tilde.old) == true)
    }

    /// What 0.12.14-beta.141 left: everything moved, the backup made, and a `~/` folder still old.
    static func repairsAnEarlierMove() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let old = "~/Library/Application Support/\(fixture.legacy)/tinycastscripts"
        let new = "~/Library/Application Support/\(fixture.current)/tinycastscripts"
        let commands = try JSONEncoder().encode([Command(command: "ls", workingDirectory: old)])
        fixture.domains.values[fixture.current] = ["customCommands": commands, "kept": "yes"]

        check("a repair never registers a login item", !fixture.migrate())

        let preferences = fixture.domains.values[fixture.current] ?? [:]
        let repaired = (preferences["customCommands"] as? Data).flatMap {
            try? JSONDecoder().decode([Command].self, from: $0)
        }
        check(
            "the earlier move's custom command folder is repaired", repaired?.first?.workingDirectory == new)
        check("the rest of the preferences stay", preferences["kept"] as? String == "yes")
        check(
            "the preferences are backed up before the repair",
            FileManager.default.fileExists(
                atPath: fixture.backup.appending(path: fixture.current + ".plist").path))

        fixture.domains.values[fixture.current]?["late"] = old
        fixture.migrate()
        check("the repair runs once", fixture.domains.values[fixture.current]?["late"] as? String == old)
    }

    static func leavesAFreshInstallAlone() {
        guard let fixture = try? Fixture() else { return check("a fixture opens", false) }
        defer { fixture.remove() }
        let path = "~/Library/Application Support/\(fixture.legacy)/x"
        fixture.domains.values[fixture.current] = ["path": path]
        check("a copy that never had the old id has nothing to do", !fixture.migrate())
        check("nothing is created for it", !FileManager.default.fileExists(atPath: fixture.home.path))
        check(
            "nothing in it is rewritten", fixture.domains.values[fixture.current]?["path"] as? String == path)
    }
}

/// The preference domains, in memory.
final class Domains {
    var values: [String: [String: Any]] = [:]

    var preferences: BundleIdentifierMigration.Preferences {
        BundleIdentifierMigration.Preferences(
            read: { self.values[$0] }, write: { self.values[$1] = $0 }, remove: { self.values[$0] = nil })
    }
}

/// A scratch Library, removed afterwards.
struct Fixture {
    let root: URL
    let support: URL
    let caches: URL
    let current = "com.abueammar.tinycast.beta"
    let legacy = "com.tinycast.app.beta"
    let domains = Domains()

    var home: URL { support.appending(path: current, directoryHint: .isDirectory) }
    var legacyHome: URL { support.appending(path: legacy, directoryHint: .isDirectory) }
    var backup: URL { home.appending(path: "Migration Backup", directoryHint: .isDirectory) }
    var settingsFile: URL { root.appending(path: "config/settings.json") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "tinycast-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        support = root.appending(path: "Application Support", directoryHint: .isDirectory)
        caches = root.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    }

    @discardableResult
    func migrate(now: Date = Date()) -> Bool {
        BundleIdentifierMigration.migrate(
            from: legacy, to: current, library: root, settingsFile: settingsFile,
            preferences: domains.preferences, now: now)
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func makeClipboard(imagePaths: [String?]) throws {
        let rows = imagePaths.map { path in
            "INSERT INTO items VALUES('\(UUID())', 'image', NULL, \(path.map { "'\($0)'" } ?? "NULL"));"
        }
        try sqlite(
            legacyHome.appending(path: "clipboard.sqlite3"),
            "PRAGMA journal_mode=WAL; CREATE TABLE items(id TEXT, kind TEXT, text TEXT, image_path TEXT);"
                + rows.joined())
    }

    func sqlite(_ database: URL, _ sql: String) throws {
        try FileManager.default.createDirectory(
            at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        sqlite3_open(database.path, &db)
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func imagePaths(in database: URL) -> [String?] {
        column(in: database, "SELECT image_path FROM items")
    }

    func column(in database: URL, _ select: String) -> [String?] {
        var db: OpaquePointer?
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
            sqlite3_close(db)
        }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            sqlite3_prepare_v2(db, select, -1, &statement, nil) == SQLITE_OK
        else { return [] }
        var values: [String?] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(sqlite3_column_text(statement, 0).map { String(cString: $0) })
        }
        return values
    }

    func encoded(_ folder: URL) -> String {
        folder.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folder.path
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
