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
                && fixture.imagePaths(in: fixture.home.appending(path: "clipboard.sqlite3")).contains(newImage)
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
            FileManager.default.fileExists(atPath: fixture.legacyHome.appending(path: "Notes/Groceries.md").path))
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
        check("a backup past a month is removed", !FileManager.default.fileExists(atPath: fixture.backup.path))
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
            from: legacy, to: current, library: root, preferences: domains.preferences, now: now)
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func makeClipboard(imagePaths: [String?]) throws {
        try FileManager.default.createDirectory(at: legacyHome, withIntermediateDirectories: true)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        sqlite3_open(legacyHome.appending(path: "clipboard.sqlite3").path, &db)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE items(id TEXT, image_path TEXT)", nil, nil, nil)
        for path in imagePaths {
            let value = path.map { "'\($0)'" } ?? "NULL"
            sqlite3_exec(db, "INSERT INTO items VALUES('\(UUID())', \(value))", nil, nil, nil)
        }
    }

    func imagePaths(in database: URL) -> [String?] {
        var db: OpaquePointer?
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
            sqlite3_close(db)
        }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            sqlite3_prepare_v2(db, "SELECT image_path FROM items", -1, &statement, nil) == SQLITE_OK
        else { return [] }
        var paths: [String?] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            paths.append(sqlite3_column_text(statement, 0).map { String(cString: $0) })
        }
        return paths
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
