import Foundation
import Observation

@MainActor
@Observable
final class AIChatState {
    private(set) var session = ChatSession()
    private(set) var isStreaming = false
    private(set) var isThinking = false
    private(set) var notice: String?
    /// Files staged for the next message; they go out with whatever is typed next.
    private(set) var pendingAttachments: [ChatAttachment] = []
    /// The window's unsent text; Quick AI's lives in the palette query instead.
    var draft = ""
    /// This chat's tools menu; a new chat starts with every connected server on.
    var toolScope = ChatToolScope()

    /// Every path that consumes or drops the staged images moves this on, so a late decode knows
    @ObservationIgnored private(set) var stagingGeneration = 0

    private let history: ChatHistoryStore
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var replyGeneration = 0
    /// Deltas buffered between flushes, so the transcript re-renders per cadence, not per token.
    @ObservationIgnored private var pendingText = ""
    @ObservationIgnored private var pendingReasoning = ""
    /// When the reply's latest stretch of thinking began, so its fold can say for how long.
    @ObservationIgnored private var reasoningStartedAt: Date?
    /// Told when a reply ends whole, which is when a chat has something to be named by.
    @ObservationIgnored var onReplyFinished: (@MainActor (AIChatState) -> Void)?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var lastFlush = ContinuousClock().now

    private static let flushInterval: Duration = .milliseconds(40)

    init(history: ChatHistoryStore) {
        self.history = history
    }

    @discardableResult
    func send(
        _ input: String, using provider: any AIProvider, model: AIModelSelection? = nil,
        webSearch: Bool = false, instructions: String? = nil,
        contextBudget: Int = ChatSession.defaultTextBudget, toolScope: String? = nil
    ) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty, !isStreaming else { return false }
        notice = nil
        session.append(
            ChatMessage(
                role: .user, text: text, images: pendingAttachments.compactMap(\.image),
                documents: pendingAttachments.compactMap(\.document), toolScope: toolScope))
        clearStaging()
        if let model { session.model = model }
        startReply(
            using: provider, webSearch: webSearch, instructions: instructions,
            contextBudget: contextBudget)
        return true
    }

    /// The chat's own route from now on; a saved chat records it at once, a new one on first send.
    func setModel(_ model: AIModelSelection) {
        session.model = model
        history.setModel(model, id: session.id)
    }

    /// Asks again for the last reply; the question and its attachments go out as they first did.
    @discardableResult
    func regenerate(
        using provider: any AIProvider, model: AIModelSelection? = nil, webSearch: Bool = false,
        instructions: String? = nil, contextBudget: Int = ChatSession.defaultTextBudget
    ) -> Bool {
        guard !isStreaming, session.dropTrailingReply() else { return false }
        notice = nil
        if let model { session.model = model }
        startReply(
            using: provider, webSearch: webSearch, instructions: instructions,
            contextBudget: contextBudget)
        return true
    }

    private func startReply(
        using provider: any AIProvider, webSearch: Bool, instructions: String?, contextBudget: Int
    ) {
        let request = AIRequest(
            instructions: instructions,
            messages: session.requestMessages(textBudget: contextBudget), webSearch: webSearch)
        session.append(ChatMessage(role: .assistant, text: "", state: .streaming))
        isStreaming = true
        isThinking = false
        reasoningStartedAt = nil
        history.save(session)

        replyGeneration += 1
        let generation = replyGeneration
        replyTask = Task { [weak self, provider] in
            do {
                for try await event in provider.stream(request) {
                    guard let self, !Task.isCancelled, self.replyGeneration == generation else {
                        return
                    }
                    self.receive(event)
                }
                guard let self, !Task.isCancelled, self.replyGeneration == generation,
                    self.isStreaming
                else { return }
                self.finishLast(state: .failed, fallback: "The response ended unexpectedly.")
            } catch {
                guard let self, !Task.isCancelled, self.replyGeneration == generation,
                    self.isStreaming
                else { return }
                self.finishLast(state: .failed, fallback: error.localizedDescription)
            }
        }
    }

    func report(_ message: String) {
        notice = message
    }

    /// Refused, not truncated: the composer is the last place an oversized turn can be explained.
    @discardableResult
    func attach(_ attachment: ChatAttachment) -> ChatAttachmentRefusal? {
        // Deliberately not de-duped: pasting the same file twice means you wanted it twice.
        guard pendingAttachments.count < AIAttachmentBudget.maxCount else { return .count }
        guard
            AIAttachmentBudget.admits(
                images: pendingAttachments.compactMap(\.image),
                documents: pendingAttachments.compactMap(\.document),
                addingBytes: attachment.payload.byteCount)
        else { return .size }
        pendingAttachments.append(attachment)
        return nil
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    @discardableResult
    func removeLastAttachment() -> Bool {
        guard !pendingAttachments.isEmpty else { return false }
        pendingAttachments.removeLast()
        return true
    }

    func clearAttachments() {
        clearStaging()
    }

    private func clearStaging() {
        pendingAttachments = []
        stagingGeneration += 1
    }

    func cancel() {
        replyGeneration += 1
        replyTask?.cancel()
        replyTask = nil
        guard isStreaming else {
            discardPendingText()
            return
        }
        finishLast(state: .failed, fallback: "Cancelled")
    }

    func startNewChat() {
        cancel()
        session = ChatSession()
        notice = nil
        clearStaging()
    }

    /// Staged images belong to the conversation they were picked in; leaving it drops them.
    @discardableResult
    func open(id: UUID) -> Bool {
        if session.id == id, !session.messages.isEmpty { return true }
        guard let loaded = history.session(id: id) else { return false }
        cancel()
        session = loaded
        notice = nil
        clearStaging()
        return true
    }

    func delete(id: UUID) {
        if session.id == id {
            cancel()
            session = ChatSession()
            notice = nil
            clearStaging()
        }
        history.remove(id: id)
    }

    /// The latest reply's report, so a reopened chat still knows what its last turn cost.
    var usage: AIUsage? {
        session.messages.last { $0.role == .assistant && $0.usage != nil }?.usage
    }

    /// True when this state is the one showing `id`; an empty chat holds nothing yet.
    func holds(_ id: UUID) -> Bool {
        session.id == id && !session.messages.isEmpty
    }

    /// The line shown in the empty streaming bubble while nothing has arrived yet.
    var liveStatus: String? { isThinking ? "Thinking…" : nil }

    var lastAssistantText: String? {
        session.messages.last(where: { $0.role == .assistant && !$0.text.isEmpty })?.text
    }

    private func receive(_ event: AIStreamEvent) {
        switch event {
        case .text(let text):
            guard let last = session.messages.last, last.role == .assistant else { return }
            if isThinking { isThinking = false }
            // Buffered in order: thinking before this text must land before it, not after.
            if !pendingReasoning.isEmpty { flushPendingText() }
            queueDelta(text)
        case .thinking:
            isThinking = true
        case .reasoning(let text):
            guard let last = session.messages.last, last.role == .assistant else { return }
            isThinking = true
            if !pendingText.isEmpty { flushPendingText() }
            pendingReasoning += text
            scheduleFlush()
        case .searching(let query):
            flushPendingText()
            guard var message = session.messages.last, message.role == .assistant else { return }
            isThinking = false
            message.searches.append(
                ChatSearch(
                    query: query, isComplete: false, textOffset: message.text.count,
                    sequence: message.nextSequence))
            session.replaceLast(with: message)
        case .searched(let query):
            flushPendingText()
            guard var message = session.messages.last, message.role == .assistant else { return }
            if let index = message.searches.lastIndex(where: { !$0.isComplete }) {
                message.searches[index].query = message.searches[index].query ?? query
            }
            message.searches = message.searches.map { Self.completed($0) }
            session.replaceLast(with: message)
        case .toolCall(let id, let origin, let title):
            flushPendingText()
            guard var message = session.messages.last, message.role == .assistant else { return }
            isThinking = false
            message.toolUses.append(
                ChatToolUse(
                    callID: id, origin: origin, title: title, state: .running,
                    textOffset: message.text.count, sequence: message.nextSequence))
            session.replaceLast(with: message)
        case .toolResult(let id, let isError):
            guard var message = session.messages.last, message.role == .assistant else { return }
            guard let index = message.toolUses.lastIndex(where: { $0.callID == id }) else { return }
            message.toolUses[index].state = isError ? .failed : .completed
            session.replaceLast(with: message)
        case .toolCallRequested:
            break
        case .usage(let usage):
            guard var message = session.messages.last, message.role == .assistant else { return }
            message.usage = usage
            session.replaceLast(with: message)
        case .finished:
            finishLast(state: .complete, fallback: "No response")
        }
    }

    /// A due leading flush keeps the first token instant; the trailing task coalesces the rest.
    private func queueDelta(_ text: String) {
        pendingText += text
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        if ContinuousClock().now - lastFlush >= Self.flushInterval { flushPendingText() }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            self.flushPendingText()
        }
    }

    private func flushPendingText() {
        guard !pendingText.isEmpty || !pendingReasoning.isEmpty else { return }
        guard var message = session.messages.last, message.role == .assistant else {
            pendingText = ""
            pendingReasoning = ""
            return
        }
        appendReasoning(pendingReasoning, to: &message)
        pendingReasoning = ""
        if !pendingText.isEmpty {
            // Text after a search means the search is over, whether or not the route says so.
            message.searches = message.searches.map { Self.completed($0) }
            // The answer resuming is where that stretch of thinking ended.
            closeReasoning(in: &message)
        }
        message.text += pendingText
        pendingText = ""
        session.replaceLast(with: message)
        lastFlush = ContinuousClock().now
    }

    private func discardPendingText() {
        flushTask?.cancel()
        flushTask = nil
        pendingText = ""
        pendingReasoning = ""
    }

    private func finishLast(state: ChatMessage.State, fallback: String) {
        flushPendingText()
        discardPendingText()
        guard var message = session.messages.last, message.role == .assistant else { return }
        if state == .failed, !message.text.isEmpty {
            message.text += "\n\n\(fallback)"
        } else if message.text.isEmpty {
            message.text = fallback
        }
        message.state = state
        closeReasoning(in: &message)
        message.searches = message.searches.map { Self.completed($0) }
        // A call still running when the turn ends never reported back, whatever ended the turn.
        message.toolUses = message.toolUses.map { Self.settled($0) }
        session.replaceLast(with: message)
        history.save(session)
        isStreaming = false
        isThinking = false
        replyTask = nil
        if state == .complete { onReplyFinished?(self) }
    }

    /// Thinking after answer text is a new stretch, pinned where the answer paused for it.
    private func appendReasoning(_ text: String, to message: inout ChatMessage) {
        guard !text.isEmpty else { return }
        let offset = message.text.count
        if let last = message.reasoning.last, last.textOffset == offset, last.duration == nil {
            message.reasoning[message.reasoning.count - 1].text += text
            return
        }
        // A route's block separator opening a stretch is not text the fold should start with.
        let opening = String(text.drop(while: \.isWhitespace))
        guard !opening.isEmpty else { return }
        reasoningStartedAt = Date()
        message.reasoning.append(ChatReasoning(text: opening, textOffset: offset, duration: nil))
    }

    private func closeReasoning(in message: inout ChatMessage) {
        guard let last = message.reasoning.last, last.duration == nil,
            let started = reasoningStartedAt
        else { return }
        message.reasoning[message.reasoning.count - 1].duration = Date().timeIntervalSince(started)
        reasoningStartedAt = nil
    }
}

extension AIChatState {
    fileprivate static func completed(_ search: ChatSearch) -> ChatSearch {
        var search = search
        search.isComplete = true
        return search
    }

    fileprivate static func settled(_ use: ChatToolUse) -> ChatToolUse {
        guard use.state == .running else { return use }
        var use = use
        use.state = .failed
        return use
    }
}

/// Why the composer would not take another file; the limits are `AIAttachmentBudget`'s.
enum ChatAttachmentRefusal: Equatable, Sendable {
    case count
    case size
    case textTooLong
    case undecodable
    case unreadable
    case unsupported(String)
    case imagesUnsupported
    case documentsUnsupported

    var message: String {
        switch self {
        case .count:
            return "\(AIAttachmentBudget.maxCount) attachments is all one message can carry."
        case .size: return "That file is too big for this message — send these first."
        case .textTooLong:
            let limit = AIAttachmentBudget.maxInlinedTextBytes / 1_024
            return "That text file is too big to attach — \(limit) KB is the limit."
        case .undecodable: return "That file isn't text Tinycast can read."
        case .unreadable: return "That file could not be read."
        case .unsupported(let ext):
            return "Tinycast can attach images, PDFs and text files, not .\(ext) files."
        case .imagesUnsupported: return "This model can't read images. Switch model to attach one."
        case .documentsUnsupported:
            return "This model can't read PDFs. Switch model, or paste the text instead."
        }
    }
}

/// A staged file with the name and preview the chip shows; neither ever goes on the wire.
struct ChatAttachment: Identifiable, Equatable, Sendable {
    /// One staged list holds all three, so every lifetime rule applies to them alike.
    enum Payload: Equatable, Sendable {
        case image(AIImage)
        case document(AIDocument)

        var byteCount: Int {
            switch self {
            case .image(let image): return image.data.count
            case .document(let document): return document.data.count
            }
        }
    }

    let id = UUID()
    let payload: Payload
    let name: String
    /// A ~40px PNG, about a kilobyte: six cost less to decode than one keystroke's re-render.
    let preview: Data?

    var image: AIImage? {
        guard case .image(let image) = payload else { return nil }
        return image
    }

    var document: AIDocument? {
        guard case .document(let document) = payload else { return nil }
        return document
    }

    var kind: AIAttachmentPolicy.Kind {
        switch payload {
        case .image: return .image
        case .document(let document):
            return document.mimeType == AIAttachmentPolicy.pdfMIMEType ? .pdf : .text
        }
    }
}
