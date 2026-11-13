import Foundation

/// One entry's usage: a decaying score, and the terms it was last opened by.
struct LauncherVisit: Codable, Hashable, Sendable {
    /// When the decayed score falls back to 1, so a later anchor is always the higher score.
    var anchor: Date
    var openedAt: Date
    /// Distinct and folded, most recent last, at most `LauncherRankingStore.termLimit`.
    var searchTerms: [String]
}

struct LauncherUsage: Sendable, Equatable {
    /// 1 for an entry never opened, or opened too long ago to count.
    let frecency: Double
    /// Empty unless the entry was opened recently enough for its terms to steer a query.
    let searchTerms: [String]

    static let unused = LauncherUsage(frecency: 1, searchTerms: [])
}

/// Learns what the user opens, and by which query, as bounded on-device frecency data.
@MainActor
@Observable
final class LauncherRankingStore {
    /// Each visit adds 100 to a score that halves every ten days and never drops below 1.
    nonisolated static let halfLife: TimeInterval = 10 * 86_400
    nonisolated static let visitWeight = 100.0
    /// Past this since the last open, an entry's search terms stop steering the ranking.
    nonisolated static let termWindow: TimeInterval = 408 * 3_600
    nonisolated static let termLimit = 3
    /// `exp` overflows a `Double` just past this.
    private nonisolated static let exponentCeiling = 709.78
    /// Caps pasted input, so one visit cannot store a paragraph as a term.
    private static let queryLimit = 64

    private let fileURL: URL
    private let now: () -> Date

    private(set) var visits: [String: LauncherVisit]
    /// Part of `AppIndex`'s cache key, invalidating a result after a visit or a reset.
    private(set) var revision = 0

    /// The in-flight persist, awaited by the next one so a burst can't land out of order.
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.now = now
        let decoded =
            (try? Data(contentsOf: self.fileURL))
            .flatMap { try? JSONDecoder().decode([String: LauncherVisit].self, from: $0) } ?? [:]
        visits = Self.live(decoded, at: now())
    }

    var isEmpty: Bool { visits.isEmpty }

    /// Awaits the pending persist. The launcher never needs it; reading the file back does.
    func flush() async {
        await writeTask?.value
    }

    /// `query` is nil when the text was no search for the entry, like a category word.
    func visit(itemKey: String, query: String?) {
        guard !itemKey.isEmpty else { return }
        let timestamp = now()
        let previous = visits[itemKey]
        let score = previous.map { Self.frecency(anchor: $0.anchor, at: timestamp) } ?? 1
        var terms = previous?.searchTerms ?? []
        if let term = query.map(Self.normalize), !term.isEmpty, term.count <= Self.queryLimit {
            terms.removeAll { $0 == term }
            terms.append(term)
            terms = Array(terms.suffix(Self.termLimit))
        }
        visits[itemKey] = LauncherVisit(
            anchor: Self.anchor(visitedWith: score, at: timestamp), openedAt: timestamp,
            searchTerms: terms)
        didMutate()
    }

    /// Everything one ranking pass reads, with the clock read once for the whole pass.
    func snapshot() -> Snapshot { Snapshot(visits: visits, now: now()) }

    struct Snapshot: Sendable {
        let visits: [String: LauncherVisit]
        let now: Date

        func usage(for itemKey: String) -> LauncherUsage {
            LauncherRankingStore.usage(of: visits[itemKey], at: now)
        }
    }

    func hasRanking(for itemKey: String) -> Bool {
        visits[itemKey] != nil
    }

    func reset(itemKey: String) {
        guard visits.removeValue(forKey: itemKey) != nil else { return }
        didMutate()
    }

    func resetAll() {
        guard !visits.isEmpty else { return }
        visits = [:]
        didMutate()
    }

    /// Replaces the table wholesale from a backup, dropping what the initialiser would.
    func replace(_ imported: [String: LauncherVisit]) {
        visits = Self.live(imported, at: now())
        didMutate()
    }

    /// The form a query is matched in, so a term is stored as the ranking will compare it.
    nonisolated static func normalize(_ query: String) -> String {
        SearchText(query.trimmingCharacters(in: .whitespacesAndNewlines), transliterated: true).string
    }

    nonisolated static func frecency(anchor: Date, at timestamp: Date) -> Double {
        let exponent = decay * anchor.timeIntervalSince(timestamp)
        return max(1, exp(min(exponent, exponentCeiling)))
    }

    /// The anchor that puts the score at `score + visitWeight` right now.
    nonisolated static func anchor(visitedWith score: Double, at timestamp: Date) -> Date {
        timestamp.addingTimeInterval(log(score + visitWeight) / decay)
    }

    nonisolated static func usage(of visit: LauncherVisit?, at timestamp: Date) -> LauncherUsage {
        guard let visit else { return .unused }
        let frecency = frecency(anchor: visit.anchor, at: timestamp)
        let recent = frecency > 1 && timestamp.timeIntervalSince(visit.openedAt) < termWindow
        return LauncherUsage(frecency: frecency, searchTerms: recent ? visit.searchTerms : [])
    }

    private nonisolated static let decay = log(2) / halfLife

    /// A passed anchor scores 1 with its terms gated off, which is exactly an entry never opened.
    private nonisolated static func live(
        _ table: [String: LauncherVisit], at timestamp: Date
    ) -> [String: LauncherVisit] {
        table.filter { !$0.key.isEmpty && $0.value.anchor > timestamp }
    }

    private func didMutate() {
        revision &+= 1
        // Off-main: this lands on ↵, in front of the launch. Chained, so writes stay ordered.
        let snapshot = visits
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Application Support, not Caches: relearning a ranking takes the user weeks of use.
    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.abueammar.tinycast"
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("launcher-ranking.json")
    }
}
