import Foundation

/// Maps Alfred's bookmarks, custom searches and default web searches onto `Quicklink`.
/// See docs/features/alfred-import.md.
enum AlfredQuicklinkImport {
    /// Only `remote.alfred.openurl` becomes a quicklink; Alfred's other page items open files,
    /// run system commands or drive iTunes, none of which a link is.
    static func bookmarks(inPages pages: [[String: Any]]) -> [Quicklink] {
        pages.flatMap { page in
            (page["items"] as? [[String: Any]] ?? []).compactMap { item in
                guard item["actionuid"] as? String == "remote.alfred.openurl",
                    let config = item["actionconfig"] as? [String: Any],
                    let url = trimmed(config["url"])
                else { return nil }
                return quicklink(
                    name: trimmed(item["buttonlabel"]) ?? host(of: url), keyword: nil, link: url)
            }
        }
    }

    /// One `customSites` row. A disabled search is not carried over, matching Alfred itself.
    static func search(title: String, keyword: String?, url: String) -> Quicklink? {
        quicklink(name: title, keyword: keyword, link: url)
    }

    /// One of Alfred's own searches: the package stores its keyword but not its URL.
    static func defaultSearch(folder: String, keyword: String?) -> Quicklink? {
        guard let template = defaultSearches[folder], let keyword, !keyword.isEmpty else {
            return nil
        }
        return search(title: template.title, keyword: keyword, url: template.url)
    }

    /// Alfred's built-in searches, by the folder name its preferences use. A folder missing here
    /// is reported rather than guessed at, since the URL only exists inside Alfred.
    static let defaultSearches: [String: (title: String, url: String)] = [
        "amazon": ("Amazon", "https://www.amazon.com/s?k={query}"),
        "applemaps": ("Apple Maps", "https://maps.apple.com/?q={query}"),
        "bing": ("Bing", "https://www.bing.com/search?q={query}"),
        "duckduckgo": ("DuckDuckGo", "https://duckduckgo.com/?q={query}"),
        "ebay": ("eBay", "https://www.ebay.com/sch/i.html?_nkw={query}"),
        "facebook": ("Facebook", "https://www.facebook.com/search/top?q={query}"),
        "flickr": ("Flickr", "https://www.flickr.com/search/?text={query}"),
        "google": ("Google", "https://www.google.com/search?q={query}"),
        "googledrive": ("Google Drive", "https://drive.google.com/drive/u/0/my-drive?q={query}"),
        "gmail": ("Gmail", "https://mail.google.com/mail/u/0/#search/{query}"),
        "images": ("Google Images", "https://www.google.com/search?q={query}&tbm=isch"),
        "imdb": ("IMDb", "https://www.imdb.com/find?q={query}"),
        "linkedin": ("LinkedIn", "https://www.linkedin.com/search/results/all/?keywords={query}"),
        "lucky": ("I'm Feeling Lucky", "https://www.google.com/search?q={query}&btnI=1"),
        "maps": ("Google Maps", "https://www.google.com/maps/search/{query}"),
        "pinterest": ("Pinterest", "https://www.pinterest.com/search/pins/?q={query}"),
        "reddit": ("Reddit", "https://www.reddit.com/search?q={query}"),
        "stackoverflow": (
            "Stack Overflow", "https://stackoverflow.com/search?q={query}"
        ),
        "twitter": ("Twitter", "https://twitter.com/search?q={query}"),
        "translate": (
            "Google Translate",
            "https://translate.google.com/?sl=auto&tl=en&text={query}&op=translate"
        ),
        "weather": (
            "Weather Underground", "https://www.wunderground.com/weather/search/{query}"
        ),
        "wiki": ("Wikipedia", "https://en.wikipedia.org/w/index.php?search={query}"),
        "wolfram": ("Wolfram Alpha", "https://www.wolframalpha.com/input?i={query}"),
        "yahoo": ("Yahoo", "https://search.yahoo.com/search?p={query}"),
        "youtube": ("YouTube", "https://www.youtube.com/results?search_query={query}"),
        "yubnub": ("Yubnub", "https://yubnub.com/search?q={query}")
    ]

    private static func quicklink(name: String?, keyword: String?, link: String) -> Quicklink? {
        guard let name, !name.isEmpty else { return nil }
        let rewritten = Quicklink.replacingArgumentTokens(link)
        guard !rewritten.isEmpty else { return nil }
        return Quicklink(name: name, keyword: keyword, link: rewritten)
    }

    /// Alfred leaves a bookmark's label empty for a plain URL, so the host names the row.
    private static func host(of url: String) -> String? {
        guard let components = URLComponents(string: url), let host = components.host else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
