import CoreServices
import Foundation

/// The aliases macOS knows an app by, which no Info.plist key exposes.
enum SpotlightNames {
    /// `MDItem.h` exports no constant for either key, so both are named directly.
    private static let alternatesAttribute = "kMDItemAlternateNames"
    private static let localizedNameAttribute = "kMDItemDisplayName"

    /// Empty when the path isn't indexed; Spotlight off is a thinner index, not a failure.
    nonisolated static func alternateNames(for url: URL) -> [String] {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return [] }
        let alternates = MDItemCopyAttribute(item, alternatesAttribute as CFString) as? [String] ?? []
        // Apple's system apps translate only in `InfoPlist.loctable`, which `CFBundle` can't read.
        let localized = (MDItemCopyAttribute(item, localizedNameAttribute as CFString) as? String)
            .map(EntryNaming.strippingAppExtension)
        // Rejecting nothing: `EntryNaming.aliases` drops whatever repeats the entry's own names.
        return EntryNaming.usable(alternates + [localized].compactMap { $0 }, rejecting: [])
    }
}
