import Foundation

public enum NewsRSSEngine {
    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=en-US&gl=US&ceid=US:en") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Tinycast-News/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return parse(xml: xml)
    }

    public static func parse(xml: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let itemPattern = #"<item>.*?<title>(.*?)<\/title>.*?<link>(.*?)<\/link>.*?(?:<pubDate>(.*?)<\/pubDate>)?.*?(?:<description>(.*?)<\/description>)?.*?<\/item>"#

        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
        var rank = 1

        for match in matches.prefix(8) {
            guard let titleRange = Range(match.range(at: 1), in: xml),
                  let linkRange = Range(match.range(at: 2), in: xml) else { continue }

            let rawTitle = String(xml[titleRange])
            let rawLink = String(xml[linkRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let url = URL(string: rawLink) else { continue }

            var snippet = ""
            if match.numberOfRanges > 4, let descRange = Range(match.range(at: 4), in: xml) {
                let rawDesc = String(xml[descRange])
                snippet = HTMLToMarkdownConverter.decodeHTMLEntities(
                    rawDesc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let cleanTitle = HTMLToMarkdownConverter.decodeHTMLEntities(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)

            results.append(
                WebSearchResult(
                    title: cleanTitle,
                    url: url,
                    snippet: snippet.isEmpty ? cleanTitle : snippet,
                    engine: .news,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}
