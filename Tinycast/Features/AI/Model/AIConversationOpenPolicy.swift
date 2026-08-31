import Foundation

/// What summoning AI Chat lands on, decided at open time rather than when the palette hides.
enum AIOpensTo: Int, CaseIterable, Identifiable, Sendable {
    case recent = 0
    case newConversation = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent Conversation"
        case .newConversation: return "A New Conversation"
        }
    }
}

/// Minutes as the raw value, `never` negative so it cannot collide with the 0 an unset key reads.
enum AINewChatAfter: Int, CaseIterable, Identifiable, Sendable {
    case twoMinutes = 2
    case fiveMinutes = 5
    case tenMinutes = 10
    case thirtyMinutes = 30
    case never = -1

    var id: Int { rawValue }

    var title: String {
        self == .never ? "Never" : "\(rawValue) Minutes"
    }

    var interval: TimeInterval { TimeInterval(rawValue) * 60 }
}

/// One clock, read from a timestamp, so the verdict survives a relaunch as a hide timer could not.
enum AIConversationOpenPolicy {
    enum Decision: Equatable, Sendable {
        case resume
        case startNew
    }

    /// `lastActiveAt` is nil when there is nothing to go back to, which is already a new chat.
    static func decide(
        opensTo: AIOpensTo, newAfter: AINewChatAfter, lastActiveAt: Date?, now: Date
    ) -> Decision {
        guard opensTo == .recent, let lastActiveAt else { return .startNew }
        guard newAfter != .never else { return .resume }
        // A backwards clock yields a negative interval; it must not strand a reader in a chat.
        let idle = now.timeIntervalSince(lastActiveAt)
        return idle >= newAfter.interval ? .startNew : .resume
    }
}
