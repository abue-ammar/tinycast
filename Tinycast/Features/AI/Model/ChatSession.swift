import Foundation

struct ChatSession: Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    private(set) var updatedAt: Date
    private(set) var messages: [ChatMessage]
    /// The route this chat talks to, so coming back to it comes back to the same model.
    var model: AIModelSelection?

    init(
        id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil,
        messages: [ChatMessage] = [], model: AIModelSelection? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.messages = messages
        self.model = model
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
            historyMessages.map { message in
                AIMessage(
                    role: message.role == .user ? .user : .assistant,
                    text: message.text, images: message.images, documents: message.documents)
            }, textBudget: textBudget)
    }

    static let defaultTextBudget = 100_000

    /// The turns a request may carry as history: a failed or unfinished reply never goes out.
    var historyMessages: [ChatMessage] {
        messages.filter { $0.role == .user || $0.state == .complete }
    }

    /// Counted in the budget's own unit; past `textBudget` the oldest turns stop going out.
    var historyBytes: Int {
        historyMessages.reduce(0) { $0 + $1.text.utf8.count }
    }

    /// How many turns `requestMessages` would send, counted without building or inlining them.
    func sentMessageCount(textBudget: Int = Self.defaultTextBudget) -> Int {
        let history = historyMessages
        guard let newest = history.lastIndex(where: { $0.role == .user }) else {
            return history.count
        }
        var remaining = textBudget
        let tail = history[(newest + 1)...]
        remaining -= tail.reduce(0) { $0 + $1.text.utf8.count }
        var head: [ChatMessage.Role] = []
        for message in history[..<newest].reversed() {
            remaining -= message.text.utf8.count
            guard remaining >= 0 else { break }
            head.append(message.role)
        }
        // Mirrors `boundedContext`: a slice never opens on a reply whose question fell out.
        while head.last == .assistant { head.removeLast() }
        return head.count + 1 + tail.count
    }

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
        let kept = AIAttachmentBudget.bounded(prompt.images, prompt.documents)
        // Inlined here, not in `ChatMessage.text`: the transcript's title is its first user text.
        let bounded = AIMessage(
            role: prompt.role,
            text: AIAttachmentPolicy.prompt(text: prompt.text, documents: kept.documents),
            images: kept.images,
            documents: kept.documents.filter { $0.mimeType == AIAttachmentPolicy.pdfMIMEType })
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

    /// Regenerate's first half: only a trailing reply goes, so the question it answered stays.
    @discardableResult
    mutating func dropTrailingReply() -> Bool {
        guard messages.last?.role == .assistant, messages.count > 1 else { return false }
        messages.removeLast()
        return true
    }

    /// What Copy Chat puts on the pasteboard: each turn under its speaker, attachments by name.
    func markdownTranscript(title: String) -> String {
        var parts = ["# \(title)"]
        for message in messages
        where !message.text.isEmpty || !message.documents.isEmpty || !message.images.isEmpty {
            var turn = message.role == .user ? "**You**" : "**AI**"
            let names = message.documents.map(\.name) + message.images.map { _ in "Image" }
            if !names.isEmpty { turn += " _(attached: \(names.joined(separator: ", ")))_" }
            // The choices fence drew buttons; in a pasted transcript it is only markup.
            let text = message.role == .assistant ? ChatChoices.split(message.text).text : message.text
            parts.append(turn + "\n\n" + text)
        }
        return parts.joined(separator: "\n\n")
    }

    private static func summary(_ text: String, limit: Int) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
    }
}

struct ChatConversation: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Derived from the first question; a rename lives beside it and never overwrites it.
    let title: String
    let preview: String
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
    var customTitle: String?
    var isPinned = false
    /// What the chat's harness or model named it; a rename still wins over it.
    var generatedTitle: String?

    var displayTitle: String { customTitle ?? generatedTitle ?? title }
}
