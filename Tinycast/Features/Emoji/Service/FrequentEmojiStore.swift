import Foundation

/// One emoji's usage tally, keyed on the base (untoned) glyph.
struct FrequentEmoji: Codable, Hashable, Sendable {
    let glyph: String
    var count: Int
    var lastUsed: Date
}

/// Capped emoji history and usage counts, persisted together for the grid and search.
@MainActor
@Observable
final class FrequentEmojiStore {
    private static let cap = 300

    private let fileURL: URL

    private(set) var records: [FrequentEmoji]

    /// Search re-reads `top()` across queries, so this sorts once per tally.
    @ObservationIgnored private var sortedMemo = Memo<Int, [String]>()
    private(set) var revision = 0

    init(fileURL: URL = AppPaths.applicationSupport().appendingPathComponent("emoji-frequency.json")) {
        self.fileURL = fileURL

        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([FrequentEmoji].self, from: data)
        {
            records = Self.history(decoded)
        } else {
            records = []
        }
    }

    func record(_ glyph: String) {
        revision &+= 1
        if let index = records.firstIndex(where: { $0.glyph == glyph }) {
            var entry = records.remove(at: index)
            entry.count += 1
            entry.lastUsed = Date()
            records.insert(entry, at: 0)
        } else {
            records.insert(FrequentEmoji(glyph: glyph, count: 1, lastUsed: Date()), at: 0)
        }
        if records.count > Self.cap {
            records.removeLast(records.count - Self.cap)
        }
        persist()
    }

    func replace(_ imported: [FrequentEmoji]) {
        revision &+= 1
        records = Self.history(imported)
        persist()
    }

    /// Most-used glyphs (recency breaks ties), newest habits first.
    func top(_ n: Int = 16) -> [String] {
        let sorted = sortedMemo.value(for: revision) {
            records
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed }
                .map(\.glyph)
        }
        return Array(sorted.prefix(n))
    }

    /// A backup can repeat a glyph; only its newest tally is kept, so each takes one grid cell.
    private static func history(_ tallies: [FrequentEmoji]) -> [FrequentEmoji] {
        var seen = Set<String>()
        return Array(
            tallies
                .filter { !$0.glyph.isEmpty && $0.count > 0 }
                .sorted { $0.lastUsed > $1.lastUsed }
                .filter { seen.insert($0.glyph).inserted }
                .prefix(cap))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
