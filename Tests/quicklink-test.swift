// Standalone test for the quicklink model, destination detection, store and archive.
import Foundation

@main
@MainActor
struct QuicklinkTests {
    static var failures = 0
    static var passes = 0

    /// Injected everywhere a path is resolved, so no assertion depends on the machine.
    static let home = "/Users/tinycast-harness"

    static func main() {
        destinationDetection()
        pathDetection()
        encodingChoice()
        placeholderDetection()
        displayOrder()
        storeCRUD()
        storeValidation()
        pinning()
        persistence()
        readsADatabaseWrittenElsewhere()
        corruptDatabaseIsPreserved()
        archiveRoundTrip()
        archiveMerge()
        archiveAcceptsAHandWrittenFile()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Destination detection

    static func destinationDetection() {
        expect(detect("https://example.com") == .web(url("https://example.com")), "https is a website")
        expect(detect("http://example.com/a") == .web(url("http://example.com/a")), "http is a website")
        expect(
            detect("example.com/search?q=1") == .web(url("https://example.com/search?q=1")),
            "a bare host gains https, keeping its path and query")
        expect(
            detect("sub.example.co.uk") == .web(url("https://sub.example.co.uk")),
            "a multi-label host is still a website")
        expect(
            detect("example.com:8080/x") == .web(url("https://example.com:8080/x")),
            "a port does not stop a bare host being a website")
        expect(
            detect("spotify://track/1") == .deeplink(url("spotify://track/1")),
            "an unknown scheme is a deeplink")
        expect(
            detect("shortcuts://run-shortcut?name=Focus")
                == .deeplink(url("shortcuts://run-shortcut?name=Focus")),
            "a deeplink keeps its query")
        expect(
            detect("mailto:someone@example.com") == .deeplink(url("mailto:someone@example.com")),
            "a schemeless-authority scheme is still a deeplink")
        expect(
            detect("smb://server/share") == .network(url("smb://server/share")),
            "smb is a network path")
        expect(
            detect("afp://server/share") == .network(url("afp://server/share")),
            "afp is a network path")
        expect(
            detect("http://example.com/a b") == .web(url("http://example.com/a%20b")),
            "a literal space is rescued rather than rejected")
        expect(
            detect("https://example.com/a%20b") == .web(url("https://example.com/a%20b")),
            "an already-encoded value is not encoded twice")

        expect(detect("") == nil, "an empty link resolves to nothing")
        expect(detect("   ") == nil, "a whitespace-only link resolves to nothing")
        expect(detect("not a url") == nil, "prose is not a destination")
        expect(detect("{argument}") == nil, "a bare leftover placeholder is not a destination")
        expect(detect("1.5") == nil, "a decimal is not a host")
        expect(detect("C:/Users/x") == nil, "a drive letter is not a scheme")
    }

    static func pathDetection() {
        expect(detect("/tmp") == .path("/tmp"), "an absolute path is a path")
        expect(
            detect("~/Downloads") == .path("\(home)/Downloads"),
            "a tilde expands against the injected home")
        expect(detect("~") == .path(home), "a bare tilde is the home directory")
        expect(
            detect("  ~/Projects/Tinycast  ") == .path("\(home)/Projects/Tinycast"),
            "surrounding whitespace is trimmed before detection")
        expect(
            detect("file:///Users/x/notes.md") == .path("/Users/x/notes.md"),
            "a file URL resolves to the path it names, not to a deeplink")
        expect(
            QuicklinkDestination.detect("~/Downloads", homeDirectory: "/Users/other/")
                == .path("/Users/other/Downloads"),
            "a trailing slash on the home directory does not double up")
    }

    static func encodingChoice() {
        expect(
            QuicklinkDestination.usesURLEncoding("https://x.com/?q={argument}", homeDirectory: home),
            "values going into a URL are encoded")
        expect(
            QuicklinkDestination.usesURLEncoding("spotify://search/{argument}", homeDirectory: home),
            "values going into a deeplink are encoded")
        expect(
            !QuicklinkDestination.usesURLEncoding("~/Notes/{date}.md", homeDirectory: home),
            "values going into a path are not encoded")
        expect(
            !QuicklinkDestination.usesURLEncoding("/tmp/{argument}", homeDirectory: home),
            "an absolute path is not encoded either")
    }

    static func placeholderDetection() {
        expect(
            QuicklinkDestination.containsPlaceholder("https://x.com/?q={argument}"),
            "a token is a placeholder")
        expect(
            !QuicklinkDestination.containsPlaceholder("https://x.com/?q=1"),
            "a plain link has no placeholder")
        expect(
            !QuicklinkDestination.containsPlaceholder("https://x.com/{unterminated"),
            "an unclosed brace is not a placeholder")
    }

    // MARK: - Model

    static func displayOrder() {
        let base = Date(timeIntervalSince1970: 1_000)
        let zulu = link("Zulu")
        let alpha = link("alpha")
        var pinnedLate = link("Late Pin")
        pinnedLate.pinnedAt = base.addingTimeInterval(60)
        var pinnedEarly = link("Early Pin")
        pinnedEarly.pinnedAt = base

        let sorted = [zulu, alpha, pinnedLate, pinnedEarly].sorted(by: Quicklink.precedes)
        expect(
            sorted.map(\.name) == ["Early Pin", "Late Pin", "alpha", "Zulu"],
            "pins lead in pin order, then the rest sort case-insensitively by name")
    }

    // MARK: - Store

    static func storeCRUD() {
        withStore { store in
            guard let github = try? store.add(link("GitHub", "https://github.com")) else {
                return fail("adding a quicklink succeeds")
            }
            expect(store.quicklinks.map(\.name) == ["GitHub"], "an added quicklink is listed")
            expect(store.quicklink(entryID: github.entryID)?.id == github.id, "entry id round-trips")

            var edited = github
            edited.name = "GitHub Issues"
            edited.link = "https://github.com/issues"
            try? store.update(edited)
            expect(
                store.quicklink(id: github.id)?.name == "GitHub Issues",
                "an edit is stored under the same identity")
            expect(
                store.quicklink(id: github.id)?.link == "https://github.com/issues",
                "the edited link is stored")

            try? store.setShowsInRootSearch(false, id: github.id)
            expect(
                store.quicklink(id: github.id)?.showsInRootSearch == false,
                "hiding from root search is stored")

            expect(github.isEnabled, "a new quicklink is enabled")
            try? store.setEnabled(false, id: github.id)
            expect(store.quicklink(id: github.id)?.isEnabled == false, "disabling is stored")
            expect(
                store.quicklink(id: github.id)?.link == "https://github.com/issues",
                "disabling keeps every other field intact")

            guard let copy = try? store.duplicate(id: github.id) else {
                return fail("duplicating a quicklink succeeds")
            }
            expect(copy.id != github.id, "a duplicate is a new identity")
            expect(copy.name == "GitHub Issues Copy", "a duplicate gets a distinct name")
            expect(copy.link == "https://github.com/issues", "a duplicate keeps the destination")
            expect(!copy.isEnabled, "a duplicate inherits the enabled flag")

            try? store.remove(id: copy.id)
            expect(store.quicklinks.map(\.id) == [github.id], "removing drops only that row")
        }
    }

    static func storeValidation() {
        withStore { store in
            expect(throwsError(store, link("", "https://x.com")) == .emptyName, "a name is required")
            expect(throwsError(store, link("Name", "")) == .emptyLink, "a link is required")
            expect(
                throwsError(store, link("Name", "not a url")) == .unresolvableLink,
                "a link that resolves to nothing is rejected")
            expect(
                throwsError(store, link("Na\0me", "https://x.com")) == .invalidCharacter,
                "a null character is rejected")

            _ = try? store.add(link("Search", "https://x.com/?q={argument}"))
            expect(
                store.quicklinks.count == 1,
                "a templated link is accepted, since its destination is only knowable once expanded")
            expect(
                throwsError(store, link("search", "https://other.com")) == .duplicateName,
                "a duplicate name is rejected case-insensitively")

            var renamed = store.quicklinks[0]
            renamed.name = "  Search  "
            expect(
                (try? store.update(renamed)) != nil,
                "a quicklink does not collide with its own name when edited")
            expect(store.quicklinks[0].name == "Search", "names are trimmed on save")
        }
    }

    static func pinning() {
        withStore { store in
            _ = try? store.add(link("Alpha"))
            _ = try? store.add(link("Bravo"))
            _ = try? store.add(link("Charlie"))
            expect(names(store) == ["Alpha", "Bravo", "Charlie"], "unpinned rows sort by name")

            let charlie = store.quicklinks[2].id
            let alpha = store.quicklinks[0].id
            try? store.togglePinned(id: charlie)
            expect(names(store) == ["Charlie", "Alpha", "Bravo"], "a pin lifts the row to the top")

            try? store.togglePinned(id: alpha)
            expect(
                names(store) == ["Charlie", "Alpha", "Bravo"],
                "a second pin joins below the first rather than displacing it")

            var pinned = store.quicklink(id: charlie)!
            pinned.name = "Charlie Renamed"
            try? store.update(pinned)
            expect(
                names(store) == ["Charlie Renamed", "Alpha", "Bravo"],
                "editing a pinned row keeps its pin stamp and its place")

            try? store.togglePinned(id: charlie)
            expect(
                names(store) == ["Alpha", "Bravo", "Charlie Renamed"],
                "unpinning drops the row back into the alphabetical block")
        }
    }

    static func persistence() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        var stored: UUID?
        do {
            let store = QuicklinkStore(directory: dir)
            var draft = link("Downloads", "~/Downloads")
            draft.iconSymbol = "folder"
            draft.openWithBundleID = "com.apple.finder"
            stored = try? store.add(draft).id
            try? store.togglePinned(id: stored!)
            try? store.setEnabled(false, id: stored!)
        }

        let reopened = QuicklinkStore(directory: dir)
        reopened.load()
        expect(reopened.isAvailable, "a reopened database is available")
        guard let restored = reopened.quicklinks.first, reopened.quicklinks.count == 1 else {
            return fail("the quicklink survives a close and reopen")
        }
        expect(restored.id == stored, "identity survives")
        expect(restored.name == "Downloads" && restored.link == "~/Downloads", "fields survive")
        expect(restored.iconSymbol == "folder", "the icon survives")
        expect(restored.openWithBundleID == "com.apple.finder", "the open-with app survives")
        expect(restored.isPinned, "the pin stamp survives")
        expect(!restored.isEnabled, "the enabled flag survives")
    }

    /// The bound column order must match the read order, and an older table must gain `is_enabled`.
    static func readsADatabaseWrittenElsewhere() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        sqlite(
            dir.appendingPathComponent("quicklinks.sqlite3"),
            """
            CREATE TABLE quicklinks(
              id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, link TEXT NOT NULL,
              open_with TEXT, icon TEXT, in_root_search INTEGER NOT NULL DEFAULT 1,
              pinned_at REAL, created_at REAL NOT NULL
            );
            INSERT INTO quicklinks(id, name, link, open_with, icon, in_root_search, created_at)
              VALUES('\(id.uuidString)', 'Jira', 'https://jira.example.com', NULL, 'ticket', 0, 1000);
            """)

        let store = QuicklinkStore(directory: dir)
        store.load()
        guard let row = store.quicklinks.first else {
            return fail("an externally written row loads")
        }
        expect(row.id == id, "the external id is read")
        expect(row.name == "Jira" && row.link == "https://jira.example.com", "the text columns line up")
        expect(row.iconSymbol == "ticket", "the icon column lines up")
        expect(row.openWithBundleID == nil, "a null open-with reads as none")
        expect(!row.showsInRootSearch, "the root-search flag lines up")
        expect(!row.isPinned, "a null pin stamp reads as unpinned")
        expect(row.isEnabled, "a table written before is_enabled loads its rows as enabled")

        // A second open must find the column already there rather than adding it twice.
        let reopened = QuicklinkStore(directory: dir)
        reopened.load()
        expect(reopened.quicklinks.count == 1, "the migrated table reopens cleanly")
    }

    /// Quicklinks are authored data, so an unreadable database is reported, never recreated.
    static func corruptDatabaseIsPreserved() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("quicklinks.sqlite3")
        let garbage = Data("this is definitely not a database".utf8)
        try? garbage.write(to: dbURL)

        let store = QuicklinkStore(directory: dir)
        expect(!store.isAvailable, "an unreadable database reports itself unavailable")
        expect(store.quicklinks.isEmpty, "no rows are invented")
        expect(
            (try? Data(contentsOf: dbURL)) == garbage,
            "the unreadable file is left exactly as it was — never deleted or overwritten")
        expect(
            throwsError(store, link("Anything")) == .storageUnavailable,
            "a mutation refuses rather than pretending to save")
    }

    // MARK: - Archive

    static func archiveRoundTrip() {
        // Whole seconds: the archive is ISO 8601 so a reader can hand-edit it.
        let stamp = Date(timeIntervalSince1970: 500)
        let pinned = Quicklink(
            name: "Pinned", link: "~/Downloads", openWithBundleID: "com.apple.finder",
            iconSymbol: "folder", isEnabled: false, showsInRootSearch: false, pinnedAt: stamp,
            createdAt: stamp)
        let plain = Quicklink(name: "GitHub", link: "https://github.com", createdAt: stamp)
        let source = [plain, pinned]

        guard let data = try? QuicklinkArchive.encode(source),
            let decoded = try? QuicklinkArchive.decode(data)
        else { return fail("an exported archive decodes again") }
        expect(decoded == source, "every field survives an export and import round trip")
    }

    static func archiveMerge() {
        let existing = [link("GitHub", "https://github.com"), link("Downloads", "~/Downloads")]
        let incoming = [
            link("github", "https://elsewhere.com"),  // same name
            link("Repos", "https://github.com"),  // same destination
            link("Jira", "https://jira.example.com"),  // new
            link("Jira Two", "https://jira.example.com")  // duplicate of the one above, in-batch
        ]

        let result = QuicklinkArchive.merge(incoming, into: existing)
        expect(result.imported == 1, "only the genuinely new quicklink is imported")
        expect(result.skipped == 3, "the duplicates are counted rather than silently dropped")
        expect(result.additions.first?.name == "Jira", "the imported quicklink is the new one")
        expect(
            result.additions.first?.id != incoming[2].id,
            "an import takes a fresh identity so it cannot inherit another item's hotkey")

        let reimported = QuicklinkArchive.merge(existing, into: existing)
        expect(
            reimported.imported == 0 && reimported.skipped == 2,
            "importing the same file twice adds nothing")
    }

    static func archiveAcceptsAHandWrittenFile() {
        let handWritten = Data(
            """
            { "version": 1, "quicklinks": [ { "name": "Staging", "link": "https://staging.example.com" } ] }
            """.utf8)
        guard let decoded = try? QuicklinkArchive.decode(handWritten), let first = decoded.first
        else { return fail("a hand-written archive decodes") }
        expect(first.name == "Staging", "the name is read")
        expect(first.isEnabled, "an omitted enabled flag defaults to on")
        expect(first.showsInRootSearch, "an omitted root-search flag defaults to shown")
        expect(first.pinnedAt == nil, "an omitted pin stamp reads as unpinned")

        let bareArray = Data(#"[{ "name": "A", "link": "https://a.example.com" }]"#.utf8)
        expect((try? QuicklinkArchive.decode(bareArray))?.count == 1, "a bare array also decodes")
        expect(
            throwsArchiveError(Data("{}".utf8)) == .unreadable, "an unrelated JSON file is rejected")
        expect(
            throwsArchiveError(Data(#"{"version":1,"quicklinks":[]}"#.utf8)) == .empty,
            "an archive with no quicklinks is reported as empty rather than imported")
    }

    // MARK: - Helpers

    static func detect(_ value: String) -> QuicklinkDestination? {
        QuicklinkDestination.detect(value, homeDirectory: home)
    }

    static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            fail("harness could not build \(value)")
            exit(1)
        }
        return url
    }

    static func link(_ name: String, _ target: String = "https://example.com") -> Quicklink {
        Quicklink(name: name, link: target)
    }

    static func names(_ store: QuicklinkStore) -> [String] {
        store.quicklinks.map(\.name)
    }

    static func throwsError(_ store: QuicklinkStore, _ draft: Quicklink) -> QuicklinkError? {
        do {
            _ = try store.add(draft)
            return nil
        } catch {
            return error
        }
    }

    static func throwsArchiveError(_ data: Data) -> QuicklinkArchive.ArchiveError? {
        do {
            _ = try QuicklinkArchive.decode(data)
            return nil
        } catch {
            return error
        }
    }

    static func withStore(_ body: (QuicklinkStore) -> Void) {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        body(QuicklinkStore(directory: dir))
    }

    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-quicklink-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a database the store didn't create, which is the only way to prove it reads one.
    @discardableResult
    static func sqlite(_ database: URL, _ sql: String) -> Set<String> {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [database.path, sql]
        task.standardOutput = pipe
        guard (try? task.run()) != nil else {
            fail("could not run sqlite3")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 { fail("sqlite3 failed: \(sql.prefix(60))") }
        return Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
