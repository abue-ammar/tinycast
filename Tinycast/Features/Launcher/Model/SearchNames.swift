import Foundation

/// Name providers: raw name in, extra names a user might type out, no other state. A new naming
/// criterion is a function here plus one line at its call site, and no change to `SearchRelevance`.
enum SearchNames {
    static func strippingAppExtension(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Drops the leading reverse-DNS component, which prefixes nearly every installed app.
    static func identifyingPart(of bundleID: String) -> String {
        guard let dot = bundleID.firstIndex(of: ".") else { return bundleID }
        return String(bundleID[bundleID.index(after: dot)...])
    }

    /// Spotlight mixes junk in with the real aliases; indexing it makes `app` match all.
    static func usableAlternates(
        _ raw: [String], displayName: String, fileName: String
    ) -> [String] {
        let rejected = Set([displayName, fileName].map(strippingAppExtension).map { $0.lowercased() })
        var seen = Set<String>()
        return raw.compactMap { candidate in
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !isPlaceholder(name) else { return nil }
            let key = strippingAppExtension(name).lowercased()
            guard !key.isEmpty, !rejected.contains(key), seen.insert(key).inserted else { return nil }
            return name
        }
    }

    /// A lone SCREAMING_SNAKE token is an untranslated placeholder, and several ship.
    private static func isPlaceholder(_ name: String) -> Bool {
        name.contains("_") && !name.contains(where: { $0.isLowercase || $0.isWhitespace })
    }

    /// What a non-Latin name gets typed as: `微信` as "weixin" and "wx". Heuristic on purpose — ICU
    /// reads Han as Mandarin, and a stray fuzzy alias costs far less than an unfindable app.
    static func romanizations(of name: String) -> [String] {
        guard name.unicodeScalars.contains(where: { $0.value > 0x7F }) else { return [] }
        guard
            let latin = name.applyingTransform(.toLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false)?
                .lowercased()
        else { return [] }
        let words = latin.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let joined = words.joined()
        guard !joined.isEmpty, joined.caseInsensitiveCompare(name) != .orderedSame else { return [] }
        guard words.count > 1 else { return [joined] }
        // A Chinese user types the pinyin initials far more often than the full reading.
        return [joined, String(words.compactMap(\.first))]
    }
}
