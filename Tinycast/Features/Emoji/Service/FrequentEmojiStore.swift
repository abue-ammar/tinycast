import Foundation

/// One emoji's usage tally, keyed on the base (untoned) glyph.
struct FrequentEmoji: Codable, Hashable, Sendable {
    let glyph: String
    var count: Int
    var lastUsed: Date
}

/// Usage counts as a capped JSON file in Caches, feeding the grid's "Frequently Used".
@MainActor
@Observable
final class FrequentEmojiStore {
    private static let cap = 300

    private let fileURL: URL

    private(set) var records: [FrequentEmoji]

    /// The empty-query grid re-reads `top()` every render, so this sorts once per tally.
    @ObservationIgnored private var sortedMemo = Memo<Int, [String]>()
    private var revision = 0

    init() {
        fileURL = AppPaths.caches().appendingPathComponent("emoji-frequency.json")

        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([FrequentEmoji].self, from: data)
        {
            records = decoded
        } else {
            records = []
        }
    }

    func record(_ glyph: String) {
        revision &+= 1
        if let index = records.firstIndex(where: { $0.glyph == glyph }) {
            records[index].count += 1
            records[index].lastUsed = Date()
        } else {
            records.append(FrequentEmoji(glyph: glyph, count: 1, lastUsed: Date()))
        }
        if records.count > Self.cap {
            // Evict the least-used, oldest tallies so the file stays bounded.
            records.sort { $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed }
            records.removeLast(records.count - Self.cap)
        }
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

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
