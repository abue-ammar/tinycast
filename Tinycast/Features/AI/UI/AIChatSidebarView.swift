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
        for conversation in results where !conversation.isPinned {
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
        let answering = chats.answeringIDs
        let openID = chats.window.session.id
        if sections.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: selection) {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.conversations) { conversation in
                            row(
                                conversation, isAnswering: answering.contains(conversation.id),
                                isSelected: conversation.id == openID
                            )
                            .tag(conversation.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: UUID.self) { ids in
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

    @ViewBuilder private func row(
        _ conversation: ChatConversation, isAnswering: Bool, isSelected: Bool
    ) -> some View {
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
            ChatSidebarRow(
                conversation: conversation, isAnswering: isAnswering, isSelected: isSelected)
        }
    }

    @ViewBuilder private func menu(for conversation: ChatConversation) -> some View {
        Button(
            conversation.isPinned ? "Unpin Chat" : "Pin Chat",
            systemImage: conversation.isPinned ? "pin.slash" : "pin"
        ) {
            coordinator.togglePin(id: conversation.id)
        }
        Button("Rename…", systemImage: "pencil") { beginRename(conversation) }
        Divider()
        Button("Copy Chat", systemImage: "doc.on.doc") { coordinator.copyChat(id: conversation.id) }
        Button("Export as Markdown…", systemImage: "square.and.arrow.up") {
            coordinator.exportChat(id: conversation.id)
        }
        Divider()
        Button("Delete Chat…", systemImage: "trash", role: .destructive) {
            Task { await coordinator.deleteChat(id: conversation.id) }
        }
        Button("Delete All Chats…", systemImage: "trash.slash", role: .destructive) {
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

    /// The open chat is the selected row; a new one has no row until its first message.
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

/// A chat's title, then a spinner while it answers or a pin; hover is a fainter selection.
private struct ChatSidebarRow: View {
    let conversation: ChatConversation
    let isAnswering: Bool
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(conversation.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isAnswering {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Answering")
            } else if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Pinned")
            }
        }
        // The whole cell, so the pointer never crosses a gap where no row is hovered.
        .frame(maxHeight: .infinity)
        .listRowInsets(EdgeInsets())
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .listRowBackground(hoverFill)
        .help(conversation.displayTitle)
    }

    /// Inset and rounded as the system's selection is, so the two read as one shape.
    @ViewBuilder private var hoverFill: some View {
        if isHovered, !isSelected {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Colors.rowHover)
                .padding(.horizontal, Theme.Spacing.lg)
        }
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
