import Foundation

struct SyncChanges: Sendable {
    var upserts: [String: Data] = [:]
    var deletions: Set<String> = []

    var isEmpty: Bool { upserts.isEmpty && deletions.isEmpty }
}

@MainActor
protocol SyncSource: AnyObject, Sendable {
    var id: SyncSourceID { get }
    /// Reads the observable state that changes whenever the items might have.
    func observe()
    /// Every item's key and version, or nil while the source can't speak for its data.
    func snapshot() async -> [String: String]?
    func payload(for key: String) async -> Data?
    /// Applies what arrived, and returns the keys it has to try again later.
    func apply(_ changes: SyncChanges) async -> Set<String>
    /// Local keys among `candidates` holding the same content as an incoming item.
    func duplicates(of incoming: [String: Data], among candidates: Set<String>) async -> Set<String>
    /// Moves a local item aside so a different incoming one can take its key.
    func preserveLocal(_ key: String) async -> Bool
}

extension SyncSource {
    func duplicates(of incoming: [String: Data], among candidates: Set<String>) async -> Set<String> {
        []
    }

    func preserveLocal(_ key: String) async -> Bool { false }
}

/// The JSON every Codable payload travels as: sorted keys, so equal content is equal bytes.
enum SyncPayload {
    static func encode<Value: Encodable>(_ value: Value) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) -> Value? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func snapshot<Item: Encodable>(_ items: [String: Item]) -> [String: String] {
        items.compactMapValues { encode($0).map(SyncVersion.of) }
    }
}
