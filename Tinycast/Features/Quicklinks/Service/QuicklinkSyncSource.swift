import Foundation

/// Quicklinks by UUID; an arriving name already taken here replaces the local holder.
@MainActor
final class QuicklinkSyncSource: SyncSource {
    let id = SyncSourceID.quicklinks
    private let store: QuicklinkStore

    init(store: QuicklinkStore) {
        self.store = store
    }

    func observe() {
        _ = store.quicklinks
        _ = store.isAvailable
    }

    func snapshot() async -> [String: String]? {
        guard store.isAvailable else { return nil }
        return SyncPayload.snapshot(
            Dictionary(uniqueKeysWithValues: store.quicklinks.map { (Self.key($0.id), $0) }))
    }

    func payload(for key: String) async -> Data? {
        UUID(uuidString: key).flatMap(store.quicklink(id:)).flatMap(SyncPayload.encode)
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        var deferred: Set<String> = []
        for key in changes.deletions {
            guard let id = UUID(uuidString: key), store.quicklink(id: id) != nil else { continue }
            if (try? store.remove(id: id)) == nil { deferred.insert(key) }
        }
        for (key, payload) in changes.upserts {
            guard let incoming = SyncPayload.decode(Quicklink.self, from: payload) else { continue }
            for holder in store.quicklinks where holder.id != incoming.id && Self.sameName(holder, incoming) {
                try? store.remove(id: holder.id)
            }
            do {
                if store.quicklink(id: incoming.id) == nil {
                    try store.add(incoming)
                } else {
                    try store.update(incoming)
                }
            } catch .storageUnavailable {
                deferred.insert(key)
            } catch {
                continue
            }
        }
        return deferred
    }

    /// Duplicates by name or destination, as an import judges them.
    func duplicates(of incoming: [String: Data], among candidates: Set<String>) async -> Set<String> {
        let arriving = incoming.values.compactMap { SyncPayload.decode(Quicklink.self, from: $0) }
        return Set(
            store.quicklinks.filter { local in
                candidates.contains(Self.key(local.id))
                    && arriving.contains { Self.sameName($0, local) || Self.sameLink($0, local) }
            }.map { Self.key($0.id) })
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    private static func sameName(_ lhs: Quicklink, _ rhs: Quicklink) -> Bool {
        lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(rhs.name.trimmingCharacters(in: .whitespacesAndNewlines), options: .caseInsensitive)
            == .orderedSame
    }

    private static func sameLink(_ lhs: Quicklink, _ rhs: Quicklink) -> Bool {
        lhs.link.trimmingCharacters(in: .whitespacesAndNewlines)
            == rhs.link.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
