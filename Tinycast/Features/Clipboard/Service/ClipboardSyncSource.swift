import Foundation

/// Text entries keyed by their content, or owned images keyed by their blob's file name.
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

    let id: SyncSourceID
    private let kind: ClipboardItem.Kind
    private let store: ClipboardStore
    private let isActive: () -> Bool
    /// The last snapshot's rows by key, oldest first, so a payload never rescans the table.
    private var held: [String: [ClipboardItem]] = [:]

    /// `kind` is `.text` or `.image`; a copied file names a path that means nothing elsewhere.
    init(_ kind: ClipboardItem.Kind, store: ClipboardStore, isActive: @escaping () -> Bool) {
        id = kind == .image ? .clipboardImages : .clipboardText
        self.kind = kind
        self.store = store
        self.isActive = isActive
    }

    func observe() {
        _ = isActive()
        _ = store.items
    }

    func snapshot() async -> [String: String]? {
        guard isActive(), store.isOpen else { return nil }
        held = await Self.rows(of: kind, in: store.dbURL, imagesDir: store.imagesDir)
        return held.compactMapValues { $0.last.map(Self.version) }
    }

    func payload(for key: String) async -> Data? {
        guard isActive(), let item = held[key]?.last else { return nil }
        let payload = Payload(
            text: item.text, copiedAt: item.createdAt.timeIntervalSince1970,
            pinnedAt: item.pinnedAt?.timeIntervalSince1970, sourceBundleID: item.sourceBundleID)
        return await Self.encode(payload, imageAt: item.imagePath)
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        let everything = Set(changes.upserts.keys).union(changes.deletions)
        guard isActive(), store.isOpen else { return everything }
        async let decoded = Self.decode(changes.upserts)
        let local = await Self.rows(of: kind, in: store.dbURL, imagesDir: store.imagesDir)
        var arrivals: [ClipboardItem] = []
        var images: [String: Data] = [:]
        for (key, payload) in await decoded {
            let existing = local[key]?.last
            guard let item = item(for: key, from: payload, replacing: existing) else { continue }
            if existing == nil, let path = item.imagePath { images[path] = payload.image }
            arrivals.append(item)
        }
        let removed = Set(changes.deletions.flatMap { local[$0] ?? [] }.map(\.id))
        guard isActive(), store.isOpen else { return everything }
        await store.applySynced(arrivals, images: images, removing: removed)
        return []
    }

    /// The local id carries over, so an arrival updates the entry this Mac already shows.
    private func item(
        for key: String, from payload: Payload, replacing existing: ClipboardItem?
    ) -> ClipboardItem? {
        let imagePath: String?
        if kind == .image {
            guard Self.isBlobName(key), existing != nil || payload.image != nil else { return nil }
            imagePath = store.imagesDir.appendingPathComponent(key).path
        } else {
            guard let text = payload.text, Self.key(ofText: text) == key else { return nil }
            imagePath = nil
        }
        return ClipboardItem(
            id: existing?.id ?? UUID(), kind: kind, text: kind == .text ? payload.text : nil,
            imagePath: imagePath, createdAt: Date(timeIntervalSince1970: payload.copiedAt),
            sourceBundleID: existing?.sourceBundleID ?? payload.sourceBundleID,
            pinnedAt: payload.pinnedAt.map(Date.init(timeIntervalSince1970:)))
    }

    @concurrent
    private static func rows(
        of kind: ClipboardItem.Kind, in database: URL, imagesDir: URL
    ) async -> [String: [ClipboardItem]] {
        var rows: [String: [ClipboardItem]] = [:]
        ClipboardStore.forEachStoredItem(inDatabaseAt: database) { item in
            guard item.kind == kind, let key = key(of: item, imagesDir: imagesDir) else { return }
            rows[key, default: []].append(item)
        }
        return rows
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

    nonisolated private static func version(of item: ClipboardItem) -> String {
        let fields = [item.createdAt, item.pinnedAt].map { "\($0?.timeIntervalSince1970 ?? 0)" }
        return SyncVersion.of(Data(fields.joined(separator: "\u{0}").utf8))
    }
}
