import SwiftUI

struct ChatHistoryList: View {
    @Environment(\.locale) private var localizationLocale
    let results: [ChatConversation]
    let selectedID: ChatConversation.ID?
    let scroll: ScrollIntent
    let onSelect: (ChatConversation) -> Void
    let onActivate: () -> Void
    let onActions: (ChatConversation) -> Void

    private enum Row: Identifiable {
        case header(String)
        case conversation(ChatConversation)

        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .conversation(let conversation): return conversation.id.uuidString
            }
        }
    }

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var currentBucket: DateBucket?
        for conversation in results {
            let bucket = DateBucket(for: conversation.updatedAt)
            if bucket != currentBucket {
                rows.append(.header(bucket.title))
                currentBucket = bucket
            }
            rows.append(.conversation(conversation))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .conversation(let conversation):
                            ChatHistoryRow(
                                conversation: conversation,
                                selected: conversation.id == selectedID
                            )
                            .selectionFrame(conversation.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(conversation) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(conversation)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(conversation) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            // Snap to the origin on the first row so its section header shows too.
            .scrollFollowsSelection(
                scroll, row: selectedID?.uuidString, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct ChatHistoryRow: View {
    @Environment(\.locale) private var localizationLocale
    let conversation: ChatConversation
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                .fill(Theme.Colors.controlSurface)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(conversation.title)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                if !conversation.preview.isEmpty {
                    Text(conversation.preview)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

struct ChatHistoryPreview: View {
    let history: ChatHistoryStore
    let chat: AIChatState
    let conversationID: UUID?
    @State private var session: ChatSession?

    var body: some View {
        Group {
            if conversationID == chat.session.id, !chat.session.messages.isEmpty {
                ChatTranscriptView(
                    messages: chat.session.messages, status: chat.liveStatus, usage: chat.usage)
            } else if let session {
                ChatTranscriptView(messages: session.messages, status: nil, usage: nil)
            } else if conversationID != nil {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .task(id: conversationID) {
            session = nil
            guard let conversationID else { return }
            guard conversationID != chat.session.id || chat.session.messages.isEmpty else { return }
            session = history.session(id: conversationID)
        }
    }
}
