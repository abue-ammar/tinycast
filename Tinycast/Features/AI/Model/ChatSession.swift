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
                guard message.role == .user || message.state == .complete else { return nil }
                return AIMessage(
                    role: message.role == .user ? .user : .assistant,
                    text: message.text, images: message.images)
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
            tail.append(AIMessage(role: message.role, text: message.text))
        }
        var head: [AIMessage] = []
        for message in messages[..<newest].reversed() {
            remaining -= message.text.utf8.count
            guard remaining >= 0 else { break }
            head.append(AIMessage(role: message.role, text: message.text))
        }
        // The slice opens with the user turn that prompted it; an orphaned reply reads as noise.
        while head.last?.role == .assistant { head.removeLast() }
        let prompt = messages[newest]
        let bounded = AIMessage(
            role: prompt.role, text: prompt.text,
            images: AIAttachmentBudget.bounded(prompt.images))
        return head.reversed() + [bounded] + tail
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
