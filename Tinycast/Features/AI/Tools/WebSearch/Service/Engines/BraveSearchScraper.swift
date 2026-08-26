import Foundation

public enum BraveSearchScraper {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://search.brave.com/search?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let html = String(decoding: data, as: UTF8.self)
        return parse(html: html)
    }

    public static func parse(html: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let pattern = #"<div\s+[^>]*class="[^"]*snippet[^"]*"[^>]*data-type="web"[^>]*>.*?<a\s+[^>]*href="([^"]+)"[^>]*>.*?<span[^>]*class="[^"]*title[^"]*"[^>]*>(.*?)<\/span>.*?<\/a>.*?<div\s+[^>]*class="[^"]*snippet-description[^"]*"[^>]*>(.*?)<\/div>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        var rank = 1

        for match in matches.prefix(10) {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let descRange = Range(match.range(at: 3), in: html) else { continue }

            let rawURL = String(html[urlRange])
            let rawTitle = String(html[titleRange])
            let rawDesc = String(html[descRange])

            guard let targetURL = URL(string: rawURL) else { continue }
            let cleanTitle = HTMLToMarkdownConverter.decodeHTMLEntities(rawTitle.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
            let cleanSnippet = HTMLToMarkdownConverter.decodeHTMLEntities(rawDesc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))

            results.append(
                WebSearchResult(
                    title: cleanTitle,
                    url: targetURL,
                    snippet: cleanSnippet,
                    engine: .brave,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}
