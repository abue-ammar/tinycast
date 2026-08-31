import Foundation

/// A meeting's join link and the service behind it, read out of the event's own text.
struct MeetingLink: Hashable, Sendable {
    let provider: Provider
    let url: URL
    /// The account whose calendar carried this link, for a provider that preselects it.
    let account: String?

    /// The desktop app's own URL, where one can be formed without guessing. Nil means open the web.
    var appURL: URL? { provider.appURL(for: url) }

    /// The link as written, naming the account where the provider takes one.
    var webURL: URL { provider.accountURL(for: url, account: account) ?? url }

    /// Fields in precedence order; a named provider anywhere beats a bare link found earlier.
    static func detect(fields: [String?], account: String? = nil) -> MeetingLink? {
        var fallback: MeetingLink?
        for field in fields.compactMap({ $0 }) {
            for url in webURLs(in: field) {
                guard let provider = classify(url) else { continue }
                let link = MeetingLink(provider: provider, url: url, account: account)
                if provider != .generic { return link }
                if fallback == nil { fallback = link }
            }
        }
        return fallback
    }

    static func detect(in text: String) -> MeetingLink? {
        detect(fields: [text])
    }

    /// A known host failing its path rule is rejected, never demoted to `.generic`.
    private static func classify(_ url: URL) -> Provider? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host()?.lowercased()
        else { return nil }
        guard let provider = Provider(host: host) else { return .generic }
        return provider.admits(path: url.path()) ? provider : nil
    }

    private static let terminators: Set<Character> = [
        " ", "\t", "\n", "\r", "\"", "'", "<", ">", "«", "»", "\u{00A0}"
    ]
    private static let trailingNoise: Set<Character> = [".", ",", ";", ":", ")", "]", "}", "!", "?"]

    /// Hand-rolled: `NSDataDetector` is not `Sendable` and costs more than the scan.
    private static func webURLs(in text: String) -> [URL] {
        var found: [URL] = []
        var cursor = text.startIndex
        while cursor < text.endIndex,
            let start = text.range(
                of: "http", options: .caseInsensitive, range: cursor..<text.endIndex)?.lowerBound
        {
            let end = text[start...].firstIndex(where: terminators.contains) ?? text.endIndex
            var candidate = text[start..<end]
            while let last = candidate.last, trailingNoise.contains(last) {
                candidate = candidate.dropLast()
            }
            let lowered = candidate.lowercased()
            if lowered.hasPrefix("http://") || lowered.hasPrefix("https://"),
                let url = URL(string: String(candidate))
            {
                found.append(url)
            }
            cursor = end > start ? end : text.index(after: start)
        }
        return found
    }
}

extension MeetingLink {
    enum Provider: String, CaseIterable, Sendable {
        case zoom
        case googleMeet
        case teams
        case webex
        case jitsi
        case whereby
        case chime
        case gotoMeeting
        case blueJeans
        case skype
        /// Any other http(s) link the event carries — joinable, just not identifiable.
        case generic

        var title: String {
            switch self {
            case .zoom: return "Zoom"
            case .googleMeet: return "Google Meet"
            case .teams: return "Microsoft Teams"
            case .webex: return "Webex"
            case .jitsi: return "Jitsi"
            case .whereby: return "Whereby"
            case .chime: return "Amazon Chime"
            case .gotoMeeting: return "GoTo Meeting"
            case .blueJeans: return "BlueJeans"
            case .skype: return "Skype"
            case .generic: return "Meeting Link"
            }
        }

        /// No brand artwork ships, so the glyph says only what kind of thing this is.
        var sfSymbol: String { self == .generic ? "link" : "video.fill" }

        /// Host suffixes, matched whole or as a subdomain. Disjoint by construction.
        private static let hostSuffixes: [Provider: [String]] = [
            .zoom: ["zoom.us", "zoom.com", "zoomgov.com"],
            .googleMeet: ["meet.google.com"],
            .teams: ["teams.microsoft.com", "teams.microsoft.us", "teams.live.com"],
            .webex: ["webex.com", "webex.com.cn"],
            .jitsi: ["meet.jit.si", "8x8.vc"],
            .whereby: ["whereby.com"],
            .chime: ["chime.aws"],
            .gotoMeeting: ["gotomeeting.com", "gotomeet.me", "app.goto.com"],
            .blueJeans: ["bluejeans.com"],
            .skype: ["join.skype.com"]
        ]

        init?(host: String) {
            let match = Self.hostSuffixes.first { _, suffixes in
                suffixes.contains { host == $0 || host.hasSuffix("." + $0) }
            }
            guard let match else { return nil }
            self = match.key
        }

        /// Whether the path shape is a meeting rather than a download page or a dial-in helper.
        func admits(path: String) -> Bool {
            let segments = path.split(separator: "/").map { $0.lowercased() }
            switch self {
            case .zoom:
                return segments.contains { ["j", "w", "s", "my"].contains($0) }
            case .googleMeet:
                return segments.count == 1 && segments[0] != "tel"
            case .teams:
                return segments.contains("meetup-join") || segments.contains("meet")
            case .webex, .jitsi, .whereby, .chime, .gotoMeeting, .blueJeans, .skype, .generic:
                return !segments.isEmpty
            }
        }

        private static let accountQuery = "authuser"
        /// Meet's own links keep `@` readable; `+` cannot stay, as a server may read it as a space.
        private static let accountAllowed = CharacterSet.urlQueryAllowed.subtracting(
            CharacterSet(charactersIn: "+&="))

        /// Only Google Meet takes an account; `authuser` picks between signed-in identities.
        func accountURL(for url: URL, account: String?) -> URL? {
            guard self == .googleMeet, let account,
                let encoded = account.addingPercentEncoding(withAllowedCharacters: Self.accountAllowed),
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return nil }
            let items = components.percentEncodedQueryItems ?? []
            // A link naming its own account was written deliberately, and outranks the calendar's.
            guard !items.contains(where: { $0.name == Self.accountQuery }) else { return nil }
            components.percentEncodedQueryItems =
                items + [URLQueryItem(name: Self.accountQuery, value: encoded)]
            return components.url
        }

        /// Only the two rewrites Apple's handlers make unambiguous; anything else opens the web.
        func appURL(for url: URL) -> URL? {
            switch self {
            case .zoom: return zoomAppURL(for: url)
            case .teams: return teamsAppURL(for: url)
            default: return nil
            }
        }

        private func zoomAppURL(for url: URL) -> URL? {
            let segments = url.path().split(separator: "/")
            guard let marker = segments.firstIndex(where: { ["j", "w", "s"].contains($0.lowercased()) }),
                let conference = segments.dropFirst(marker + 1).first
            else { return nil }
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = "zoom.us"
            components.path = "/join"
            var query = [URLQueryItem(name: "confno", value: String(conference))]
            if let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pwd" })?.value
            {
                query.append(URLQueryItem(name: "pwd", value: password))
            }
            components.queryItems = query
            return components.url
        }

        private func teamsAppURL(for url: URL) -> URL? {
            guard url.host()?.lowercased().hasSuffix("teams.microsoft.com") == true else { return nil }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
            return URL(string: "msteams:" + url.path() + (query.map { "?" + $0 } ?? ""))
        }
    }
}
