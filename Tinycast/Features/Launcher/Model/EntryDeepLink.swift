import Foundation

/// `tinycast://<kind>/<id>` for the launcher row `<kind>:<id>`, run as its shortcut would be.
enum EntryDeepLink {
    static let scheme = "tinycast"

    /// Nil for a row no link can run, so a copied link always resolves.
    static func url(forEntryID entryID: String) -> URL? {
        guard HotKeyAction(entryID: entryID) != nil,
            let colon = entryID.firstIndex(of: ":")
        else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = String(entryID[..<colon])
        components.path = "/" + entryID[entryID.index(after: colon)...]
        return components.url
    }

    static func action(for url: URL) -> HotKeyAction? {
        guard url.scheme?.lowercased() == scheme,
            let kind = url.host(percentEncoded: false), !kind.isEmpty
        else { return nil }
        let path = url.path(percentEncoded: false)
        guard path.count > 1 else { return nil }
        return HotKeyAction(entryID: kind.lowercased() + ":" + path.dropFirst())
    }
}
