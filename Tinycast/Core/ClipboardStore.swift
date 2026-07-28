import AppKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
    /// Pinned entries lead the list under their own section and are exempt from retention pruning.
    let isPinned: Bool

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
        sourceBundleID: String?, isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.isPinned = isPinned
    }

    /// Copy carrying one changed field — the store rewrites rows in place to re-recency (promote) or flip the pin.
    func with(createdAt: Date? = nil, isPinned: Bool? = nil) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath,
            createdAt: createdAt ?? self.createdAt, sourceBundleID: sourceBundleID,
            isPinned: isPinned ?? self.isPinned)
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
    /// Newest-first, pins included in place — `search` is the one place that lifts pinned rows to the head for display.
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

    private static let memoryWindow = 1000

    private static let schema = """
        CREATE TABLE IF NOT EXISTS items(
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          text TEXT,
          image_path TEXT,
          created_at REAL NOT NULL,
          source_app TEXT,
          pinned INTEGER NOT NULL DEFAULT 0
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
    private var db: OpaquePointer?
    private var insertStmt: OpaquePointer?
    private var loadStmt: OpaquePointer?
    private var searchStmt: OpaquePointer?
    private var deleteByIDStmt: OpaquePointer?
    private var setPinnedStmt: OpaquePointer?
    private var staleImagesStmt: OpaquePointer?
    private var deleteStaleStmt: OpaquePointer?

    init() {
        // Stored under ~/Library/Caches/<bundle-id> since clipboard history is regenerable; "Clear History" is the durable control.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
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

    // Isolated so teardown may touch the main-actor statement/db pointers; AppCore only ever releases the store on the main actor, so no hop.
    isolated deinit {
        closeDatabase()
    }

    func load() {
        guard let stmt = loadStmt else { return }
        // The window counts unpinned rows only; `loadStmt` adds every pinned row on top, however old.
        sqlite3_bind_int(stmt, 1, Int32(Self.memoryWindow - 1))
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

    func addText(_ text: String, sourceBundleID: String?) {
        if items.first?.kind == .text, items.first?.text == text { return }
        insert(ClipboardItem(text: text, sourceBundleID: sourceBundleID))
    }

    func addImage(_ data: Data, sourceBundleID: String?) {
        let url = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        let item = ClipboardItem(imagePath: url.path, sourceBundleID: sourceBundleID)
        // The blob write is multi-MB disk I/O; only the row insert (a failed write inserts nothing) returns to the main actor.
        Task.detached(priority: .utility) { [weak self] in
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            await self?.insert(item)
        }
    }

    /// Bulk-insert history from an external source (e.g. a Raycast import). Entries carry their original `createdAt` and image *paths* are stored as external references (zero-copy) — the store never owns or prunes files outside `imagesDir`. Dedups within the batch and against existing rows; imported items older than `maxAge` are pruned on reload.
    func importEntries(_ entries: [ClipboardItem]) -> Int {
        guard let stmt = insertStmt else { return 0 }
        var seenText = Set<String>()
        var seenPath = Set<String>()
        var inserted = 0
        // One transaction for the whole batch: ~1 WAL commit instead of one per row (dedup reads still see the in-progress inserts on this connection).
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
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
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        load()
        return inserted
    }

    /// Move an item to the top of history (pasting/copying it from the palette re-recencies it, Raycast-style). Stored order is rowid, so this is a delete + re-insert under the same id; the fresh `createdAt` keeps date buckets descending, the pin rides along, and the image blob is never touched.
    func promote(_ item: ClipboardItem) {
        guard items.first?.id != item.id else { return }
        let promoted = item.with(createdAt: Date())
        if let deleteStmt = deleteByIDStmt, let insertStmt {
            // One transaction: `id` is UNIQUE and a crash between the two statements must not lose the row.
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            sqlite3_bind_text(deleteStmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
            bindAndInsert(insertStmt, promoted)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
        // Array ops also cover items surfaced by FTS from beyond the in-memory window.
        items.removeAll { $0.id == item.id }
        items.insert(promoted, at: 0)
        trimWindow()
    }

    /// Flip an entry's pin. Pinned rows render in their own section above the history and survive retention pruning; a row pinned from an FTS hit older than the in-memory window is spliced into it so the section can show it.
    func togglePinned(_ item: ClipboardItem) {
        let updated = item.with(isPinned: !item.isPinned)
        if let stmt = setPinnedStmt {
            sqlite3_bind_int(stmt, 1, updated.isPinned ? 1 : 0)
            sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        } else if updated.isPinned {
            let index = items.firstIndex { $0.createdAt < updated.createdAt } ?? items.count
            items.insert(updated, at: index)
        }
    }

    func remove(_ item: ClipboardItem) {
        if let stmt = deleteByIDStmt {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        items.removeAll { $0.id == item.id }
        deleteBlob(item)
    }

    func clearAll() {
        if db != nil { sqlite3_exec(db, "DELETE FROM items", nil, nil, nil) }
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
        let result = Self.pinnedFirst(runSearch(q))
        searchCache = (q, result)
        return result
    }

    /// Row index of `item` among the results for `query` — lets the palette keep its selection on a row that moved (pin toggle, promote) whether or not the search is filtered. Reads the same memoized result the list renders.
    func rowIndex(of item: ClipboardItem, in query: String) -> Int? {
        search(query).firstIndex { $0.id == item.id }
    }

    private func runSearch(_ q: String) -> [ClipboardItem] {
        // Trigram FTS needs ≥3 characters; shorter queries (and the no-database path) fall back to filtering the in-memory window.
        guard let stmt = searchStmt, q.count >= 3 else { return fallbackSearch(q) }
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
        items.filter { ($0.text?.localizedCaseInsensitiveContains(q)) ?? false }
    }

    private var orderedItems: [ClipboardItem] {
        if let orderedCache { return orderedCache }
        let result = Self.pinnedFirst(items)
        orderedCache = result
        return result
    }

    /// Lift pinned rows to the head, preserving the newest-first order within each block.
    private static func pinnedFirst(_ list: [ClipboardItem]) -> [ClipboardItem] {
        let pinned = list.filter(\.isPinned)
        guard !pinned.isEmpty else { return list }
        return pinned + list.filter { !$0.isPinned }
    }

    /// Cap the in-memory window, but never drop a pinned row: those render however old they are.
    private func trimWindow() {
        guard items.count > Self.memoryWindow, let index = items.lastIndex(where: { !$0.isPinned })
        else { return }
        items.remove(at: index)
    }

    private func insert(_ item: ClipboardItem) {
        if let stmt = insertStmt { bindAndInsert(stmt, item) }
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
        sqlite3_bind_int(stmt, 7, item.isPinned ? 1 : 0)
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
        if let imagesStmt = staleImagesStmt, let deleteStmt = deleteStaleStmt {
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
        if items.last.map({ $0.createdAt < cutoff }) == true {
            items.removeAll { $0.createdAt < cutoff && !$0.isPinned }
        }
    }

    private func deleteBlob(_ item: ClipboardItem) {
        guard let path = item.imagePath, owns(path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        // Migrates pre-source_app databases; guarded so current ones don't log "duplicate column".
        if !columnExists("source_app", in: "items") {
            sqlite3_exec(db, "ALTER TABLE items ADD COLUMN source_app TEXT", nil, nil, nil)
        }
        if !columnExists("pinned", in: "items") {
            sqlite3_exec(
                db, "ALTER TABLE items ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        }
        insertStmt = prepare(
            """
            INSERT INTO items(id, kind, text, image_path, created_at, source_app, pinned)
            VALUES(?,?,?,?,?,?,?)
            """
        )
        // Every pinned row plus the newest `memoryWindow` unpinned ones (rowid of the oldest kept unpinned row is the floor; NULL when there are fewer than that, so everything loads).
        loadStmt = prepare(
            """
            SELECT id, kind, text, image_path, created_at, source_app, pinned FROM items
            WHERE pinned = 1 OR rowid >= COALESCE(
              (SELECT rowid FROM items WHERE pinned = 0 ORDER BY rowid DESC LIMIT 1 OFFSET ?), 0)
            ORDER BY rowid DESC
            """)
        searchStmt = prepare(
            """
            SELECT i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned
            FROM items_fts f JOIN items i ON i.rowid = f.rowid
            WHERE items_fts MATCH ? ORDER BY f.rowid DESC LIMIT 200
            """)
        deleteByIDStmt = prepare("DELETE FROM items WHERE id = ?")
        setPinnedStmt = prepare("UPDATE items SET pinned = ? WHERE id = ?")
        staleImagesStmt = prepare(
            """
            SELECT image_path FROM items
            WHERE created_at < ? AND pinned = 0 AND image_path IS NOT NULL
            """)
        deleteStaleStmt = prepare("DELETE FROM items WHERE created_at < ? AND pinned = 0")
        return insertStmt != nil && loadStmt != nil && searchStmt != nil
            && deleteByIDStmt != nil && setPinnedStmt != nil && staleImagesStmt != nil
            && deleteStaleStmt != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
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
        [
            insertStmt, loadStmt, searchStmt, deleteByIDStmt, setPinnedStmt, staleImagesStmt,
            deleteStaleStmt,
        ].forEach { sqlite3_finalize($0) }
        insertStmt = nil
        loadStmt = nil
        searchStmt = nil
        deleteByIDStmt = nil
        setPinnedStmt = nil
        staleImagesStmt = nil
        deleteStaleStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    private static func row(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let kindString = columnString(stmt, 1),
            let kind = ClipboardItem.Kind(rawValue: kindString)
        else { return nil }
        return ClipboardItem(
            id: id, kind: kind, text: columnString(stmt, 2), imagePath: columnString(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            sourceBundleID: columnString(stmt, 5), isPinned: sqlite3_column_int(stmt, 6) != 0)
    }

    private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}
