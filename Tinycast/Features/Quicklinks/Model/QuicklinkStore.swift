import Foundation
import SQLite3

// Spelled as the C macro in sqlite3.h, which isn't imported into Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite library of authored quicklinks, never deleted. See docs/features/quicklinks.md#storage.
@MainActor
@Observable
final class QuicklinkStore {
    /// Display order is `Quicklink.precedes`: pinned first by pin time, then the rest by name.
    private(set) var quicklinks: [Quicklink] = []
    /// False when the database wouldn't open; every mutation then refuses rather than pretends.
    private(set) var isAvailable = false
    var onChange: (([Quicklink]) -> Void)?

    private static let schema = """
        CREATE TABLE IF NOT EXISTS quicklinks(
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          link TEXT NOT NULL,
          open_with TEXT,
          icon TEXT,
          in_root_search INTEGER NOT NULL DEFAULT 1,
          pinned_at REAL,
          created_at REAL NOT NULL
        );
        """

    private let dbURL: URL
    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var upsertStmt: OpaquePointer?
    @ObservationIgnored private var loadStmt: OpaquePointer?
    @ObservationIgnored private var deleteStmt: OpaquePointer?

    /// `directory` defaults per channel; the harness passes a throwaway one.
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        dbURL = base.appendingPathComponent("quicklinks.sqlite3")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        isAvailable = openDatabase()
        // A failed open leaves the file alone: this is authored data, so report, never delete.
        if !isAvailable { closeDatabase() }
    }

    /// Under Application Support, the same per-channel root snippets use.
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
        var loaded: [Quicklink] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let row = Self.row(stmt) { loaded.append(row) }
        }
        sqlite3_reset(stmt)
        quicklinks = loaded.sorted(by: Quicklink.precedes)
    }

    func quicklink(id: UUID) -> Quicklink? {
        quicklinks.first { $0.id == id }
    }

    func quicklink(entryID: String) -> Quicklink? {
        Quicklink.id(fromEntryID: entryID).flatMap(quicklink)
    }

    // Takes a whole draft, so adding an option doesn't churn every call site.
    @discardableResult
    func add(_ draft: Quicklink) throws(QuicklinkError) -> Quicklink {
        let value = try validated(draft)
        try write(value)
        return value
    }

    func update(_ draft: Quicklink) throws(QuicklinkError) {
        guard quicklinks.contains(where: { $0.id == draft.id }) else { return }
        try write(validated(draft))
    }

    func remove(id: UUID) throws(QuicklinkError) {
        guard let stmt = deleteStmt else { throw .storageUnavailable }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        let status = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard status == SQLITE_DONE else { throw .storageUnavailable }
        commit(quicklinks.filter { $0.id != id })
    }

    func togglePinned(id: UUID) throws(QuicklinkError) {
        guard var value = quicklink(id: id) else { return }
        value.pinnedAt = value.isPinned ? nil : Date()
        try write(value)
    }

    func setShowsInRootSearch(_ shows: Bool, id: UUID) throws(QuicklinkError) {
        guard var value = quicklink(id: id), value.showsInRootSearch != shows else { return }
        value.showsInRootSearch = shows
        try write(value)
    }

    /// "Duplicate": a new identity, so references stay with the original, plus a distinct name.
    @discardableResult
    func duplicate(id: UUID) throws(QuicklinkError) -> Quicklink {
        guard let source = quicklink(id: id) else { throw .storageUnavailable }
        return try add(
            Quicklink(
                name: Self.uniqueName(basedOn: source.name, taken: quicklinks.map(\.name)),
                link: source.link, openWithBundleID: source.openWithBundleID,
                iconSymbol: source.iconSymbol, showsInRootSearch: source.showsInRootSearch))
    }

    /// Adds a batch, skipping anything invalid — the import and backup path. Returns what landed.
    @discardableResult
    func append(_ incoming: [Quicklink]) -> [Quicklink] {
        var added: [Quicklink] = []
        for candidate in incoming {
            if let stored = try? add(candidate) { added.append(stored) }
        }
        return added
    }

    /// Replaces the whole set on backup import, dropping invalid and duplicate records.
    @discardableResult
    func replace(with incoming: [Quicklink]) -> Int {
        guard isAvailable, sqlite3_exec(db, "DELETE FROM quicklinks", nil, nil, nil) == SQLITE_OK
        else { return 0 }
        commit([])
        return append(Self.sanitized(incoming)).count
    }

    private func write(_ value: Quicklink) throws(QuicklinkError) {
        guard let stmt = upsertStmt else { throw .storageUnavailable }
        sqlite3_bind_text(stmt, 1, value.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, value.link, -1, SQLITE_TRANSIENT)
        bind(stmt, 4, value.openWithBundleID)
        bind(stmt, 5, value.iconSymbol)
        sqlite3_bind_int(stmt, 6, value.showsInRootSearch ? 1 : 0)
        if let pinnedAt = value.pinnedAt {
            sqlite3_bind_double(stmt, 7, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_bind_double(stmt, 8, value.createdAt.timeIntervalSince1970)
        let status = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard status == SQLITE_DONE else { throw .storageUnavailable }

        var updated = quicklinks.filter { $0.id != value.id }
        updated.append(value)
        commit(updated.sorted(by: Quicklink.precedes))
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func commit(_ updated: [Quicklink]) {
        guard updated != quicklinks else { return }
        quicklinks = updated
        onChange?(updated)
    }

    private func validated(_ draft: Quicklink) throws(QuicklinkError) -> Quicklink {
        guard isAvailable else { throw .storageUnavailable }
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        value.iconSymbol =
            draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        value.openWithBundleID =
            draft.openWithBundleID?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.link.isEmpty else { throw .emptyLink }
        guard !value.name.contains("\0"), !value.link.contains("\0") else {
            throw .invalidCharacter
        }
        // A templated link is only knowable once filled, so it is reported at open time.
        guard
            QuicklinkDestination.containsPlaceholder(value.link)
                || QuicklinkDestination.detect(value.link) != nil
        else { throw .unresolvableLink }
        guard
            !quicklinks.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    private static func uniqueName(basedOn name: String, taken: [String]) -> String {
        let folded = Set(taken.map { $0.folding(options: [.caseInsensitive], locale: .current) })
        var candidate = name + " Copy"
        var suffix = 2
        while folded.contains(candidate.folding(options: [.caseInsensitive], locale: .current)) {
            candidate = "\(name) Copy \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func sanitized(_ values: [Quicklink]) -> [Quicklink] {
        var ids = Set<UUID>()
        // Copy-and-clean rather than rebuild, so a new option can never be dropped on import.
        return values.filter { ids.insert($0.id).inserted }
    }

    // MARK: - SQLite

    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        // After the schema, so a column added later can be indexed the same way.
        sqlite3_exec(
            db,
            "CREATE INDEX IF NOT EXISTS quicklinks_pinned_at ON quicklinks(pinned_at) WHERE pinned_at IS NOT NULL",
            nil, nil, nil)
        upsertStmt = prepare(
            """
            INSERT INTO quicklinks(id, name, link, open_with, icon, in_root_search, pinned_at, created_at)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name, link = excluded.link, open_with = excluded.open_with,
              icon = excluded.icon, in_root_search = excluded.in_root_search,
              pinned_at = excluded.pinned_at
            """
        )
        loadStmt = prepare(
            """
            SELECT id, name, link, open_with, icon, in_root_search, pinned_at, created_at
            FROM quicklinks
            """
        )
        deleteStmt = prepare("DELETE FROM quicklinks WHERE id = ?")
        return upsertStmt != nil && loadStmt != nil && deleteStmt != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func closeDatabase() {
        [upsertStmt, loadStmt, deleteStmt].forEach { sqlite3_finalize($0) }
        upsertStmt = nil
        loadStmt = nil
        deleteStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    private static func row(_ stmt: OpaquePointer?) -> Quicklink? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let name = columnString(stmt, 1), let link = columnString(stmt, 2)
        else { return nil }
        return Quicklink(
            id: id, name: name, link: link, openWithBundleID: columnString(stmt, 3),
            iconSymbol: columnString(stmt, 4),
            showsInRootSearch: sqlite3_column_int(stmt, 5) != 0,
            pinnedAt: columnDate(stmt, 6),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)))
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

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
