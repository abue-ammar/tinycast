import Foundation

/// One learned launcher choice for a normalized query prefix.
struct LauncherRankingRecord: Codable, Hashable, Sendable {
    let itemKey: String
    let query: String
    var count: Int
    var lastUsed: Date
}

/// Learns which launcher results the user chooses for each query and persists the bounded,
/// on-device-only frecency data under `~/Library/Caches/<bundle-id>/`.
@MainActor
final class LauncherRankingStore: ObservableObject {
    private static let cap = 1_000
    /// The adaptive boost stays below half the 10k gaps between FuzzyMatch's relevance tiers, so
    /// learned usage can reorder similarly-matching results without beating a stronger match kind.
    private static let maximumBoost = 4_500

    private let fileURL: URL
    private let now: () -> Date

    @Published private(set) var records: [LauncherRankingRecord]
    /// AppIndex includes this in its one-entry cache key, invalidating a result after a visit/reset.
    private(set) var revision = 0

    private var lookup: [String: [String: LauncherRankingRecord]]?

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.now = now

        if let data = try? Data(contentsOf: self.fileURL),
            let decoded = try? JSONDecoder().decode([LauncherRankingRecord].self, from: data)
        {
            records = decoded.filter {
                !$0.itemKey.isEmpty && !$0.query.isEmpty && $0.count > 0
            }
        } else {
            records = []
        }
    }

    var isEmpty: Bool { records.isEmpty }

    /// Record every prefix of the submitted query: choosing WhatsApp for "wha" teaches "w",
    /// "wh", and "wha", letting the preferred result surface for progressively shorter input.
    func record(itemKey: String, query: String) {
        let query = Self.normalize(query)
        guard !itemKey.isEmpty, !query.isEmpty else { return }

        let timestamp = now()
        for prefix in Self.prefixes(of: query) {
            if let index = records.firstIndex(where: {
                $0.itemKey == itemKey && $0.query == prefix
            }) {
                records[index].count += 1
                records[index].lastUsed = timestamp
            } else {
                records.append(
                    LauncherRankingRecord(
                        itemKey: itemKey, query: prefix, count: 1, lastUsed: timestamp))
            }
        }

        if records.count > Self.cap {
            records.sort {
                $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed
            }
            records.removeLast(records.count - Self.cap)
        }
        didMutate()
    }

    /// A bounded blend of frequency and exponentially-decaying recency for this exact query.
    func boost(itemKey: String, query: String) -> Int {
        let query = Self.normalize(query)
        guard !query.isEmpty, let record = rankingLookup()[query]?[itemKey] else { return 0 }

        let age = max(0, now().timeIntervalSince(record.lastUsed))
        let ageInDays = age / 86_400
        // Cap frequency separately so an old, once-dominant habit cannot stay permanently pinned;
        // enough recent visits to a different result can eventually overtake it.
        let frequency = min(3_000, log2(Double(record.count) + 1) * 600)
        let recency = 1_500 * exp(-ageInDays / 14)
        return min(Self.maximumBoost, Int((frequency + recency).rounded()))
    }

    func hasRanking(for itemKey: String) -> Bool {
        records.contains { $0.itemKey == itemKey }
    }

    func reset(itemKey: String) {
        let oldCount = records.count
        records.removeAll { $0.itemKey == itemKey }
        guard records.count != oldCount else { return }
        didMutate()
    }

    func resetAll() {
        guard !records.isEmpty else { return }
        records = []
        didMutate()
    }

    static func normalize(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func prefixes(of query: String) -> [String] {
        // Launcher names and useful queries are short; cap pathological pasted input so one visit
        // cannot evict the whole bounded ranking table.
        let limit = min(query.count, 64)
        var result: [String] = []
        result.reserveCapacity(limit)
        var end = query.startIndex
        for _ in 0..<limit {
            end = query.index(after: end)
            result.append(String(query[..<end]))
        }
        return result
    }

    private func rankingLookup() -> [String: [String: LauncherRankingRecord]] {
        if let lookup { return lookup }
        var built: [String: [String: LauncherRankingRecord]] = [:]
        for record in records {
            built[record.query, default: [:]][record.itemKey] = record
        }
        lookup = built
        return built
    }

    private func didMutate() {
        lookup = nil
        revision &+= 1
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("launcher-ranking.json")
    }
}
