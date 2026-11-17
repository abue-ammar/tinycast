import Foundation

/// A chat as it travels to another Mac: everything but attachments, which stay where added.
struct ChatSyncPayload: Codable, Sendable {
    struct Message: Codable, Sendable {
        let id: UUID
        let role: ChatMessage.Role
        let text: String
        let state: ChatMessage.State
        let sentAt: Date
        let searches: [ChatSearch]
        let toolUses: [ChatToolUse]
        let reasoning: [ChatReasoning]
        let usage: AIUsage?
        let toolScope: String?
    }

    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let messages: [Message]
    let model: AIModelSelection?
    let preset: ChatPreset.Stamp?
    let customTitle: String?
    let generatedTitle: String?
    let isPinned: Bool

    init(session: ChatSession, conversation: ChatConversation) {
        id = session.id
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        messages = session.messages.map { message in
            Message(
                id: message.id, role: message.role, text: message.text, state: message.state,
                sentAt: message.sentAt, searches: message.searches, toolUses: message.toolUses,
                reasoning: message.reasoning, usage: message.usage, toolScope: message.toolScope)
        }
        model = session.model
        preset = session.preset
        customTitle = conversation.customTitle
        generatedTitle = conversation.generatedTitle
        isPinned = conversation.isPinned
    }

    /// Rebuilt over this Mac's copy, so an image or document added here is kept with its message.
    func session(keepingAttachmentsOf local: ChatSession?) -> ChatSession {
        let attachments = Dictionary(
            (local?.messages ?? []).map { ($0.id, ($0.images, $0.documents)) },
            uniquingKeysWith: { first, _ in first })
        return ChatSession(
            id: id, createdAt: createdAt, updatedAt: updatedAt,
            messages: messages.map { message in
                ChatMessage(
                    id: message.id, role: message.role, text: message.text, state: message.state,
                    sentAt: message.sentAt, images: attachments[message.id]?.0 ?? [],
                    documents: attachments[message.id]?.1 ?? [], searches: message.searches,
                    toolUses: message.toolUses, reasoning: message.reasoning, usage: message.usage,
                    toolScope: message.toolScope)
            },
            model: model, preset: preset)
    }
}
