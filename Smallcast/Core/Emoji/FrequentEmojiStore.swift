import Foundation

/// One emoji's usage tally, keyed on the base (untoned) glyph.
struct FrequentEmoji: Codable, Hashable, Sendable {
    let glyph: String
    var count: Int
    var lastUsed: Date
}

/// Persists emoji usage counts as a capped JSON file under `~/Library/Caches/<bundle-id>/`, feeding the grid's "Frequently Used" section.
@MainActor
final class FrequentEmojiStore: ObservableObject {
    private static let cap = 300

    private let fileURL: URL

    @Published private(set) var records: [FrequentEmoji]

    /// Cached glyphs in ranked order so the empty-query grid (which re-reads `top()` every render, incl. arrow-key nav) doesn't re-sort all records each frame; invalidated on `record()`.
    private var sortedGlyphs: [String]?

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.smallcast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("emoji-frequency.json")

        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([FrequentEmoji].self, from: data)
        {
            records = decoded
        } else {
            records = []
        }
    }

    func record(_ glyph: String) {
        sortedGlyphs = nil
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
        let sorted = sortedGlyphs ?? {
            let ranked = records
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed }
                .map(\.glyph)
            sortedGlyphs = ranked
            return ranked
        }()
        return Array(sorted.prefix(n))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
