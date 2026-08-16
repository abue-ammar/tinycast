// Standalone test for the clipboard store, compiling the real source rather than a copy.
import Foundation

@main
@MainActor
struct ClipboardTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        pinOrder()
        unpinRejoinsAsNewest()
        pasteLeavesPinsAlone()
        pinsSurvivePruningAndTheWindow()
        pinsLeadFilteredSearches()
        textFormClassification()
        typeFilterSplitsTheHistory()
        typeFilterJoinsTheSearchMemo()
        persistence()
        migrationFromShippedDatabase()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cases

    /// Pins stack in pin order, oldest pin first, regardless of how old the entries are.
    static func pinOrder() {
        withStore { store, _ in
            store.addText("oldest", sourceBundleID: nil)
            store.addText("middle", sourceBundleID: nil)
            store.addText("newest", sourceBundleID: nil)

            store.togglePinned(item(store, "oldest"))
            expect(texts(store) == ["oldest", "newest", "middle"], "first pin leads the list")

            store.togglePinned(item(store, "middle"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "second pin joins below the first, and does not sort by recency")

            store.togglePinned(item(store, "newest"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "pins hold pin order, not the recency order they had in the history")
        }
    }

    /// Unpinning drops the row in as today's newest entry rather than back where it came from.
    static func unpinRejoinsAsNewest() {
        withStore { store, _ in
            store.addText("a", sourceBundleID: nil)
            store.addText("b", sourceBundleID: nil)
            store.addText("c", sourceBundleID: nil)
            let before = item(store, "a").createdAt

            store.togglePinned(item(store, "a"))
            store.togglePinned(item(store, "a"))

            expect(texts(store) == ["a", "c", "b"], "unpinned row leads the history")
            expect(!item(store, "a").isPinned, "pin stamp cleared")
            expect(item(store, "a").createdAt > before, "unpin re-recencies the row")
        }
    }

    /// Pasting a pinned entry must not reshuffle the Pinned section.
    static func pasteLeavesPinsAlone() {
        withStore { store, _ in
            store.addText("one", sourceBundleID: nil)
            store.addText("two", sourceBundleID: nil)
            store.togglePinned(item(store, "one"))
            store.togglePinned(item(store, "two"))
            let stamp = item(store, "one").createdAt

            store.promote(item(store, "one"))

            expect(texts(store) == ["one", "two"], "promote leaves a pinned row in place")
            expect(item(store, "one").createdAt == stamp, "promote does not rewrite a pinned row")

            store.addText("three", sourceBundleID: nil)
            store.addText("four", sourceBundleID: nil)
            store.promote(item(store, "three"))
            expect(
                texts(store) == ["one", "two", "three", "four"],
                "an unpinned row still promotes to the head of the history")
        }
    }

    /// Retention sweeps everything around a pin but never the pin itself.
    static func pinsSurvivePruningAndTheWindow() {
        withStore { store, dir in
            // Older than the 1-day retention the case sets below, but inside the default the import prunes against.
            let old = Date().addingTimeInterval(-2 * 86_400)
            _ = store.importEntries([
                entry("ancient-pinned", at: old),
                entry("ancient-loose", at: old.addingTimeInterval(1)),
                entry("fresh", at: Date())
            ])
            store.togglePinned(item(store, "ancient-pinned"))

            store.maxAge = 86_400
            store.enforceLimits()
            expect(
                Set(texts(store)) == ["ancient-pinned", "fresh"],
                "pruning skips pinned rows and takes the rest")

            // Reopen: the pin must come back even though it is far outside the retention window.
            let reopened = ClipboardStore(directory: dir)
            reopened.maxAge = 86_400
            reopened.load()
            expect(
                Set(texts(reopened)) == ["ancient-pinned", "fresh"],
                "a pin outlives retention across a relaunch")
        }
    }

    /// A pin must lead a filtered search even when the FTS statement's LIMIT cannot reach it.
    static func pinsLeadFilteredSearches() {
        withStore { store, _ in
            var seed: [ClipboardItem] = []
            let base = Date().addingTimeInterval(-10_000)
            // The pinned hit is the oldest of 260 matches; the FTS statement stops at 200.
            seed.append(entry("needle in the haystack", at: base))
            for i in 1...259 {
                seed.append(entry("haystack filler \(i)", at: base.addingTimeInterval(Double(i))))
            }
            _ = store.importEntries(seed)
            store.togglePinned(item(store, "needle in the haystack"))

            let results = store.search("haystack", filter: .all)
            expect(results.count > 200, "FTS results plus the pinned block")
            expect(
                results.first?.text == "needle in the haystack",
                "the pinned match leads the filtered results")
            expect(
                results.filter(\.isPinned).count == 1, "the pinned row is not duplicated")

            // Below the trigram threshold: the fallback path.
            let short = store.search("ne", filter: .all)
            expect(
                short.first?.text == "needle in the haystack",
                "the pinned match leads the fallback search too")
        }
    }

    /// The link/address classifier, including the filenames that must not read as links.
    static func textFormClassification() {
        let links = [
            "https://apple.com", "http://apple.com/path?q=1", "apple.com", "apple.com/store",
            "www.Apple.com", "vscode://file/tmp/x", "docs.google.com", "bit.ly/abc"
        ]
        for text in links {
            expect(form(text) == .link, "\(text) is a link")
        }

        let addresses = ["hi@apple.com", "mailto:hi@apple.com", "first.last@mail.example.co.uk"]
        for text in addresses {
            expect(form(text) == .email, "\(text) is an address")
        }

        let plain = [
            // Extensions that collide with a real TLD are the whole reason for the TLD set.
            "report.pdf", "index.html", "App.swift", "data.json", "Safari.app", "image.png",
            "hello world", "visit apple.com today", "3.14", "", "   ", "no-dot-at-all",
            "two@at@signs.com", "@apple.com", "hi@localhost", "line one\nline two"
        ]
        for text in plain {
            expect(form(text) == .plain, "\(String(text.prefix(20))) is plain text")
        }

        // Past the scan cap, so a multi-MB copy is never walked looking for a scheme.
        expect(
            form("https://apple.com/" + String(repeating: "a", count: 4096)) == .plain,
            "an over-long token is plain by definition")

        expect(
            ClipboardItem(imagePath: "/tmp/x.png", sourceBundleID: nil).textForm == nil,
            "an image has no text form")
    }

    /// Each filter returns only its own kind, and a pin still leads the block.
    static func typeFilterSplitsTheHistory() {
        withStore { store, _ in
            store.addText("just some prose", sourceBundleID: nil)
            store.addText("https://apple.com", sourceBundleID: nil)
            store.addText("hi@apple.com", sourceBundleID: nil)
            store.addText("second.link.dev", sourceBundleID: nil)

            expect(texts(store).count == 4, "every entry under All Types")
            expect(texts(store, filter: .text) == ["just some prose"], "text excludes links")
            expect(
                texts(store, filter: .link) == ["second.link.dev", "https://apple.com"],
                "links stay newest-first")
            expect(texts(store, filter: .email) == ["hi@apple.com"], "addresses on their own")
            expect(texts(store, filter: .image).isEmpty, "no images were captured")

            store.togglePinned(item(store, "https://apple.com"))
            expect(
                texts(store, filter: .link) == ["https://apple.com", "second.link.dev"],
                "a pinned link leads its filtered block")
        }
    }

    /// The memo keys on the filter too: same query, new filter, different rows.
    static func typeFilterJoinsTheSearchMemo() {
        withStore { store, _ in
            store.addText("shared token prose", sourceBundleID: nil)
            store.addText("shared-token.com", sourceBundleID: nil)

            expect(store.search("shared", filter: .all).count == 2, "both match the query")
            expect(
                store.search("shared", filter: .link).map(\.text) == ["shared-token.com"],
                "the same query under a link filter is not served from the wider memo")
            expect(
                store.search("shared", filter: .text).map(\.text) == ["shared token prose"],
                "and switching filters again re-runs rather than reusing")
            expect(store.search("shared", filter: .all).count == 2, "back to both")
        }
    }

    /// Pin stamps and their order survive a reopen.
    static func persistence() {
        withStore { store, dir in
            store.addText("first", sourceBundleID: nil)
            store.addText("second", sourceBundleID: nil)
            store.addText("third", sourceBundleID: nil)
            store.togglePinned(item(store, "third"))
            store.togglePinned(item(store, "first"))

            let reopened = ClipboardStore(directory: dir)
            reopened.load()
            expect(
                texts(reopened) == ["third", "first", "second"],
                "pin order is restored from disk, not recomputed from recency")

            reopened.togglePinned(item(reopened, "third"))
            expect(texts(reopened) == ["first", "third", "second"], "unpin after a reload")

            reopened.clearAll()
            expect(reopened.items.isEmpty, "Clear History takes pins too")
        }
    }

    /// A shipped pre-pin database migrates in place. Failing to open one is not a soft failure: the store deletes and recreates a database it can't open, taking the history with it.
    static func migrationFromShippedDatabase() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("clipboard.sqlite3")
        seedPrePinDatabase(at: db)

        let store = ClipboardStore(directory: dir)
        store.load()
        expect(texts(store) == ["newer", "older"], "existing history survives the migration")

        store.addText("after", sourceBundleID: nil)
        store.togglePinned(item(store, "older"))
        expect(texts(store) == ["older", "after", "newer"], "the migrated database takes pins")

        let reopened = ClipboardStore(directory: dir)
        reopened.load()
        expect(texts(reopened) == ["older", "after", "newer"], "and keeps them across a reopen")

        expect(
            sqlite(db, "SELECT name FROM pragma_table_info('items')").contains("pinned_at"),
            "the pin stamp column was added")
        expect(
            sqlite(db, "SELECT name FROM sqlite_master WHERE type = 'index'")
                .contains("items_pinned_at"),
            "and indexed")
    }

    // MARK: - Harness

    /// Runs `body` against a store rooted in a fresh temp directory, torn down afterwards.
    static func withStore(_ body: (ClipboardStore, URL) -> Void) {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        body(ClipboardStore(directory: dir), dir)
    }

    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "tinycast-clipboard-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes the schema as shipped before pinning existed: no `pinned_at`, and two rows to migrate.
    static func seedPrePinDatabase(at url: URL) {
        let now = Date().timeIntervalSince1970
        sqlite(
            url,
            """
            CREATE TABLE items(
              id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, text TEXT, image_path TEXT,
              created_at REAL NOT NULL, source_app TEXT
            );
            CREATE INDEX items_created_at ON items(created_at);
            CREATE VIRTUAL TABLE items_fts USING fts5(
              text, content='items', content_rowid='rowid', tokenize='trigram'
            );
            CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
              INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
            END;
            CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
              INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
            END;
            INSERT INTO items(id, kind, text, created_at)
              VALUES('\(UUID().uuidString)', 'text', 'older', \(now - 60));
            INSERT INTO items(id, kind, text, created_at)
              VALUES('\(UUID().uuidString)', 'text', 'newer', \(now));
            """)
    }

    /// Rows returned by the `sqlite3` CLI — used to write a legacy database and to read the schema back, neither of which the store exposes.
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

    static func form(_ text: String) -> ClipboardItem.TextForm? {
        ClipboardItem(text: text, sourceBundleID: nil).textForm
    }

    static func entry(_ text: String, at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: date,
            sourceBundleID: nil)
    }

    static func texts(_ store: ClipboardStore, filter: ClipboardFilter = .all) -> [String] {
        store.search("", filter: filter).compactMap(\.text)
    }

    static func item(_ store: ClipboardStore, _ text: String) -> ClipboardItem {
        guard let match = store.items.first(where: { $0.text == text }) else {
            fail("no entry named \(text)")
            exit(1)
        }
        return match
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
