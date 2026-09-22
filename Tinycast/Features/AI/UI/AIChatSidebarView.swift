import SwiftUI

/// Every saved conversation, pinned first and then by day; selecting one opens it on the right.
struct AIChatSidebarView: View {
    @Environment(AIChatCoordinator.self) private var coordinator
    @State private var query = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var renameFocused: Bool

    private var chats: AIChatSurfacesState { coordinator.chats }
    private var history: ChatHistoryStore { coordinator.history }

    private struct ChatSection: Identifiable {
        let title: String
        var conversations: [ChatConversation]
        var id: String { title }
    }

    /// Recency order already groups each day together, so a bucket only ever opens once.
    private var sections: [ChatSection] {
        let results = history.search(query)
        var sections: [ChatSection] = []
        let pinned = results.filter(\.isPinned)
        if !pinned.isEmpty { sections.append(ChatSection(title: "Pinned", conversations: pinned)) }
        var unpinned = results.filter { !$0.isPinned }
        if let draft { unpinned.insert(draft, at: 0) }
        for conversation in unpinned {
            let title = DateBucket(for: conversation.updatedAt).title
            if sections.last?.title == title {
                sections[sections.count - 1].conversations.append(conversation)
            } else {
                sections.append(ChatSection(title: title, conversations: [conversation]))
            }
        }
        return sections
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatSearchField(query: $query, focused: $searchFocused)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            list
        }
        // The field sits under the toolbar's material, so it needs its own clearance from the top.
        .padding(.top, Theme.Spacing.md)
        .onExitCommand { query = "" }
    }

    @ViewBuilder private var list: some View {
        let sections = sections
        if sections.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: selection) {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.conversations) { conversation in
                            row(conversation).tag(conversation.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: UUID.self) { ids in
                // The unsaved new chat has nothing to pin, rename, copy or delete yet.
                if let id = ids.first, let conversation = history.conversation(id: id) {
                    menu(for: conversation)
                }
            }
            .onDeleteCommand {
                guard let id = selection.wrappedValue, history.conversation(id: id) != nil
                else { return }
                Task { await coordinator.deleteChat(id: id) }
            }
        }
    }

    /// The open chat before its first message: unsaved, yet it is where you are, so it has a row.
    private var draft: ChatConversation? {
        let session = chats.window.session
        guard query.isEmpty, history.conversation(id: session.id) == nil else { return nil }
        return ChatConversation(
            id: session.id, title: "New Chat", preview: "", createdAt: session.createdAt,
            updatedAt: Date(), messageCount: 0)
    }

    @ViewBuilder private var emptyState: some View {
        if !history.isAvailable {
            ContentUnavailableView(
                "History Unavailable", systemImage: "exclamationmark.triangle",
                description: Text("Chats can't be saved on this Mac right now."))
        } else if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView(
                "No Chats Yet", systemImage: "bubble.left.and.bubble.right",
                description: Text("Conversations stay on this Mac."))
        }
    }

    @ViewBuilder private func row(_ conversation: ChatConversation) -> some View {
        if renaming == conversation.id {
            TextField("Chat name", text: $renameText, prompt: Text(conversation.title))
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commitRename(conversation.id) }
                .onExitCommand { renaming = nil }
                .onChange(of: renameFocused) { _, focused in
                    if !focused { commitRename(conversation.id) }
                }
        } else {
            HStack(spacing: Theme.Spacing.sm) {
                Text(conversation.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if chats.answeringIDs.contains(conversation.id) {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Answering")
                }
            }
            .help(conversation.displayTitle)
        }
    }

    @ViewBuilder private func menu(for conversation: ChatConversation) -> some View {
        Button(conversation.isPinned ? "Unpin" : "Pin") {
            coordinator.togglePin(id: conversation.id)
        }
        Button("Rename…") { beginRename(conversation) }
        Button("Copy Chat") { coordinator.copyChat(id: conversation.id) }
        Divider()
        Button("Delete Chat…", role: .destructive) {
            Task { await coordinator.deleteChat(id: conversation.id) }
        }
        Button("Delete All Chats…", role: .destructive) {
            Task { await coordinator.deleteAllChats() }
        }
    }

    private func beginRename(_ conversation: ChatConversation) {
        renameText = conversation.customTitle ?? ""
        renaming = conversation.id
        Task { @MainActor in renameFocused = true }
    }

    private func commitRename(_ id: UUID) {
        guard renaming == id else { return }
        renaming = nil
        coordinator.rename(id: id, to: renameText)
    }

    /// The open chat is always the selected row, the unsaved new one included.
    private var selection: Binding<UUID?> {
        Binding(
            get: { chats.window.session.id },
            set: { id in
                guard let id, id != chats.window.session.id else { return }
                coordinator.openChat(id: id)
            }
        )
    }

}

/// The sidebar's search field, drawn the way Settings' own is so the two windows match.
private struct ChatSearchField: View {
    @Binding var query: String
    @FocusState.Binding var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text("Search"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($focused)
                .pointerStyle(.horizontalText)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Size.aiChatSearchField)
        .background { Color.clear.frosted(in: Capsule()) }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .accessibilityLabel("Search chats")
    }
}
