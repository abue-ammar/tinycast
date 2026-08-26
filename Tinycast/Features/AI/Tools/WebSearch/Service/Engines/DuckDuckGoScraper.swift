import Foundation

public enum DuckDuckGoScraper {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "q=\(encoded)&b=".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let html = String(decoding: data, as: UTF8.self)
        return parse(html: html)
    }

    public static func parse(html: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let resultPattern = #"<a\s+[^>]*class="[^"]*result__snippet[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>"#

        // Extract using regex
        guard let snippetRegex = try? NSRegularExpression(pattern: resultPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = snippetRegex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        var rank = 1

        for match in matches.prefix(10) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let snippetRange = Range(match.range(at: 2), in: html) else { continue }

            let rawHref = String(html[hrefRange])
            let rawSnippet = String(html[snippetRange])

            guard let targetURL = URLRedirectDecoder.decode(rawHref) else { continue }
            let cleanSnippet = HTMLToMarkdownConverter.decodeHTMLEntities(rawSnippet).trimmingCharacters(in: .whitespacesAndNewlines)
            let hostTitle = targetURL.host ?? targetURL.absoluteString

            results.append(
                WebSearchResult(
                    title: hostTitle,
                    url: targetURL,
                    snippet: cleanSnippet,
                    engine: .duckDuckGo,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}
