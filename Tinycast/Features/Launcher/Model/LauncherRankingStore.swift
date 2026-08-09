import Foundation

/// One learned launcher choice for a normalized query prefix.
struct LauncherRankingRecord: Codable, Hashable, Sendable {
    let itemKey: String
    let query: String
    var count: Int
    var lastUsed: Date
}

/// Learns which result a query leads to, as bounded on-device frecency data in Caches.
@MainActor
@Observable
final class LauncherRankingStore {
    private static let cap = 1_000
    /// Below half a tier gap, so a learned boost reorders within a tier but never across.
    private static let maximumBoost = 4_500

    private let fileURL: URL
    private let now: () -> Date

    private(set) var records: [LauncherRankingRecord]
    /// Part of `AppIndex`'s cache key, invalidating a result after a visit or a reset.
    private(set) var revision = 0

    /// `boosts(query:)` builds this from a launcher render; tracked, the write lands mid-body.
    @ObservationIgnored private var lookup: [String: [String: LauncherRankingRecord]]?
    /// The in-flight persist, awaited by the next one so a burst can't land out of order.
    @ObservationIgnored private var writeTask: Task<Void, Never>?

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

    /// Awaits the pending persist. The launcher never needs it; reading the file back does.
    func flush() async {
        await writeTask?.value
    }

    /// Records every prefix, so the preferred result surfaces for shorter input too.
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

    /// Boosts for one query; the fold and the clock read happen once, not per candidate.
    func boosts(query: String) -> [String: Int] {
        let query = Self.normalize(query)
        guard !query.isEmpty, let learned = rankingLookup()[query] else { return [:] }
        let timestamp = now()
        return learned.mapValues { boost($0, at: timestamp) }
    }

    private func boost(_ record: LauncherRankingRecord, at timestamp: Date) -> Int {
        let ageInDays = max(0, timestamp.timeIntervalSince(record.lastUsed)) / 86_400
        // Cap frequency separately, so an old habit cannot stay permanently pinned.
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

    /// Locale-independent: a Turkish fold maps "I" to "ı" and orphans every stored key.
    static func normalize(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func prefixes(of query: String) -> [String] {
        // Cap pasted input, so one visit cannot evict the whole bounded table.
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
        // Off-main: this lands on ↵, in front of the launch. Chained, so writes stay ordered.
        let snapshot = records
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
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
