import Foundation

public enum WikipediaEngine {
    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&utf8=1") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Tinycast-Search/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryObj = json["query"] as? [String: Any],
              let searchArr = queryObj["search"] as? [[String: Any]] else {
            return []
        }

        var results: [WebSearchResult] = []
        var rank = 1

        for item in searchArr.prefix(5) {
            guard let title = item["title"] as? String,
                  let rawSnippet = item["snippet"] as? String,
                  let pageURL = URL(string: "https://en.wikipedia.org/wiki/\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)") else {
                continue
            }

            let cleanSnippet = HTMLToMarkdownConverter.decodeHTMLEntities(
                rawSnippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            )

            results.append(
                WebSearchResult(
                    title: "\(title) - Wikipedia",
                    url: pageURL,
                    snippet: cleanSnippet,
                    engine: .wikipedia,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}
