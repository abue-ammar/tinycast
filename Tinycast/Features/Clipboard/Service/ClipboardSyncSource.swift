import Foundation

@MainActor
final class ClipboardSyncSource: SyncSource {
    private struct Payload: Codable, Sendable {
        var text: String?
        var image: Data?
        /// Seconds, not a `Date`: ISO 8601 drops the fraction that orders two quick copies.
        var copiedAt: TimeInterval
        var pinnedAt: TimeInterval?
        var sourceBundleID: String?
    }

    /// No text or image, so holding a whole history costs a few bytes an entry.
    private struct Row: Sendable {
        let id: UUID
        let createdAt: Date
        let pinnedAt: Date?
    }

    let id: SyncSourceID
    private let kind: ClipboardItem.Kind
    private let store: ClipboardStore
    private let isActive: () -> Bool
    /// The last snapshot's rows by key, oldest first, so a payload never rescans the table.
    private var held: [String: [Row]] = [:]

    /// `kind` is `.text` or `.image`; a copied file names a path that means nothing elsewhere.
    init(_ kind: ClipboardItem.Kind, store: ClipboardStore, isActive: @escaping () -> Bool) {
        id = kind == .image ? .clipboardImages : .clipboardText
        self.kind = kind
        self.store = store
        self.isActive = isActive
    }

    func observe() {
        if isActive() { _ = store.items }
    }

    func snapshot() async -> [String: String]? {
        guard isActive(), store.isOpen,
            let rows = await Self.rows(of: kind, in: store.dbURL, imagesDir: store.imagesDir)
        else { return nil }
        held = rows
        return rows.compactMapValues { Self.representative(of: $0).map(Self.version) }
    }

    func payload(for key: String) async -> Data? {
        guard isActive(), let row = held[key].flatMap(Self.representative(of:)),
            let item = store.item(id: row.id),
            item.createdAt == row.createdAt, item.pinnedAt == row.pinnedAt,
            Self.key(of: item, imagesDir: store.imagesDir) == key
        else { return nil }
        let payload = Payload(
            text: item.text, copiedAt: item.createdAt.timeIntervalSince1970,
            pinnedAt: item.pinnedAt?.timeIntervalSince1970, sourceBundleID: item.sourceBundleID)
        let encoded = await Self.encode(payload, imageAt: item.imagePath)
        return isActive() ? encoded : nil
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        let everything = Set(changes.upserts.keys).union(changes.deletions)
        guard isActive(), store.isOpen else { return everything }
        async let decoded = Self.decode(changes.upserts)
        guard let local = await Self.rows(of: kind, in: store.dbURL, imagesDir: store.imagesDir)
        else { return everything }
        var keys: [UUID: String] = [:]
        var arrivals: [ClipboardItem] = []
        var images: [String: Data] = [:]
        for (key, payload) in await decoded {
            let existing = local[key].flatMap(Self.representative(of:))?.id
            guard let item = item(for: key, from: payload, replacing: existing) else { continue }
            if existing == nil, let path = item.imagePath { images[path] = payload.image }
            keys[item.id] = key
            arrivals.append(item)
        }
        var removed: Set<UUID> = []
        for key in changes.deletions {
            for row in local[key] ?? [] {
                removed.insert(row.id)
                keys[row.id] = key
            }
        }
        guard isActive(), store.isOpen else { return everything }
        let failed = await store.applySynced(arrivals, images: images, removing: removed)
        return Set(failed.compactMap { keys[$0] })
    }

    private func item(for key: String, from payload: Payload, replacing existing: UUID?) -> ClipboardItem? {
        let imagePath: String?
        if kind == .image {
            guard Self.isBlobName(key), existing != nil || payload.image != nil else { return nil }
            imagePath = store.imagesDir.appendingPathComponent(key).path
        } else {
            guard let text = payload.text, Self.key(ofText: text) == key else { return nil }
            imagePath = nil
        }
        return ClipboardItem(
            id: existing ?? UUID(), kind: kind, text: kind == .text ? payload.text : nil,
            imagePath: imagePath, createdAt: Date(timeIntervalSince1970: payload.copiedAt),
            sourceBundleID: payload.sourceBundleID,
            pinnedAt: payload.pinnedAt.map(Date.init(timeIntervalSince1970:)))
    }

    /// Nil when the table couldn't be read to the end, which must pause rather than delete.
    @concurrent
    private static func rows(
        of kind: ClipboardItem.Kind, in database: URL, imagesDir: URL
    ) async -> [String: [Row]]? {
        var rows: [String: [Row]] = [:]
        let complete = ClipboardStore.forEachStoredItem(inDatabaseAt: database) { item in
            guard item.kind == kind, let key = key(of: item, imagesDir: imagesDir) else { return }
            rows[key, default: []].append(
                Row(id: item.id, createdAt: item.createdAt, pinnedAt: item.pinnedAt))
        }
        return complete ? rows : nil
    }

    @concurrent
    private static func encode(_ payload: Payload, imageAt path: String?) async -> Data? {
        var payload = payload
        if let path {
            guard let image = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            payload.image = image
        }
        return SyncPayload.encode(payload)
    }

    @concurrent
    private static func decode(_ upserts: [String: Data]) async -> [String: Payload] {
        upserts.compactMapValues { SyncPayload.decode(Payload.self, from: $0) }
    }

    /// A pin outranks recency, so pinning an older duplicate still travels.
    nonisolated private static func representative(of rows: [Row]) -> Row? {
        rows.last { $0.pinnedAt != nil } ?? rows.last
    }

    nonisolated private static func key(of item: ClipboardItem, imagesDir: URL) -> String? {
        switch item.kind {
        case .text:
            return item.text.map(key(ofText:))
        case .image:
            guard let path = item.imagePath, ClipboardStore.owns(path, in: imagesDir) else { return nil }
            let name = URL(fileURLWithPath: path).lastPathComponent
            return isBlobName(name) ? name : nil
        case .file:
            return nil
        }
    }

    nonisolated private static func key(ofText text: String) -> String {
        SyncVersion.of(Data(text.utf8))
    }

    /// The name `addImage` gives a blob, checked before an arriving key may name a file here.
    nonisolated private static func isBlobName(_ name: String) -> Bool {
        name.hasSuffix(".png") && UUID(uuidString: String(name.dropLast(4))) != nil
    }

    nonisolated private static func version(of row: Row) -> String {
        let fields = [row.createdAt, row.pinnedAt].map { "\($0?.timeIntervalSince1970 ?? 0)" }
        return SyncVersion.of(Data(fields.joined(separator: "\u{0}").utf8))
    }
}
