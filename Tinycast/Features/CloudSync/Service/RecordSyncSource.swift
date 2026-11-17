import Foundation

@MainActor
final class RecordSyncSource<Record: Codable & Identifiable & Sendable>: SyncSource where Record.ID == UUID {
    let id: SyncSourceID
    private let records: () -> [Record]?
    private let save: (Record) -> Bool
    private let remove: (UUID) -> Bool
    private let isDuplicate: (Record, Record) -> Bool

    /// `records` is nil while unavailable; `save` and `remove` report whether the write landed.
    init(
        _ id: SyncSourceID, records: @escaping () -> [Record]?, save: @escaping (Record) -> Bool,
        remove: @escaping (UUID) -> Bool, isDuplicate: @escaping (Record, Record) -> Bool
    ) {
        self.id = id
        self.records = records
        self.save = save
        self.remove = remove
        self.isDuplicate = isDuplicate
    }

    func observe() {
        _ = records()
    }

    func snapshot() async -> [String: String]? {
        records().map {
            SyncPayload.snapshot(Dictionary(uniqueKeysWithValues: $0.map { (Self.key($0.id), $0) }))
        }
    }

    func payload(for key: String) async -> Data? {
        records()?.first { Self.key($0.id) == key }.flatMap(SyncPayload.encode)
    }

    /// Saves first, so an arriving twin can take over what a duplicate held before that goes.
    func apply(_ changes: SyncChanges) async -> Set<String> {
        var deferred: Set<String> = []
        for (key, payload) in changes.upserts {
            guard let record = SyncPayload.decode(Record.self, from: payload) else { continue }
            if !save(record) { deferred.insert(key) }
        }
        for key in changes.deletions {
            guard let id = UUID(uuidString: key), records()?.contains(where: { $0.id == id }) == true else {
                continue
            }
            if !remove(id) { deferred.insert(key) }
        }
        return deferred
    }

    func duplicates(of incoming: [String: Data], among candidates: Set<String>) async -> Set<String> {
        let arriving = incoming.values.compactMap { SyncPayload.decode(Record.self, from: $0) }
        return Set(
            (records() ?? []).filter { local in
                candidates.contains(Self.key(local.id)) && arriving.contains { isDuplicate($0, local) }
            }.map { Self.key($0.id) })
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }
}
