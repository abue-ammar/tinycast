import Foundation

/// A bundle's names in the languages this Mac reads; `CFBundle` alone misses every loctable app.
enum BundleLocalization {
    /// Preferred languages first, English last: a user who reads Thai still types "Calendar".
    nonisolated static func indexedLanguages(_ preferred: [String]) -> [String] {
        var codes: [String] = []
        var seen = Set<String>()
        for tag in preferred + ["en"] {
            // loctable keys and .lproj folders both use underscores where a language tag uses "-".
            let underscored = tag.replacingOccurrences(of: "-", with: "_")
            let bare = tag.split(separator: "-").first.map(String.init) ?? tag
            for code in [tag, underscored, bare] where !code.isEmpty && seen.insert(code).inserted {
                codes.append(code)
            }
        }
        return codes
    }

    /// Every localized name the bundle carries, most preferred language first.
    nonisolated static func names(for bundleURL: URL, languages: [String]) -> [String] {
        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let table = plist(at: resources.appendingPathComponent("InfoPlist.loctable"))
        var result: [String] = []
        var seen = Set<String>()
        for code in languages {
            let strings = plist(
                at: resources.appendingPathComponent("\(code).lproj/InfoPlist.strings"))
            for source in [table?[code] as? [String: Any], strings] {
                guard let source, let name = AppDisplayName.inInfo(source),
                    seen.insert(FuzzyMatch.normalized(name)).inserted
                else { continue }
                result.append(name)
            }
        }
        return result
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any]
    }
}
