import Foundation

/// One past calculation, recorded when the user copies an answer.
struct CalcHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let expression: String
    let result: String
    let createdAt: Date
}

/// Persists recent calculations as a capped JSON file under `~/Library/Caches/<bundle-id>/`, alongside `ClipboardStore`'s data so `brew uninstall --zap` removes it too.
@MainActor
final class CalculatorHistoryStore: ObservableObject {
    private static let cap = 200

    private let fileURL: URL

    @Published private(set) var entries: [CalcHistoryEntry]  // newest first

    /// One-entry memo so repeated renders (e.g. arrow-key nav) for the same query reuse the filter instead of re-scanning every entry each frame; invalidated on any mutation.
    private var searchCache: (query: String, result: [CalcHistoryEntry])?

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.smallcast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("calculator-history.json")

        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([CalcHistoryEntry].self, from: data)
        {
            entries = decoded
        } else {
            entries = []
        }
    }

    func record(expression: String, result: String) {
        // Re-copying the same answer (Enter twice, or from history) shouldn't stack duplicates.
        if let latest = entries.first, latest.expression == expression, latest.result == result {
            return
        }
        entries.insert(
            CalcHistoryEntry(id: UUID(), expression: expression, result: result, createdAt: Date()),
            at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        persist()
    }

    func remove(_ entry: CalcHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clearAll() {
        entries = []
        persist()
    }

    /// Case-insensitive substring match over both sides of each calculation.
    func search(_ query: String) -> [CalcHistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        if let searchCache, searchCache.query == q { return searchCache.result }
        let result = entries.filter {
            $0.expression.localizedCaseInsensitiveContains(q)
                || $0.result.localizedCaseInsensitiveContains(q)
        }
        searchCache = (q, result)
        return result
    }

    private func persist() {
        searchCache = nil
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
