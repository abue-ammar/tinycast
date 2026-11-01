import Foundation

/// A built-in `tinycast://` link; extension links never parse as one. See docs/features/deeplinks.md.
enum DeepLink: Equatable, Sendable {
    case launcher(fallbackText: String?)
    /// `<kind>/<id>` for the launcher row `<kind>:<id>`, run as its shortcut would be.
    case entry(HotKeyAction, DeepLinkInput)
    case settings(slug: String)

    /// Extension links own this host, so built-in parsing must never claim it.
    static let extensionsHost = "extensions"

    init?(url: URL, scheme: String) {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let input = DeepLinkInput(queryItems: items) else { return nil }
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let path = String(url.path(percentEncoded: false).dropFirst())
        switch host {
        case "", "search":
            guard path.isEmpty else { return nil }
            self = .launcher(fallbackText: input.fallbackText)
        case "settings":
            guard !path.isEmpty, !path.contains("/") else { return nil }
            self = .settings(slug: path.lowercased())
        case Self.extensionsHost:
            return nil
        default:
            guard !path.isEmpty, let action = HotKeyAction(entryID: host + ":" + path) else {
                return nil
            }
            self = .entry(action, input)
        }
    }

    /// Nil for a row no link can run, so a copied link always resolves.
    static func url(forEntryID entryID: String, scheme: String) -> URL? {
        guard HotKeyAction(entryID: entryID) != nil,
            let colon = entryID.firstIndex(of: ":")
        else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = String(entryID[..<colon])
        components.path = "/" + entryID[entryID.index(after: colon)...]
        return components.url
    }
}
