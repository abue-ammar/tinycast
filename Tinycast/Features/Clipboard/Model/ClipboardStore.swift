import Foundation
import SQLite3

// Spelled as the C macro in sqlite3.h, which isn't imported into Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ClipboardItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case text, image, file }

    let id: UUID
    let kind: Kind
    /// The copied text, or for a `.file` entry the absolute path — which is what FTS indexes.
    let text: String?
    /// Absolute path on disk; only files under `imagesDir` are ours to delete.
    let imagePath: String?
    let createdAt: Date
    /// Bundle ID of the app frontmost when the copy was captured (see `ClipboardManager.poll`).
    let sourceBundleID: String?
    /// When the entry was pinned; pins lead the list and are exempt from pruning.
    let pinnedAt: Date?

    var isPinned: Bool { pinnedAt != nil }

    /// The referenced path, so no call site re-derives a file entry's meaning from `text`.
    var filePath: String? { kind == .file ? text : nil }

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

    /// Referenced where it lies: `imagePath` stays nil, keeping an unowned file from `deleteBlob`.
    init(filePath: String, createdAt: Date = Date(), sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .file, text: filePath, imagePath: nil, createdAt: createdAt,
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

    /// Copy with the two fields the store rewrites; the pin is always stated outright.
    func with(createdAt: Date? = nil, pinnedAt: Date?) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath,
            createdAt: createdAt ?? self.createdAt, sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt)
    }

    /// Case-insensitive substring match: how the store filters without FTS.
    func matches(_ query: String) -> Bool {
        text?.localizedCaseInsensitiveContains(query) ?? false
    }
}

/// Retention in days; `forever` is -1, so an unset key (0) falls through to the default.
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

/// SQLite-backed clipboard history. See docs/features/clipboard.md#store.
@MainActor
@Observable
final class ClipboardStore {
    /// Newest-first with pins in place, every pin resident. docs/features/clipboard.md
    private(set) var items: [ClipboardItem] = [] {
        didSet {
            searchCache = nil
            orderedCache = nil
        }
    }
    var maxAge: TimeInterval = ClipboardRetention.threeMonths.maxAge

    /// One-entry memo so repeated renders reuse the FTS result; cleared when `items` changes.
    @ObservationIgnored private var searchCache:
        (query: String, filter: ClipboardFilter, result: [ClipboardItem])?
    /// Same memo for the empty query, so the pinned split runs once per mutation.
    @ObservationIgnored private var orderedCache: [ClipboardItem]?

    private static let memoryWindow = 1000

    nonisolated private static let insertSQL = """
        INSERT INTO items(id, kind, text, image_path, created_at, source_app, pinned_at)
        VALUES(?,?,?,?,?,?,?)
        """

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
        CREATE INDEX IF NOT EXISTS items_pinned_at ON items(pinned_at) WHERE pinned_at IS NOT NULL;
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

    /// Internal, not private: a backup names both to stream the table and adopt its blobs.
    let imagesDir: URL
    let dbURL: URL
    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var insertStmt: OpaquePointer?
    @ObservationIgnored private var loadStmt: OpaquePointer?
    @ObservationIgnored private var windowFloorStmt: OpaquePointer?
    @ObservationIgnored private var searchStmt: OpaquePointer?
    @ObservationIgnored private var deleteByIDStmt: OpaquePointer?
    @ObservationIgnored private var pinStmt: OpaquePointer?
    @ObservationIgnored private var staleImagesStmt: OpaquePointer?
    @ObservationIgnored private var deleteStaleStmt: OpaquePointer?

    /// `directory` defaults to the per-channel store; the harness passes a throwaway one.
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        dbURL = base.appendingPathComponent("clipboard.sqlite3")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        open()
    }

    /// Idempotent, so the coordinator can re-open the file when the feature is switched back on.
    func open() {
        guard db == nil else { return }
        if openDatabase() { return }
        // Captured, not authored: discard a corrupt or outdated database and start over.
        closeDatabase()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + suffix)
        }
        if !openDatabase() { closeDatabase() }
    }

    /// Every accessor is statement-guarded, so a closed store answers as an empty history.
    func close() {
        closeDatabase()
        items = []
    }

    /// Application Support, not Caches: a history the OS may reclaim is not a history.
    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // Isolated so teardown may touch the main-actor pointers; the release is already on main.
    isolated deinit {
        closeDatabase()
    }

    func load() {
        guard let stmt = loadStmt else { return }
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

    /// The floor rowid `loadStmt` reads from; 0 means no floor, so load everything.
    private func windowFloor() -> sqlite3_int64 {
        guard let stmt = windowFloorStmt else { return 0 }
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

    /// One row per file. Batched, so a multi-file copy prunes once rather than once per file.
    func addFiles(_ paths: [String], sourceBundleID: String?) {
        // Only a single file can be a ⌘C repeat, which is the case `addText` also guards.
        if paths.count == 1, items.first?.kind == .file, items.first?.text == paths[0] { return }
        for path in paths {
            let item = ClipboardItem(filePath: path, sourceBundleID: sourceBundleID)
            if let stmt = insertStmt { Self.bindAndInsert(stmt, item) }
            items.insert(item, at: 0)
        }
        trimWindow()
        prune()
    }

    func addImage(_ data: Data, sourceBundleID: String?) {
        let url = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        let item = ClipboardItem(imagePath: url.path, sourceBundleID: sourceBundleID)
        // The blob write is multi-MB I/O; only the row insert returns to the main actor.
        Task.detached(priority: .utility) { [weak self] in
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            await self?.insert(item)
        }
    }

    /// Bulk-insert from an import: original timestamps, external image paths, deduped.
    @discardableResult
    func importEntries(_ entries: [ClipboardItem]) -> Int {
        // Oldest first so newest ends up with the highest rowid (load orders by rowid DESC).
        let inserted = Self.importStoredItems(
            inDatabaseAt: dbURL, entries.sorted { $0.createdAt < $1.createdAt })
        load()
        return inserted
    }

    /// Move an item to the top; pasting or copying it from the palette re-recencies it.
    func promote(_ item: ClipboardItem) {
        // A pinned row holds its place, so re-recencying it would rewrite for no change.
        guard !item.isPinned, items.first?.id != item.id else { return }
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    func togglePinned(_ item: ClipboardItem) {
        if item.isPinned { unpin(item) } else { pin(item) }
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

    func fileURL(for item: ClipboardItem) -> URL? {
        guard let path = item.filePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Display order for `query` under `filter`: pinned entries first, each block newest-first.
    func search(_ query: String, filter: ClipboardFilter) -> [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        // The filter joins the key: `rows` rebuilds per render, so a query-only memo goes stale.
        if let searchCache, searchCache.query == q, searchCache.filter == filter {
            return searchCache.result
        }
        // Filtering after the split leaves a matching pin in the Pinned section, in pin order.
        let result = filter.apply(to: unfiltered(q))
        searchCache = (q, filter, result)
        return result
    }

    /// Row index of `item` as currently listed, so the palette can follow a row that moved.
    func rowIndex(of item: ClipboardItem, in query: String, filter: ClipboardFilter) -> Int? {
        search(query, filter: filter).firstIndex { $0.id == item.id }
    }

    /// The Nth visible pinned entry under `query` and `filter`, where 0 is the first pinned row.
    func pinnedItem(at index: Int, in query: String, filter: ClipboardFilter) -> ClipboardItem? {
        guard index >= 0 else { return nil }
        return search(query, filter: filter).prefix(while: \.isPinned).dropFirst(index).first
    }

    private func unfiltered(_ q: String) -> [ClipboardItem] {
        guard !q.isEmpty else { return orderedItems }
        // Pins are matched in memory: all resident, and the LIMIT would otherwise drop one.
        return pinnedItems.filter { $0.matches(q) } + runSearch(q).filter { !$0.isPinned }
    }

    private func runSearch(_ q: String) -> [ClipboardItem] {
        // Trigram FTS needs ≥3 characters; shorter queries filter the in-memory window.
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

    /// The Pinned section in pin order, so a new pin joins the end rather than the head.
    private var pinnedItems: [ClipboardItem] {
        items.filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture) }
    }

    /// The row keeps its place and gains a stamp, which heads the Pinned section.
    private func pin(_ item: ClipboardItem) {
        let stamp = Date()
        let pinned = item.with(pinnedAt: stamp)
        if let stmt = pinStmt {
            sqlite3_bind_double(stmt, 1, stamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = pinned
        } else {
            // Pinned from an FTS hit outside the window, so splice it in by recency.
            let index = items.firstIndex { $0.createdAt < pinned.createdAt } ?? items.count
            items.insert(pinned, at: index)
        }
    }

    /// Unpinning rejoins as the newest entry. See docs/features/clipboard.md#pinned-entries.
    private func unpin(_ item: ClipboardItem) {
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    /// Rewrite a row under the same id so it leads. See docs/features/clipboard.md#store.
    private func reinsert(_ updated: ClipboardItem) {
        if let deleteStmt = deleteByIDStmt, let insertStmt {
            // One transaction: `id` is UNIQUE, and a crash between the two must not lose it.
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            sqlite3_bind_text(deleteStmt, 1, updated.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
            Self.bindAndInsert(insertStmt, updated)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
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
        if let stmt = insertStmt { Self.bindAndInsert(stmt, item) }
        items.insert(item, at: 0)
        trimWindow()
        prune()
    }

    nonisolated private static func bindAndInsert(_ stmt: OpaquePointer, _ item: ClipboardItem) {
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

    /// Whether a path is inside our images directory; only those are ours to delete.
    private func owns(_ path: String) -> Bool {
        path.hasPrefix(imagesDir.path + "/")
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        if let imagesStmt = staleImagesStmt, let deleteStmt = deleteStaleStmt {
            sqlite3_bind_double(imagesStmt, 1, cutoff.timeIntervalSince1970)
            var staleOwnedPaths: [String] = []
            while sqlite3_step(imagesStmt) == SQLITE_ROW {
                // Only delete files we own; an external reference just loses its row.
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
            // A retention cut can strand hundreds of files, so delete them off the main actor.
            if !staleOwnedPaths.isEmpty {
                Task.detached(priority: .utility) {
                    for path in staleOwnedPaths {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }
            }
        }
        // Against the oldest unpinned row: an exempt pin would make this permanently true.
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
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        insertStmt = prepare(Self.insertSQL)
        // Two indexed branches, deliberately not one OR. See docs/features/clipboard.md#store.
        loadStmt = prepare(
            """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at FROM (
              SELECT rowid AS rid, * FROM items WHERE rowid >= ?1
              UNION ALL
              SELECT rowid AS rid, * FROM items WHERE pinned_at IS NOT NULL AND rowid < ?1
            ) ORDER BY rid DESC
            """)
        windowFloorStmt = prepare(
            "SELECT rowid FROM items WHERE pinned_at IS NULL ORDER BY rowid DESC LIMIT 1 OFFSET ?")
        searchStmt = prepare(
            """
            SELECT i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned_at
            FROM items_fts f JOIN items i ON i.rowid = f.rowid
            WHERE items_fts MATCH ? ORDER BY f.rowid DESC LIMIT 200
            """)
        deleteByIDStmt = prepare("DELETE FROM items WHERE id = ?")
        // Only ever sets a stamp: unpinning rewrites the whole row so it leads the history again.
        pinStmt = prepare("UPDATE items SET pinned_at = ? WHERE id = ?")
        staleImagesStmt = prepare(
            """
            SELECT image_path FROM items
            WHERE created_at < ? AND pinned_at IS NULL AND image_path IS NOT NULL
            """)
        deleteStaleStmt = prepare("DELETE FROM items WHERE created_at < ? AND pinned_at IS NULL")
        return insertStmt != nil && loadStmt != nil && windowFloorStmt != nil && searchStmt != nil
            && deleteByIDStmt != nil && pinStmt != nil && staleImagesStmt != nil
            && deleteStaleStmt != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func closeDatabase() {
        [
            insertStmt, loadStmt, windowFloorStmt, searchStmt, deleteByIDStmt, pinStmt,
            staleImagesStmt, deleteStaleStmt
        ].forEach { sqlite3_finalize($0) }
        insertStmt = nil
        loadStmt = nil
        windowFloorStmt = nil
        searchStmt = nil
        deleteByIDStmt = nil
        pinStmt = nil
        staleImagesStmt = nil
        deleteStaleStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    /// Streams an import into the file off-main; a staged blob moves into `imagesDirectory`,
    /// which is what makes `owns` true and lets retention reclaim it later.
    nonisolated static func importStoredItems(
        inDatabaseAt url: URL, adoptingImagesInto imagesDirectory: URL? = nil,
        _ items: some Sequence<ClipboardItem>
    ) -> Int {
        var keys: Set<Int> = []
        forEachStoredItem(inDatabaseAt: url) { keys.insert(importKey($0)) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return 0
        }
        defer { sqlite3_close_v2(db) }
        // A capture from the poller can hold the write lock; without this the import truncates.
        sqlite3_busy_timeout(db, 5_000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        var inserted = 0
        // One transaction for the batch: ~1 WAL commit rather than one per row.
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for staged in items {
            let item = adoptionTarget(staged, in: imagesDirectory)
            guard keys.insert(importKey(item)).inserted else { continue }
            if item.imagePath != staged.imagePath,
                !moveBlob(from: staged.imagePath, to: item.imagePath)
            {
                continue
            }
            bindAndInsert(stmt, item)
            inserted += 1
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        return inserted
    }

    /// Hashed, never held: a whole history's text must not sit in memory to dedupe an import.
    nonisolated private static func importKey(_ item: ClipboardItem) -> Int {
        var hasher = Hasher()
        hasher.combine(item.kind)
        // Keyed off `text` for everything but an image, or every file entry hashes alike.
        hasher.combine(item.kind == .image ? item.imagePath : item.text)
        return hasher.finalize()
    }

    /// Keeps the staged blob's name, so importing one backup twice lands on the same path — and
    /// the row dedupes on it rather than minting a second copy of every image.
    nonisolated private static func adoptionTarget(
        _ item: ClipboardItem, in directory: URL?
    ) -> ClipboardItem {
        guard let directory, item.kind == .image, let path = item.imagePath else { return item }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return ClipboardItem(
            id: item.id, kind: .image, text: nil,
            imagePath: directory.appendingPathComponent(name).path, createdAt: item.createdAt,
            sourceBundleID: item.sourceBundleID, pinnedAt: item.pinnedAt)
    }

    /// false leaves the row out, so none ever points into a staging tree about to be discarded.
    nonisolated private static func moveBlob(from source: String?, to destination: String?) -> Bool {
        guard let source, let destination else { return false }
        let from = URL(fileURLWithPath: source)
        let to = URL(fileURLWithPath: destination)
        return (try? FileManager.default.moveItem(at: from, to: to)) != nil
            || (try? FileManager.default.copyItem(at: from, to: to)) != nil
    }

    /// Past the memory window, off-main. `READWRITE` because a WAL reader still writes `-shm`.
    nonisolated static func forEachStoredItem(
        inDatabaseAt url: URL, _ body: (ClipboardItem) -> Void
    ) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return
        }
        defer { sqlite3_close_v2(db) }
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at
            FROM items ORDER BY rowid
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = row(stmt) { body(item) }
        }
    }

    nonisolated private static func row(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let kindString = columnString(stmt, 1),
            let kind = ClipboardItem.Kind(rawValue: kindString)
        else { return nil }
        return ClipboardItem(
            id: id, kind: kind, text: columnString(stmt, 2), imagePath: columnString(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            sourceBundleID: columnString(stmt, 5), pinnedAt: columnDate(stmt, 6))
    }

    nonisolated private static func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    nonisolated private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}
