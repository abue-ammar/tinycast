import SwiftUI

/// Local conversations: search summaries, preview one, then explicitly open it as the active chat.
struct ChatHistoryScreen: PaletteScreen {
    let history: ChatHistoryStore
    let chat: AIChatState
    let coordinator: AIChatCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [ChatConversation] { history.search(vm.query) }
    let primaryActionTitle = String(localized: "Open Chat", bundle: .appLanguage)

    private func conversation(at selection: Int) -> ChatConversation? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let conversation = conversation(at: selection) else { return nil }
        return ChatHistoryActionsMenu.content(
            conversation: conversation, coordinator: coordinator)
    }

    func activate(at selection: Int) {
        guard let conversation = conversation(at: selection) else { return }
        coordinator.openChat(id: conversation.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    func delete(at selection: Int) {
        guard let conversation = conversation(at: selection) else { return }
        coordinator.deleteChat(id: conversation.id)
    }

    func deleteAll() {
        Task { await coordinator.deleteAllChats() }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: history.isAvailable
                    ? history.conversations.isEmpty ? String(
                        localized: "No chats yet",
                        bundle: .appLanguage) : "No matching chats"
                    : String(localized: "Chat history is unavailable", bundle: .appLanguage))
        } else {
            let selected = conversation(at: selection)
            HStack(spacing: 0) {
                ChatHistoryList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { conversation in
                        vm.selection = rows.firstIndex(of: conversation) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { conversation in
                        if let index = rows.firstIndex(of: conversation) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: Theme.Size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                ChatHistoryPreview(history: history, chat: chat, conversationID: selected?.id)
            }
        }
    }
}

@MainActor
enum ChatHistoryActionsMenu {
    static func content(
        conversation: ChatConversation, coordinator: AIChatCoordinator
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: conversation.title,
            items: [
                PopoverMenuItem(
                    title: String(
                        localized: "Open Chat",
                        bundle: .appLanguage), systemImage: "bubble.left.and.bubble.right", shortcut: "↵"
                ) {
                    coordinator.openChat(id: conversation.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Delete Chat", bundle: .appLanguage), systemImage: "trash", shortcut: "⌃X",
                    isDestructive: true
                ) {
                    coordinator.deleteChat(id: conversation.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Delete All Chats", bundle: .appLanguage), systemImage: "trash", shortcut: "⌃⇧X",
                    isDestructive: true
                ) {
                    Task { await coordinator.deleteAllChats() }
                }
            ])
    }
}
