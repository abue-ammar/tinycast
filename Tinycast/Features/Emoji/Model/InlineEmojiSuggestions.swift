import Foundation

enum InlineEmojiSuggestions: String, CaseIterable, Identifiable, Sendable {
    case frequentlyUsed
    case pinned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frequentlyUsed: String(localized: "Frequently Used")
        case .pinned: String(localized: "Pinned")
        }
    }
}
