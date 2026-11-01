import Foundation

/// A built-in `tinycast://` link; an extension link never parses as one. See deeplinks.md.
enum DeepLink: Equatable, Sendable {
    case launcher(fallbackText: String?)
    /// `<kind>/<id>` for the launcher row `<kind>:<id>`, run as its shortcut would be.
    case entry(HotKeyAction, DeepLinkInput)
    case settings(slug: String)
    /// A note by its file name, which is all a note is known by.
    case note(name: String)
    case chat(id: UUID)
    case windowSize(CustomWindowSize)

    /// Extension links own this host, so built-in parsing must never claim it.
    static let extensionsHost = "extensions"
    static let searchHost = "search"
    static let windowSizeHost = "window-size"
    private static let noteHost = "note"
    private static let chatHost = "chat"

    init?(url: URL, scheme: String) {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let input = DeepLinkInput(queryItems: items),
            let link = Self.link(
                host: url.host(percentEncoded: false)?.lowercased() ?? "",
                path: String(url.path(percentEncoded: false).dropFirst()), input: input)
        else { return nil }
        self = link
    }

    /// Nil for a row no link can run, so a copied link always resolves.
    static func url(forEntryID entryID: String, scheme: String, input: DeepLinkInput = .none) -> URL? {
        guard HotKeyAction(entryID: entryID) != nil,
            let colon = entryID.firstIndex(of: ":")
        else { return nil }
        return url(
            scheme: scheme, host: String(entryID[..<colon]),
            path: String(entryID[entryID.index(after: colon)...]), input: input)
    }

    static func url(forNote name: String, scheme: String) -> URL? {
        url(scheme: scheme, host: noteHost, path: name, input: .none)
    }

    static func url(forChat id: UUID, scheme: String) -> URL? {
        url(scheme: scheme, host: chatHost, path: id.uuidString.lowercased(), input: .none)
    }

    private static func url(scheme: String, host: String, path: String, input: DeepLinkInput) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + path
        let items = input.percentEncodedQueryItems
        if !items.isEmpty { components.percentEncodedQueryItems = items }
        return components.url
    }

    private static func link(host: String, path: String, input: DeepLinkInput) -> DeepLink? {
        switch (host, path.isEmpty) {
        case ("", true), (searchHost, true):
            return .launcher(fallbackText: input.fallbackText)
        case ("settings", false):
            return path.contains("/") ? nil : .settings(slug: path.lowercased())
        case (noteHost, false):
            return path.contains("/") ? nil : .note(name: path)
        case (chatHost, false):
            return UUID(uuidString: path).map { .chat(id: $0) }
        case (windowSizeHost, true):
            guard case .named(let fields)? = input.arguments else { return nil }
            return CustomWindowSize(linkFields: fields).map { .windowSize($0) }
        case (extensionsHost, _), (_, true):
            return nil
        default:
            return HotKeyAction(entryID: host + ":" + path).map { .entry($0, input) }
        }
    }
}
