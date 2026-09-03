import Foundation

/// Every name a bundle carries on disk, re-read only when its modification date moves.
/// A scan runs on every palette open, so caching Spotlight's ~0.8 ms and not the loctable's
/// ~0.2 ms would leave most of a warm pass uncached.
struct BundleNameCache: Sendable {
    /// Preferred-language names first; `scan` takes the first as the display name.
    struct Names: Sendable {
        let localized: [String]
        let alternates: [String]
    }

    private struct Entry: Sendable {
        let modified: Date?
        let names: Names
    }

    private let languages: [String]
    private let previous: [String: Entry]
    private var current: [String: Entry] = [:]

    init() {
        languages = []
        previous = [:]
    }

    /// Only bundles this pass asks about carry forward, so uninstalled apps fall out.
    /// A changed system language drops the table whole: every name in it is in the old one.
    init(reusing cache: BundleNameCache, languages: [String]) {
        self.languages = languages
        previous = cache.languages == languages ? cache.current : [:]
    }

    mutating func names(for url: URL) -> Names {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let cached = previous[url.path], cached.modified == modified {
            current[url.path] = cached
            return cached.names
        }
        let names = Names(
            localized: BundleLocalization.names(for: url, languages: languages),
            alternates: SpotlightNames.alternateNames(for: url))
        current[url.path] = Entry(modified: modified, names: names)
        return names
    }
}
