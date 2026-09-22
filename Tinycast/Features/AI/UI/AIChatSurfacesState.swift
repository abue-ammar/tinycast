import Foundation
import Observation

/// Which live chat each surface shows; a chat is live in one place, and leaving never cancels it.
@MainActor
@Observable
final class AIChatSurfacesState {
    /// The palette's conversation.
    private(set) var quickAI: AIChatState
    /// The AI Chat window's conversation.
    private(set) var window: AIChatState
    /// Window conversations left mid-reply; each saves itself when its reply ends.
    private var answeringElsewhere: [UUID: AIChatState] = [:]

    private let history: ChatHistoryStore

    /// Handed to every state, so a chat that finishes its first answer can be named wherever it is.
    @ObservationIgnored var onReplyFinished: (@MainActor (AIChatState) -> Void)? {
        didSet {
            for state in [quickAI, window] + answeringElsewhere.values {
                state.onReplyFinished = onReplyFinished
            }
        }
    }

    init(history: ChatHistoryStore) {
        self.history = history
        quickAI = AIChatState(history: history)
        window = AIChatState(history: history)
    }

    private func makeState() -> AIChatState {
        let state = AIChatState(history: history)
        state.onReplyFinished = onReplyFinished
        return state
    }

    /// Conversations with a reply still arriving, wherever they are shown.
    var answeringIDs: Set<UUID> {
        Set(live.filter(\.isStreaming).map(\.session.id))
    }

    /// Whoever holds `id` right now, so a second surface never edits the same transcript.
    func holder(of id: UUID) -> AIChatState? {
        live.first { $0.holds(id) }
    }

    // MARK: - The window

    /// Reuses the live state wherever it is, so a reply still arriving keeps arriving on screen.
    @discardableResult
    func openInWindow(id: UUID) -> Bool {
        if window.holds(id) { return true }
        let next: AIChatState
        if quickAI.holds(id) {
            next = quickAI
            quickAI = makeState()
        } else if let answering = answeringElsewhere.removeValue(forKey: id), answering.isStreaming {
            next = answering
        } else {
            let loaded = makeState()
            guard loaded.open(id: id) else { return false }
            next = loaded
        }
        show(next)
        return true
    }

    /// An empty chat is already new; replacing it would only drop what is staged in it.
    func newWindowChat() {
        guard !window.session.messages.isEmpty else { return }
        show(makeState())
    }

    /// Quick AI's conversation moves over whole, reply and staged files included.
    @discardableResult
    func continueQuickAIInWindow(draft: String = "") -> Bool {
        guard !quickAI.session.messages.isEmpty || !quickAI.pendingAttachments.isEmpty else {
            // Nothing moves, so the line joins the window chat's own unsent text rather than replace it.
            if !draft.isEmpty {
                window.draft = window.draft.isEmpty ? draft : window.draft + "\n" + draft
            }
            return false
        }
        let moved = quickAI
        quickAI = makeState()
        show(moved)
        if !draft.isEmpty { window.draft = draft }
        return true
    }

    private func show(_ next: AIChatState) {
        if window.isStreaming { answeringElsewhere[window.session.id] = window }
        window = next
        answeringElsewhere = answeringElsewhere.filter { $0.value.isStreaming }
    }

    // MARK: - Quick AI

    /// Refused while another surface has it: two writers would each save over the other.
    @discardableResult
    func openInQuickAI(id: UUID) -> Bool {
        if quickAI.holds(id) { return true }
        guard holder(of: id) == nil else { return false }
        return quickAI.open(id: id)
    }

    // MARK: - Every surface

    func delete(id: UUID) {
        (holder(of: id) ?? window).delete(id: id)
        answeringElsewhere[id] = nil
    }

    /// Every doomed reply is cancelled before the clear: a cancel saves, which would bring it back.
    func deleteAll() {
        let doomed = live.filter { history.conversation(id: $0.session.id)?.isPinned != true }
        for state in doomed { state.cancel() }
        history.clearAll()
        for state in doomed { state.startNewChat() }
        answeringElsewhere = answeringElsewhere.filter { entry in
            !doomed.contains { $0 === entry.value }
        }
    }

    /// Off, or quitting: every reply stops and saves, and both surfaces start over.
    func reset() {
        for state in live { state.startNewChat() }
        answeringElsewhere = [:]
    }

    /// A parked chat that has finished is already saved, so only one still answering counts.
    private var live: [AIChatState] {
        [quickAI, window] + answeringElsewhere.values.filter(\.isStreaming)
    }
}
