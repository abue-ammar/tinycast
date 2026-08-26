import Foundation

public struct WebSearchResult: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let url: URL
    public let snippet: String
    public let engine: WebSearchEngineType
    public let rank: Int
    public var score: Double
    public let publishedDate: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        snippet: String,
        engine: WebSearchEngineType,
        rank: Int = 1,
        score: Double = 0.0,
        publishedDate: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
        self.snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        self.engine = engine
        self.rank = rank
        self.score = score
        self.publishedDate = publishedDate
    }
}
