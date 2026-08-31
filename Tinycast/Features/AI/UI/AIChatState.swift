import Foundation
import Observation

@MainActor
@Observable
final class AIChatState {
    private(set) var session = ChatSession()
    private(set) var isStreaming = false
    private(set) var isThinking = false
    private(set) var usage: AIUsage?
    private(set) var notice: String?
    /// Images staged for the next message; they go out with whatever is typed next.
    private(set) var pendingImages: [ChatAttachment] = []

    /// Every path that consumes or drops the staged images moves this on, so a late decode knows
    @ObservationIgnored private(set) var stagingGeneration = 0

    private let history: ChatHistoryStore
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var replyGeneration = 0
    /// Deltas buffered between flushes, so the transcript re-renders per cadence, not per token.
    @ObservationIgnored private var pendingText = ""
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var lastFlush = ContinuousClock().now

    private static let flushInterval: Duration = .milliseconds(40)

    init(history: ChatHistoryStore) {
        self.history = history
    }

    @discardableResult
    func send(
        _ input: String, using provider: any AIProvider, webSearch: Bool = false,
        instructions: String? = nil, contextBudget: Int = ChatSession.defaultTextBudget
    ) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty, !isStreaming else { return false }
        notice = nil
        session.append(ChatMessage(role: .user, text: text, images: pendingImages.map(\.image)))
        clearStaging()
        session.append(ChatMessage(role: .assistant, text: "", state: .streaming))
        isStreaming = true
        isThinking = false
        usage = nil
        history.save(session)

        replyGeneration += 1
        let generation = replyGeneration
        replyTask = Task { [weak self, provider] in
            do {
                var turn = 0
                let maxTurns = 8
                let registry = AIToolRegistry.shared

                while turn < maxTurns {
                    turn += 1
                    guard let self, !Task.isCancelled, self.replyGeneration == generation else { return }
                    let canUseTools = (turn < maxTurns - 1)
                    let availableTools = canUseTools ? registry.availableTools : []
                    let currentRequest = AIRequest(
                        instructions: instructions,
                        messages: self.session.requestMessages(textBudget: contextBudget),
                        webSearch: webSearch,
                        tools: availableTools
                    )

                    var receivedToolCalls: [AIToolCall] = []

                    for try await event in provider.stream(currentRequest) {
                        guard !Task.isCancelled, self.replyGeneration == generation else {
                            return
                        }
                        if case .toolCall(let call) = event {
                            receivedToolCalls.append(call)
                        } else {
                            self.receive(event)
                        }
                    }

                    guard !Task.isCancelled, self.replyGeneration == generation else { return }

                    if !receivedToolCalls.isEmpty {
                        self.flushPendingText()
                        if var last = self.session.messages.last, last.role == .assistant {
                            last.toolCalls = receivedToolCalls
                            self.session.replaceLast(with: last)
                        }
                        for toolCall in receivedToolCalls {
                            let result = await registry.execute(call: toolCall)
                            self.session.append(
                                ChatMessage(
                                    role: .tool,
                                    text: result.output,
                                    state: .complete,
                                    toolCallID: result.callID
                                )
                            )
                        }
                        self.session.append(ChatMessage(role: .assistant, text: "", state: .streaming))
                        self.history.save(self.session)
                        continue
                    } else {
                        break
                    }
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
        return true
    }

    func report(_ message: String) {
        notice = message
    }

    /// Refused, not truncated: the composer is the last place an oversized turn can be explained.
    @discardableResult
    func attach(_ attachment: ChatAttachment) -> ChatAttachmentRefusal? {
        guard !pendingImages.contains(where: { $0.image == attachment.image }) else { return nil }
        guard pendingImages.count < AIAttachmentBudget.maxCount else { return .count }
        guard AIAttachmentBudget.admits(pendingImages.map(\.image), adding: attachment.image) else {
            return .size
        }
        pendingImages.append(attachment)
        return nil
    }

    @discardableResult
    func removeLastAttachment() -> Bool {
        guard !pendingImages.isEmpty else { return false }
        pendingImages.removeLast()
        return true
    }

    func clearAttachments() {
        clearStaging()
    }

    private func clearStaging() {
        pendingImages = []
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
        usage = nil
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
        usage = nil
        notice = nil
        clearStaging()
        return true
    }

    func delete(id: UUID) {
        if session.id == id {
            cancel()
            session = ChatSession()
            usage = nil
            notice = nil
            clearStaging()
        }
        history.remove(id: id)
    }

    func deleteAll() {
        cancel()
        history.clearAll()
        session = ChatSession()
        usage = nil
        notice = nil
        clearStaging()
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
            queueDelta(text)
        case .thinking:
            isThinking = true
        case .searching(let query):
            flushPendingText()
            guard var message = session.messages.last, message.role == .assistant else { return }
            isThinking = false
            message.searches.append(
                ChatSearch(query: query, isComplete: false, textOffset: message.text.count))
            session.replaceLast(with: message)
        case .searched(let query):
            flushPendingText()
            guard var message = session.messages.last, message.role == .assistant else { return }
            if let index = message.searches.lastIndex(where: { !$0.isComplete }) {
                message.searches[index].query = message.searches[index].query ?? query
            }
            message.searches = message.searches.map { Self.completed($0) }
            session.replaceLast(with: message)
        case .usage(let usage):
            self.usage = usage
        case .toolCall, .toolExecuting:
            break
        case .finished:
            finishLast(state: .complete, fallback: "No response")
        }
    }

    /// A due leading flush keeps the first token instant; the trailing task coalesces the rest.
    private func queueDelta(_ text: String) {
        pendingText += text
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
        guard !pendingText.isEmpty else { return }
        guard var message = session.messages.last, message.role == .assistant else {
            pendingText = ""
            return
        }
        // Text after a search means the search is over, whether or not the route says so.
        message.searches = message.searches.map { Self.completed($0) }
        message.text += pendingText
        pendingText = ""
        session.replaceLast(with: message)
        lastFlush = ContinuousClock().now
    }

    private func discardPendingText() {
        flushTask?.cancel()
        flushTask = nil
        pendingText = ""
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
        message.searches = message.searches.map { Self.completed($0) }
        session.replaceLast(with: message)
        history.save(session)
        isStreaming = false
        isThinking = false
        replyTask = nil
    }
}

extension AIChatState {
    fileprivate static func completed(_ search: ChatSearch) -> ChatSearch {
        var search = search
        search.isComplete = true
        return search
    }
}

/// Why the composer would not take another picture; both limits are `AIAttachmentBudget`'s.
enum ChatAttachmentRefusal: Equatable, Sendable {
    case count
    case size

    var message: String {
        switch self {
        case .count: return "\(AIAttachmentBudget.maxCount) images is all one message can carry."
        case .size: return "That image is too big for this message — send these first."
        }
    }
}

/// A staged image with the name the chip shows; the name is for the composer only, not the wire.
struct ChatAttachment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let image: AIImage
    let name: String
}
