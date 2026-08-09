import Foundation

/// One past calculation, recorded when the user copies an answer.
struct CalcHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let expression: String
    let result: String
    let createdAt: Date
}

/// A capped JSON file in Caches, beside `ClipboardStore` so `brew uninstall --zap` gets it too.
@MainActor
@Observable
final class CalculatorHistoryStore {
    private static let cap = 200

    private let fileURL: URL

    private(set) var entries: [CalcHistoryEntry]  // newest first

    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
    }

    /// Repeated renders (arrow-key nav) reuse the filter instead of re-scanning every entry.
    @ObservationIgnored private var searchMemo = Memo<SearchKey, [CalcHistoryEntry]>()
    /// Bumped on every persisted mutation, so the key above names the entries it filtered.
    private var revision = 0

    init() {
        fileURL = AppPaths.caches().appendingPathComponent("calculator-history.json")

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
        return searchMemo.value(for: SearchKey(query: q, revision: revision)) {
            entries.filter {
                $0.expression.localizedCaseInsensitiveContains(q)
                    || $0.result.localizedCaseInsensitiveContains(q)
            }
        }
    }

    private func persist() {
        revision &+= 1
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
