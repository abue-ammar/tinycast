import Foundation

/// The palette's AI screen: summoning, the open policy, and handing a chat on to the window.
@MainActor
final class QuickAICoordinator {
    private let chats: AIChatSurfacesState
    private let settings: AppSettings
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(
        chats: AIChatSurfacesState, settings: AppSettings, palette: PaletteState,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.chats = chats
        self.settings = settings
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    private var chat: AIChatState { chats.quickAI }
    private var chatCoordinator: AIChatCoordinator { core.aiChatCoordinator }

    func show() {
        guard settings.aiEnabled else { return }
        // Not `togglePalette`: the open policy decides a chat only on the way in.
        guard !paletteCoordinator.isShowing(.ai) else {
            paletteCoordinator.hidePalette()
            return
        }
        applyOpenPolicy()
        paletteCoordinator.showPalette(mode: .ai)
    }

    /// ⇥ and the AI fallback: a fresh chat that carries the question, already asked.
    func ask(_ prompt: String) {
        guard settings.aiEnabled else { return }
        // No question is no reason to skip the open policy: this is a summon, not an ask.
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show()
            return
        }
        chat.startNewChat()
        paletteCoordinator.showPalette(mode: .ai)
        send(prompt)
    }

    /// Off leaves the screen too, so the palette never shows a feature that is gone.
    func leave() {
        if palette.mode == .ai || palette.mode == .aiHistory { palette.prepare(mode: .launcher) }
    }

    /// A file pasted at the launcher belongs in Quick AI, never in a search for its name.
    func attachPastedFileFromLauncher(files: [URL]) -> Bool {
        guard settings.aiEnabled, !files.isEmpty else { return false }
        show()
        return attachPastedFile(files: files)
    }

    func attachPastedFile(files: [URL]) -> Bool {
        chatCoordinator.attachPastedFile(files: files, to: chat)
    }

    /// The one place deciding whether summoning resumes; Pop to Root only forgets the screen.
    private func applyOpenPolicy() {
        // A reply still arriving was asked for; resetting would discard the answer.
        guard !chat.isStreaming else { return }
        let recent = core.chatHistory.conversations.first
        let hasTranscript = !chat.session.messages.isEmpty
        // Staged files are unsent work: neither branch may throw them away on a plain re-summon.
        let hasStaging = !chat.pendingAttachments.isEmpty
        // From history when nothing is resident, so the verdict still holds after a relaunch.
        let lastActiveAt = hasTranscript ? chat.session.updatedAt : recent?.updatedAt
        let decision = AIConversationOpenPolicy.decide(
            opensTo: core.aiSettings.opensTo, newAfter: core.aiSettings.newChatAfter,
            lastActiveAt: lastActiveAt, now: Date())
        switch decision {
        case .resume:
            guard !hasTranscript, !hasStaging, let recent else { return }
            // The window may have it open, in which case this summon starts fresh instead.
            chats.openInQuickAI(id: recent.id)
        case .startNew:
            // An empty chat is already new; resetting it would only drop what is staged in it.
            guard hasTranscript else { return }
            chat.startNewChat()
        }
    }

    @discardableResult
    func send(_ input: String) -> Bool {
        chatCoordinator.send(input, in: chat)
    }

    func startNewChat() {
        chat.startNewChat()
        // A fresh conversation, not a fresh root: whatever opened chat is still behind it.
        palette.replace(mode: .ai)
    }

    func showHistory() {
        palette.push(mode: .aiHistory)
    }

    /// A chat the window holds opens there, since two writers would each save over the other.
    func openChat(id: UUID) {
        guard chats.openInQuickAI(id: id) else {
            paletteCoordinator.hidePalette(restoreFocus: false)
            chatCoordinator.openChat(id: id)
            chatCoordinator.showWindow()
            return
        }
        // History is left behind rather than stacked under, so one back step leaves chat for good.
        _ = palette.pop()
        palette.replace(mode: .ai)
    }

    func deleteChat(id: UUID) {
        chats.delete(id: id)
    }

    func deleteAllChats() async {
        await chatCoordinator.deleteAllChats()
    }

    /// The window takes the conversation over; the palette closes behind it, as Settings' does.
    func continueInChat() {
        let draft = palette.query
        palette.query = ""
        paletteCoordinator.hidePalette(restoreFocus: false)
        chatCoordinator.continueInWindow(draft: draft)
    }

    func stopResponse() {
        chatCoordinator.stopResponse(in: chat)
    }

    func copyLastResponse() {
        chatCoordinator.copyLastResponse(in: chat)
    }

    /// Backspace on an empty composer takes the last staged image before it backs out of chat.
    func removeLastAttachment() -> Bool {
        chat.removeLastAttachment()
    }

    func clearAttachments() {
        chat.clearAttachments()
    }

    func removeAttachment(_ id: UUID) {
        chat.removeAttachment(id)
    }
}
