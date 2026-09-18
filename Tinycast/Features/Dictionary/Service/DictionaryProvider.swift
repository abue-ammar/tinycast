import CoreServices
import Foundation

/// Reads the dictionaries enabled in Dictionary.app; local only, so a lookup never leaves the Mac.
@MainActor
enum DictionaryProvider {
    private struct Cache {
        let term: String
        let entry: DictionaryEntry?
    }

    /// One deep, because the palette rebuilds its screen on every redraw, not only on a keystroke.
    private static var cache: Cache?

    static func entry(for term: String) -> DictionaryEntry? {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        if let cache, cache.term == term { return cache.entry }
        let entry = definition(of: term).map { DictionaryEntry(term: term, text: $0) }
        cache = Cache(term: term, entry: entry)
        return entry
    }

    private static func definition(of term: String) -> String? {
        let range = CFRange(location: 0, length: term.utf16.count)
        guard let text = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue()
        else { return nil }
        let trimmed = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
