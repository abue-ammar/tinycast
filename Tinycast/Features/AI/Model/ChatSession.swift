import Foundation

struct ChatSession: Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    private(set) var updatedAt: Date
    private(set) var messages: [ChatMessage]

    init(
        id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.messages = messages
    }

    var title: String {
        guard let text = messages.first(where: { $0.role == .user })?.text else {
            return "New Chat"
        }
        return Self.summary(text, limit: 72)
    }

    var preview: String {
        guard let text = messages.last(where: { !$0.text.isEmpty })?.text else { return "" }
        return Self.summary(text, limit: 120)
    }

    var summary: ChatConversation {
        ChatConversation(
            id: id, title: title, preview: preview, createdAt: createdAt,
            updatedAt: updatedAt, messageCount: messages.count)
    }

    /// `textBudget` is the route's, not the chat's: on-device windows hold far less than a cloud.
    func requestMessages(textBudget: Int = Self.defaultTextBudget) -> [AIMessage] {
        Self.boundedContext(
            messages.compactMap { message in
                guard message.role == .user || message.role == .tool || message.state == .complete else { return nil }
                switch message.role {
                case .user:
                    return AIMessage(role: .user, text: message.text, images: message.images)
                case .assistant:
                    return AIMessage(role: .assistant, text: message.text, toolCalls: message.toolCalls)
                case .tool:
                    return AIMessage(role: .tool, text: message.text, toolCallID: message.toolCallID)
                }
            }, textBudget: textBudget)
    }

    static let defaultTextBudget = 100_000

    /// Older turns come back as text inside `textBudget`, so a request stops growing with the chat.
    static func boundedContext(
        _ messages: [AIMessage], textBudget: Int = Self.defaultTextBudget
    ) -> [AIMessage] {
        guard let newest = messages.lastIndex(where: { $0.role == .user }) else { return messages }
        var remaining = textBudget
        var tail: [AIMessage] = []
        for message in messages[(newest + 1)...] {
            remaining -= message.text.utf8.count
            tail.append(AIMessage(role: message.role, text: message.text, toolCalls: message.toolCalls, toolCallID: message.toolCallID))
        }
        var head: [AIMessage] = []
        for message in messages[..<newest].reversed() {
            remaining -= message.text.utf8.count
            guard remaining >= 0 else { break }
            head.append(AIMessage(role: message.role, text: message.text, toolCalls: message.toolCalls, toolCallID: message.toolCallID))
        }
        var trimmedHead = Array(head.reversed())
        // The slice opens with a user turn; drop any partial/orphaned turns from the head.
        while let first = trimmedHead.first, first.role != .user {
            trimmedHead.removeFirst()
        }
        let prompt = messages[newest]
        let bounded = AIMessage(
            role: prompt.role, text: prompt.text,
            images: AIAttachmentBudget.bounded(prompt.images))
        return trimmedHead + [bounded] + tail
    }

    mutating func append(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = max(updatedAt, message.sentAt)
    }

    mutating func replaceLast(with message: ChatMessage, now: Date = Date()) {
        guard !messages.isEmpty else { return }
        messages[messages.count - 1] = message
        updatedAt = max(updatedAt, now)
    }

    mutating func updateMessage(id: UUID, mutate: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
        updatedAt = max(updatedAt, Date())
    }

    private static func summary(_ text: String, limit: Int) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
    }
}

struct ChatConversation: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
}
