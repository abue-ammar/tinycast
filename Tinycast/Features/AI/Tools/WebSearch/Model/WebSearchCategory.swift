import Foundation

public enum WebSearchCategory: String, CaseIterable, Codable, Sendable {
    case general
    case news
    case wikipedia

    public var displayName: String {
        switch self {
        case .general: return "General"
        case .news: return "News"
        case .wikipedia: return "Wikipedia"
        }
    }
}
