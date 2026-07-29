import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Owns SQLite state accessed only through the main-actor store, closing it after the store's final isolated access.
private final class SQLiteResources {
    var database: OpaquePointer?
    var insert: OpaquePointer?
    var load: OpaquePointer?
    var windowFloor: OpaquePointer?
    var search: OpaquePointer?
    var deleteByID: OpaquePointer?
    var pin: OpaquePointer?
    var staleImages: OpaquePointer?
    var deleteStale: OpaquePointer?

    deinit {
        close()
    }

    func close() {
        [insert, load, windowFloor, search, deleteByID, pin, staleImages, deleteStale]
            .forEach { sqlite3_finalize($0) }
        insert = nil
        load = nil
        windowFloor = nil
        search = nil
        deleteByID = nil
        pin = nil
        staleImages = nil
        deleteStale = nil
        sqlite3_close_v2(database)
        database = nil
    }
}

/// Identifies the Clear History generation in which an image was observed.
struct ClipboardImageCaptureToken: Sendable {
    fileprivate let generation: UInt64
}

struct ClipboardItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case text, image }

    let id: UUID
    let kind: Kind
    let text: String?
    /// Absolute path to the image on disk. Files under the store's own `imagesDir` are owned (pruned/deleted with the row); external references (e.g. imported from another app's cache) are left untouched on delete.
    let imagePath: String?
    let createdAt: Date
    /// Bundle ID of the app frontmost when the copy was captured (see `ClipboardManager.poll`).
    let sourceBundleID: String?
    /// When the entry was pinned. Pinned entries lead the list in their own section, in pin order, and are exempt from retention pruning.
    let pinnedAt: Date?

    var isPinned: Bool { pinnedAt != nil }

    init(text: String, sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: Date(),
            sourceBundleID: sourceBundleID)
    }

    init(imagePath: String, createdAt: Date = Date(), sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .image, text: nil, imagePath: imagePath, createdAt: createdAt,
            sourceBundleID: sourceBundleID)
    }

    init(
        id: UUID, kind: Kind, text: String?, imagePath: String?, createdAt: Date,
        sourceBundleID: String?, pinnedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.pinnedAt = pinnedAt
    }

    /// Copy with the two fields the store rewrites in place; the pin is stated outright because every rewrite either stamps it or drops the row back into the history.
    func with(createdAt: Date? = nil, pinnedAt: Date?) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath,
            createdAt: createdAt ?? self.createdAt, sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt)
    }

    /// Case-insensitive substring match — how the store filters without FTS: short queries, the no-database path, and the pinned block.
    func matches(_ query: String) -> Bool {
        text?.localizedCaseInsensitiveContains(query) ?? false
    }
}

/// How long clipboard history is kept before pruning; raw value is the age in days persisted to UserDefaults, and `forever` is -1 so an unset key (0) falls through to the default.
enum ClipboardRetention: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return "1 Day"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .year: return "1 Year"
        case .forever: return "Forever"
        }
    }

    var maxAge: TimeInterval {
        self == .forever ? .greatestFiniteMagnitude : TimeInterval(rawValue) * 86_400
    }
}

/// SQLite-backed clipboard history (rows + trigram FTS5 index in `clipboard.sqlite3`, image blobs on disk), degrading to session-only in-memory history if the database can't be opened.
@MainActor
final class ClipboardStore: ObservableObject {
    /// Newest-first, pins included in place — `search` is the one place that lifts them to the head. Every pinned row is resident however old it is (`load` fetches them all; neither `trimWindow` nor `prune` drops one), which is what lets `search` match the pinned block in memory.
    @Published private(set) var items: [ClipboardItem] = [] {
        didSet {
            searchCache = nil
            orderedCache = nil
        }
    }
    var maxAge: TimeInterval = ClipboardRetention.threeMonths.maxAge

    /// One-entry memo so repeated renders (e.g. arrow-key nav) for the same query reuse the FTS result instead of re-querying SQLite every frame; invalidated whenever `items` changes.
    private var searchCache: (query: String, result: [ClipboardItem])?
    /// Same memo for the empty query — every render reads the full display order, so the pinned/unpinned split runs once per mutation.
    private var orderedCache: [ClipboardItem]?
    /// Invalidates image work that was already off-main when Clear History ran.
    private var imageCaptureGeneration: UInt64 = 0

    private static let memoryWindow = 1000

    private static let schema = """
        CREATE TABLE IF NOT EXISTS items(
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          text TEXT,
          image_path TEXT,
          created_at REAL NOT NULL,
          source_app TEXT,
          pinned_at REAL
        );
        CREATE INDEX IF NOT EXISTS items_created_at ON items(created_at);
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
          text, content='items', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
          INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
        END;
        """

    private let imagesDir: URL
    private let dbURL: URL
    private let sqlite = SQLiteResources()

    /// `directory` defaults to the per-channel cache; `Tools/clipboard-test.swift` passes a throwaway one so a harness run can never reach a real history.
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        dbURL = base.appendingPathComponent("clipboard.sqlite3")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        if !openDatabase() {
            // The database is a regenerable cache: discard a corrupt or outdated one and start over.
            closeDatabase()
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: dbURL.path + suffix)
            }
            if !openDatabase() { closeDatabase() }
        }
    }

    /// Under ~/Library/Caches/<bundle-id> since clipboard history is regenerable; "Clear History" is the durable control.
    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    func load() {
        guard let stmt = sqlite.load else { return }
        sqlite3_bind_int64(stmt, 1, windowFloor())
        var loaded: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = Self.row(stmt) { loaded.append(item) }
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        items = loaded
        // Age passes while the app isn't running; insert-time pruning alone can't catch that.
        enforceLimits()
    }

    /// Called on load and when the retention setting changes.
    func enforceLimits() {
        prune()
    }

    /// Rowid of the oldest unpinned row the in-memory window keeps — the floor `loadStmt` reads from. 0 (no floor, load everything) when the history is shorter than the window.
    private func windowFloor() -> sqlite3_int64 {
        guard let stmt = sqlite.windowFloor else { return 0 }
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        sqlite3_bind_int(stmt, 1, Int32(Self.memoryWindow - 1))
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    func addText(_ text: String, sourceBundleID: String?) {
        if items.first?.kind == .text, items.first?.text == text { return }
        insert(ClipboardItem(text: text, sourceBundleID: sourceBundleID))
    }

    func beginImageCapture() -> ClipboardImageCaptureToken {
        ClipboardImageCaptureToken(generation: imageCaptureGeneration)
    }

    func addImage(
        _ data: Data, sourceBundleID: String?, capture: ClipboardImageCaptureToken
    ) async {
        guard capture.generation == imageCaptureGeneration else { return }
        let url = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        let item = ClipboardItem(imagePath: url.path, sourceBundleID: sourceBundleID)
        // The blob write is multi-MB disk I/O; only the row insert (a failed or invalidated write inserts nothing) returns to the main actor.
        let written = await Task.detached(priority: .utility) {
            (try? data.write(to: url, options: .atomic)) != nil
        }.value
        guard written else { return }
        guard capture.generation == imageCaptureGeneration else {
            _ = await Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: url)
            }.value
            return
        }
        insert(item)
    }

    /// Bulk-insert history from an external source (e.g. a Raycast import). Entries carry their original `createdAt` and image *paths* are stored as external references (zero-copy) — the store never owns or prunes files outside `imagesDir`. Dedups within the batch and against existing rows; imported items older than `maxAge` are pruned on reload.
    func importEntries(_ entries: [ClipboardItem]) -> Int {
        guard let stmt = sqlite.insert else { return 0 }
        var seenText = Set<String>()
        var seenPath = Set<String>()
        var inserted = 0
        // One transaction for the whole batch: ~1 WAL commit instead of one per row (dedup reads still see the in-progress inserts on this connection).
        sqlite3_exec(sqlite.database, "BEGIN", nil, nil, nil)
        // Oldest first so newest ends up with the highest rowid (load orders by rowid DESC).
        for item in entries.sorted(by: { $0.createdAt < $1.createdAt }) {
            switch item.kind {
            case .text:
                guard let text = item.text, !seenText.contains(text), !textExists(text) else {
                    continue
                }
                seenText.insert(text)
            case .image:
                guard let path = item.imagePath, !seenPath.contains(path), !imagePathExists(path)
                else { continue }
                seenPath.insert(path)
            }
            bindAndInsert(stmt, item)
            inserted += 1
        }
        sqlite3_exec(sqlite.database, "COMMIT", nil, nil, nil)
        load()
        return inserted
    }

    /// Move an item to the top of history (pasting/copying it from the palette re-recencies it, Raycast-style).
    func promote(_ item: ClipboardItem) {
        // A pinned row holds its place in the Pinned section, so re-recencying one would rewrite the row and its FTS entry for no visible change.
        guard !item.isPinned, items.first?.id != item.id else { return }
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    func togglePinned(_ item: ClipboardItem) {
        if item.isPinned { unpin(item) } else { pin(item) }
    }

    func remove(_ item: ClipboardItem) {
        if let stmt = sqlite.deleteByID {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        items.removeAll { $0.id == item.id }
        deleteBlob(item)
    }

    func clearAll() {
        imageCaptureGeneration &+= 1
        if sqlite.database != nil {
            sqlite3_exec(sqlite.database, "DELETE FROM items", nil, nil, nil)
        }
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        items = []
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let path = item.imagePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Display order for `query`: pinned entries first, each block newest-first.
    func search(_ query: String) -> [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return orderedItems }
        if let searchCache, searchCache.query == q { return searchCache.result }
        // Pins are matched in memory rather than taken from the FTS result: they are all resident (see `items`), and the statement's LIMIT would otherwise drop one out of a busy query's matches.
        let result = pinnedItems.filter { $0.matches(q) } + runSearch(q).filter { !$0.isPinned }
        searchCache = (q, result)
        return result
    }

    /// Row index of `item` among the results for `query` — lets the palette keep its selection on a row that moved (pin toggle, promote) whether or not the search is filtered. Reads the same memoized result the list renders.
    func rowIndex(of item: ClipboardItem, in query: String) -> Int? {
        search(query).firstIndex { $0.id == item.id }
    }

    private func runSearch(_ q: String) -> [ClipboardItem] {
        // Trigram FTS needs ≥3 characters; shorter queries (and the no-database path) fall back to filtering the in-memory window.
        guard let stmt = sqlite.search, q.count >= 3 else { return fallbackSearch(q) }
        let match = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        var results: [ClipboardItem] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let item = Self.row(stmt) { results.append(item) }
            status = sqlite3_step(stmt)
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        return status == SQLITE_DONE ? results : fallbackSearch(q)
    }

    // MARK: - Private

    private func fallbackSearch(_ q: String) -> [ClipboardItem] {
        items.filter { $0.matches(q) }
    }

    private var orderedItems: [ClipboardItem] {
        if let orderedCache { return orderedCache }
        let pinned = pinnedItems
        // An unpinned history renders `items` as-is, so it never pays for the split.
        let result = pinned.isEmpty ? items : pinned + items.filter { !$0.isPinned }
        orderedCache = result
        return result
    }

    /// The Pinned section's contents in pin order, oldest pin first: a new pin joins the end of the section instead of displacing the ones already there.
    private var pinnedItems: [ClipboardItem] {
        items.filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture) }
    }

    /// The row keeps its place in the history and gains a stamp, which puts it at the head of the Pinned section.
    private func pin(_ item: ClipboardItem) {
        let stamp = Date()
        let pinned = item.with(pinnedAt: stamp)
        if let stmt = sqlite.pin {
            sqlite3_bind_double(stmt, 1, stamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = pinned
        } else {
            // Pinned from an FTS hit older than the in-memory window: splice it in at its recency position, since the Pinned section can only show resident rows.
            let index = items.firstIndex { $0.createdAt < pinned.createdAt } ?? items.count
            items.insert(pinned, at: index)
        }
    }

    /// Unpinning rejoins the history as its newest entry rather than dropping the row back into the date bucket it came from, which would scroll the list out from under the selection. Raycast does the same.
    private func unpin(_ item: ClipboardItem) {
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    /// Rewrite a row under the same id so it leads the history: stored order is rowid, so this is a delete + re-insert, and the fresh `createdAt` keeps the date buckets descending. The image blob is never touched.
    private func reinsert(_ updated: ClipboardItem) {
        if let deleteStmt = sqlite.deleteByID, let insertStmt = sqlite.insert {
            // One transaction: `id` is UNIQUE and a crash between the two statements must not lose the row.
            sqlite3_exec(sqlite.database, "BEGIN", nil, nil, nil)
            sqlite3_bind_text(deleteStmt, 1, updated.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
            bindAndInsert(insertStmt, updated)
            sqlite3_exec(sqlite.database, "COMMIT", nil, nil, nil)
        }
        // Array ops also cover items surfaced by FTS from beyond the in-memory window.
        items.removeAll { $0.id == updated.id }
        items.insert(updated, at: 0)
        trimWindow()
    }

    /// Cap the in-memory window, but never drop a pinned row: those render however old they are.
    private func trimWindow() {
        guard items.count > Self.memoryWindow, let index = items.lastIndex(where: { !$0.isPinned })
        else { return }
        items.remove(at: index)
    }

    private func insert(_ item: ClipboardItem) {
        if let stmt = sqlite.insert { bindAndInsert(stmt, item) }
        items.insert(item, at: 0)
        trimWindow()
        prune()
    }

    private func bindAndInsert(_ stmt: OpaquePointer, _ item: ClipboardItem) {
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, item.kind.rawValue, -1, SQLITE_TRANSIENT)
        if let text = item.text {
            sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let path = item.imagePath {
            sqlite3_bind_text(stmt, 4, path, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
        if let source = item.sourceBundleID {
            sqlite3_bind_text(stmt, 6, source, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        if let pinnedAt = item.pinnedAt {
            sqlite3_bind_double(stmt, 7, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    private func textExists(_ text: String) -> Bool { exists(column: "text", value: text) }
    private func imagePathExists(_ path: String) -> Bool {
        exists(column: "image_path", value: path)
    }

    private func exists(column: String, value: String) -> Bool {
        guard let stmt = prepare("SELECT 1 FROM items WHERE \(column) = ? LIMIT 1") else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, value, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Whether a path lives inside our managed images directory — only those files are ours to delete.
    private func owns(_ path: String) -> Bool {
        path.hasPrefix(imagesDir.path + "/")
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        if let imagesStmt = sqlite.staleImages, let deleteStmt = sqlite.deleteStale {
            sqlite3_bind_double(imagesStmt, 1, cutoff.timeIntervalSince1970)
            var staleOwnedPaths: [String] = []
            while sqlite3_step(imagesStmt) == SQLITE_ROW {
                // Only delete files we own; external references (e.g. imported) just lose their row.
                if let path = Self.columnString(imagesStmt, 0), owns(path) {
                    staleOwnedPaths.append(path)
                }
            }
            sqlite3_reset(imagesStmt)
            sqlite3_clear_bindings(imagesStmt)
            sqlite3_bind_double(deleteStmt, 1, cutoff.timeIntervalSince1970)
            sqlite3_step(deleteStmt)
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
            // A retention cut can strand hundreds of files; delete them off the main actor so capture-time prune doesn't hitch.
            if !staleOwnedPaths.isEmpty {
                Task.detached(priority: .utility) {
                    for path in staleOwnedPaths {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }
            }
        }
        // Checked against the oldest *unpinned* row: an exempt pin sitting at the tail would otherwise make this guard permanently true and re-scan the window on every capture.
        if items.last(where: { !$0.isPinned }).map({ $0.createdAt < cutoff }) == true {
            items.removeAll { $0.createdAt < cutoff && !$0.isPinned }
        }
    }

    private func deleteBlob(_ item: ClipboardItem) {
        guard let path = item.imagePath, owns(path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(
                dbURL.path, &sqlite.database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
            )
                == SQLITE_OK,
            sqlite3_exec(
                sqlite.database, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil,
                nil
            ) == SQLITE_OK,
            sqlite3_exec(sqlite.database, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        // Migrates pre-source_app databases; guarded so current ones don't log "duplicate column".
        if !columnExists("source_app", in: "items") {
            sqlite3_exec(
                sqlite.database, "ALTER TABLE items ADD COLUMN source_app TEXT", nil, nil, nil)
        }
        if !columnExists("pinned_at", in: "items") {
            sqlite3_exec(
                sqlite.database, "ALTER TABLE items ADD COLUMN pinned_at REAL", nil, nil, nil)
        }
        // Created after the migration rather than in `schema`, since the column may not exist yet on an older database.
        sqlite3_exec(
            sqlite.database,
            "CREATE INDEX IF NOT EXISTS items_pinned_at ON items(pinned_at) WHERE pinned_at IS NOT NULL",
            nil, nil, nil)
        sqlite.insert = prepare(
            """
            INSERT INTO items(id, kind, text, image_path, created_at, source_app, pinned_at)
            VALUES(?,?,?,?,?,?,?)
            """
        )
        // Every pinned row plus the newest `memoryWindow` unpinned ones, keyed off the floor rowid `windowFloor` looks up. Two indexed branches rather than one `pinned_at IS NOT NULL OR rowid >= ?`: the planner can't drive an OR from an index while holding the row order, so that form reads the whole table.
        sqlite.load = prepare(
            """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at FROM (
              SELECT rowid AS rid, * FROM items WHERE rowid >= ?1
              UNION ALL
              SELECT rowid AS rid, * FROM items WHERE pinned_at IS NOT NULL AND rowid < ?1
            ) ORDER BY rid DESC
            """)
        sqlite.windowFloor = prepare(
            "SELECT rowid FROM items WHERE pinned_at IS NULL ORDER BY rowid DESC LIMIT 1 OFFSET ?")
        sqlite.search = prepare(
            """
            SELECT i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned_at
            FROM items_fts f JOIN items i ON i.rowid = f.rowid
            WHERE items_fts MATCH ? ORDER BY f.rowid DESC LIMIT 200
            """)
        sqlite.deleteByID = prepare("DELETE FROM items WHERE id = ?")
        // Only ever sets a stamp: unpinning rewrites the whole row so it leads the history again.
        sqlite.pin = prepare("UPDATE items SET pinned_at = ? WHERE id = ?")
        sqlite.staleImages = prepare(
            """
            SELECT image_path FROM items
            WHERE created_at < ? AND pinned_at IS NULL AND image_path IS NOT NULL
            """)
        sqlite.deleteStale = prepare(
            "DELETE FROM items WHERE created_at < ? AND pinned_at IS NULL")
        return sqlite.insert != nil && sqlite.load != nil && sqlite.windowFloor != nil
            && sqlite.search != nil && sqlite.deleteByID != nil && sqlite.pin != nil
            && sqlite.staleImages != nil && sqlite.deleteStale != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(sqlite.database, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        return stmt
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        guard let stmt = prepare("PRAGMA table_info(\(table))") else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column { return true }
        }
        return false
    }

    private func closeDatabase() {
        sqlite.close()
    }

    private static func row(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let kindString = columnString(stmt, 1),
            let kind = ClipboardItem.Kind(rawValue: kindString)
        else { return nil }
        return ClipboardItem(
            id: id, kind: kind, text: columnString(stmt, 2), imagePath: columnString(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            sourceBundleID: columnString(stmt, 5), pinnedAt: columnDate(stmt, 6))
    }

    private static func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}
