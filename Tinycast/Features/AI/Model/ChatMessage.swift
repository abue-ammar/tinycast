import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
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
    /// Web searches the reply made, in order; each sits in the text where it happened.
    var searches: [ChatSearch]
    /// Tools the reply called, pinned the same way; the calls themselves never enter the context.
    var toolUses: [ChatToolUse]

    init(
        id: UUID = UUID(), role: Role, text: String, state: State = .complete,
        sentAt: Date = Date(), images: [AIImage] = [], searches: [ChatSearch] = [],
        toolUses: [ChatToolUse] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.sentAt = sentAt
        self.images = images
        self.searches = searches
        self.toolUses = toolUses
    }

    /// The reply split around what it did: text, search or tool, text… rendered where it happened.
    var segments: [ChatSegment] {
        let interruptions =
            (searches.map { (offset: $0.textOffset, segment: ChatSegment.search($0)) }
            + toolUses.map { (offset: $0.textOffset, segment: ChatSegment.tool($0)) })
            .sorted { $0.offset < $1.offset }
        var segments: [ChatSegment] = []
        var rest = Substring(text)
        var consumed = 0
        for interruption in interruptions {
            let take = max(0, min(interruption.offset - consumed, rest.count))
            if take > 0 { segments.append(.text(String(rest.prefix(take)))) }
            segments.append(interruption.segment)
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
}

/// One tool call inside a reply: live while it runs, a record of what ran once it is done.
struct ChatToolUse: Equatable, Hashable, Sendable {
    enum State: String, Equatable, Hashable, Sendable {
        case running
        case completed
        case failed
    }

    let callID: String
    let origin: String
    let title: String
    var state: State
    /// Characters of reply text that had arrived when the call started.
    let textOffset: Int

    var label: String {
        let verb = state == .running ? "Calling" : "Called"
        return origin.isEmpty ? "\(verb) \(title)" : "\(verb) \(origin) · \(title)"
    }
}

enum ChatSegment: Equatable, Hashable {
    case text(String)
    case search(ChatSearch)
    case tool(ChatToolUse)
}
