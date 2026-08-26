import Foundation

public enum URLRedirectDecoder {
    /// Unwrap tracking and proxy redirects (DuckDuckGo uddg=, AOL/Yahoo RU=)
    public static func decode(_ rawURLString: String) -> URL? {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }

        // 1. DuckDuckGo: //duckduckgo.com/l/?uddg=<encoded_url>
        if url.host?.contains("duckduckgo.com") == true || trimmed.contains("/l/?uddg=") {
            if let components = URLComponents(string: trimmed),
               let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
                if let decoded = uddg.removingPercentEncoding, let target = URL(string: decoded) {
                    return target
                }
            }
        }

        // 2. AOL / Yahoo: .../RU=<encoded_url>/RK=...
        if trimmed.contains("/RU=") {
            let pattern = #"/RU=([^/]+)/RK="#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                let encodedTarget = String(trimmed[range])
                if let decoded = encodedTarget.removingPercentEncoding, let target = URL(string: decoded) {
                    return target
                }
            }
        }

        // 3. Protocol relative URL: //example.com -> https://example.com
        if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        }

        return url
    }
}
