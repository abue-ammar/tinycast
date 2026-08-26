import Foundation

public enum URLNormalizer {
    private static let trackingParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "ref", "source", "spm", "_hsenc", "_hsmi",
        "mc_cid", "mc_eid", "yclid", "_openstat"
    ]

    /// Returns a clean canonical URL without tracking parameters or fragments.
    public static func normalize(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        // Strip tracking query parameters
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { !trackingParameters.contains($0.name.lowercased()) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        // Normalize host (strip www.)
        if let host = components.host?.lowercased() {
            if host.hasPrefix("www.") {
                components.host = String(host.dropFirst(4))
            } else {
                components.host = host
            }
        }

        // Strip fragment (#...)
        components.fragment = nil

        // Strip trailing slash on path
        if components.path == "/" {
            components.path = ""
        } else if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        return components.url ?? url
    }

    /// String key for deduplicating URLs.
    public static func deduplicationKey(for url: URL) -> String {
        normalize(url).absoluteString.lowercased()
    }
}
