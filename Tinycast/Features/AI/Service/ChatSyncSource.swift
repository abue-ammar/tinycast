import Foundation

/// Chats by UUID while AI is on; off, the history isn't opened, so arrivals wait for it.
@MainActor
final class ChatSyncSource: SyncSource {
    let id = SyncSourceID.chats
    private let store: ChatHistoryStore
    private let isActive: () -> Bool
    /// A reply still arriving reads back as interrupted, so its chat travels once it has finished.
    private let answering: () -> Set<UUID>

    init(store: ChatHistoryStore, isActive: @escaping () -> Bool, answering: @escaping () -> Set<UUID>) {
        self.store = store
        self.isActive = isActive
        self.answering = answering
    }

    func observe() {
        _ = isActive()
        _ = store.conversations
    }

    func snapshot() async -> [String: String]? {
        guard isActive(), store.isAvailable else { return nil }
        return Dictionary(
            uniqueKeysWithValues: store.conversations.map { (Self.key($0.id), Self.version(of: $0)) })
    }

    func payload(for key: String) async -> Data? {
        guard
            isActive(), let id = UUID(uuidString: key), !answering().contains(id),
            let conversation = store.conversation(id: id), let session = store.session(id: id)
        else { return nil }
        return SyncPayload.encode(ChatSyncPayload(session: session, conversation: conversation))
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        guard isActive() else { return Set(changes.upserts.keys).union(changes.deletions) }
        for key in changes.deletions {
            if let id = UUID(uuidString: key) { store.remove(id: id) }
        }
        var deferred: Set<String> = []
        for (key, payload) in changes.upserts {
            guard let chat = SyncPayload.decode(ChatSyncPayload.self, from: payload) else { continue }
            if !store.applySynced(chat) { deferred.insert(key) }
        }
        return deferred
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    /// Cheap to read for thousands of chats: the summary moves whenever the chat does.
    private static func version(of chat: ChatConversation) -> String {
        let fields: [String] = [
            "\(chat.updatedAt.timeIntervalSinceReferenceDate)", "\(chat.messageCount)",
            chat.customTitle ?? "", chat.generatedTitle ?? "", "\(chat.isPinned)"
        ]
        return SyncVersion.of(Data(fields.joined(separator: "\u{0}").utf8))
    }
}
