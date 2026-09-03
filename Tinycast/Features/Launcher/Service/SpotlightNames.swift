import CoreServices
import Foundation

/// The aliases macOS knows an app by, which no Info.plist key exposes.
enum SpotlightNames {
    /// `MDItem.h` exports no constant for either key, so both are named directly.
    private static let alternatesAttribute = "kMDItemAlternateNames"
    private static let localizedNameAttribute = "kMDItemDisplayName"

    /// Empty when the path isn't indexed; Spotlight off is a thinner index, not a failure.
    nonisolated static func alternateNames(for url: URL, displayName: String) -> [String] {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return [] }
        let alternates = MDItemCopyAttribute(item, alternatesAttribute as CFString) as? [String] ?? []
        // Apple's system apps translate only in `InfoPlist.loctable`, which `CFBundle` can't read.
        let localized = (MDItemCopyAttribute(item, localizedNameAttribute as CFString) as? String)
            .map(SearchNames.strippingAppExtension)
        return SearchNames.usableAlternates(
            alternates + [localized].compactMap { $0 },
            displayName: displayName, fileName: url.lastPathComponent)
    }

    /// ~0.8 ms per bundle, so a pass re-reads only bundles whose modification date moved.
    struct Cache: Sendable {
        private struct Entry: Sendable {
            let modified: Date?
            let names: [String]
        }

        private let previous: [String: Entry]
        private var current: [String: Entry] = [:]

        init() { previous = [:] }

        /// Only bundles this pass asks about carry forward, so uninstalled apps fall out.
        init(reusing cache: Cache) { previous = cache.current }

        mutating func alternateNames(for url: URL, displayName: String) -> [String] {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let cached = previous[url.path], cached.modified == modified {
                current[url.path] = cached
                return cached.names
            }
            let names = SpotlightNames.alternateNames(for: url, displayName: displayName)
            current[url.path] = Entry(modified: modified, names: names)
            return names
        }
    }
}
