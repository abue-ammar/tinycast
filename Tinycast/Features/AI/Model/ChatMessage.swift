import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
        case tool
    }

    enum State: String, Equatable, Sendable {
        case streaming
        case complete
        case failed
    }

    let id: UUID
    let role: Role
    var text: String
    var state: State
    let sentAt: Date
    let images: [AIImage]
    var toolCalls: [AIToolCall]
    let toolCallID: String?
    /// Web searches the reply made, in order; each sits in the text where it happened.
    var searches: [ChatSearch]

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        state: State = .complete,
        sentAt: Date = Date(),
        images: [AIImage] = [],
        toolCalls: [AIToolCall] = [],
        toolCallID: String? = nil,
        searches: [ChatSearch] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.sentAt = sentAt
        self.images = images
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.searches = searches
    }

    /// The reply split around its searches: text, search, text… so the row renders in place.
    var segments: [ChatSegment] {
        var segments: [ChatSegment] = []
        var rest = Substring(text)
        var consumed = 0
        for search in searches {
            let take = max(0, min(search.textOffset - consumed, rest.count))
            if take > 0 { segments.append(.text(String(rest.prefix(take)))) }
            segments.append(.search(search))
            rest = rest.dropFirst(take)
            consumed += take
        }
        if !rest.isEmpty { segments.append(.text(String(rest))) }
        return segments
    }
}

struct ChatSearch: Equatable, Hashable, Sendable {
    var query: String?
    var isComplete: Bool
    /// Characters of reply text that had arrived when the search began.
    let textOffset: Int

    init(query: String?, isComplete: Bool = true, textOffset: Int = 0) {
        self.query = query
        self.isComplete = isComplete
        self.textOffset = textOffset
    }
}

enum ChatSegment: Equatable {
    case text(String)
    case search(ChatSearch)
}


/// A staged tool or extension mention in AI Chat.
struct AIMentionItem: Identifiable, Hashable, Equatable, Sendable {
    let id: String
    let token: String
    let title: String
    let iconName: String?
    let iconPath: String?
}
