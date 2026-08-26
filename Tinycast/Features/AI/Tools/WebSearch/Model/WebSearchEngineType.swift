import Foundation

public enum WebSearchEngineType: String, CaseIterable, Codable, Sendable {
    case duckDuckGo = "duckduckgo"
    case brave = "brave"
    case aol = "aol"
    case yahoo = "yahoo"
    case wikipedia = "wikipedia"
    case news = "news"

    public var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .brave: return "Brave"
        case .aol: return "AOL"
        case .yahoo: return "Yahoo"
        case .wikipedia: return "Wikipedia"
        case .news: return "News"
        }
    }

    public var defaultWeight: Double {
        switch self {
        case .news: return 1.3
        case .duckDuckGo: return 1.1
        case .brave: return 1.0
        case .yahoo: return 1.0
        case .aol: return 0.85
        case .wikipedia: return 0.9
        }
    }
}
