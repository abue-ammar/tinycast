import Foundation

/// One TypeSafe request that ranks the catalog by meaning. Choice allows 255 options, so the
/// catalog is split and each shard is its own question in that same call.
enum JevEmojiRanking {
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let model = "jev-latest"
    static let none = "none"
    /// Room left for the `none` option under Choice's 255-option cap.
    static let shardSize = 200
    static let minimumQueryLength = 3
    static let maxHits = 24
    /// Below this, a shard's probability is noise next to `none`.
    static let minimumProbability = 0.08

    static func requestBody(query: String, entries: [EmojiEntry]) -> Data? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shards = shards(from: entries)
        guard trimmed.count >= minimumQueryLength, !shards.isEmpty else { return nil }
        var questions: [String: Any] = [:]
        for (index, shard) in shards.enumerated() {
            var criteria: [String: String] = [
                none: "No emoji in this list is one a person would insert for the query"
            ]
            for entry in shard {
                criteria[entry.glyph] = entry.name
            }
            questions["s\(index)"] = [
                "type": "choice",
                "instructions": [
                    "question":
                        "Which emoji would a person insert to express `query`? "
                        + "Treat a misspelling as the intended word. "
                        + "Choose none when no emoji in this list fits."
                ],
                "criteria": criteria
            ]
        }
        let payload: [String: Any] = [
            "model": model,
            "state": ["query": trimmed],
            "questions": questions
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    /// Glyphs a person would actually pick, strongest probability first.
    static func glyphs(in response: Data, catalog: [EmojiEntry]) -> [String] {
        let known = Set(catalog.map(\.glyph))
        guard
            let root = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
            let answers = root["answers"] as? [String: Any]
        else { return [] }
        var scored: [(glyph: String, probability: Double)] = []
        for answer in answers.values {
            guard
                let object = answer as? [String: Any],
                object["type"] as? String == "choice",
                let probabilities = object["probabilities"] as? [String: Any]
            else { continue }
            let noneProbability = number(probabilities[none])
            for (key, value) in probabilities where key != none && known.contains(key) {
                let probability = number(value)
                guard probability >= minimumProbability, probability > noneProbability else {
                    continue
                }
                scored.append((key, probability))
            }
        }
        var seen: Set<String> = []
        return
            scored
            .sorted { $0.probability > $1.probability }
            .compactMap { seen.insert($0.glyph).inserted ? $0.glyph : nil }
            .prefix(maxHits)
            .map { $0 }
    }

    private static func shards(from entries: [EmojiEntry]) -> [[EmojiEntry]] {
        guard shardSize > 0 else { return [] }
        var shards: [[EmojiEntry]] = []
        var index = entries.startIndex
        while index < entries.endIndex {
            let end = entries.index(index, offsetBy: shardSize, limitedBy: entries.endIndex)
                ?? entries.endIndex
            shards.append(Array(entries[index..<end]))
            index = end
        }
        return shards
    }

    private static func number(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }
}
