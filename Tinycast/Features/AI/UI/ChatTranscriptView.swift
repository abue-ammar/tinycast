import AppKit
import SwiftUI

struct ChatTranscriptView: View {
    let messages: [ChatMessage]
    let status: String?
    let usage: AIUsage?
    /// Cleared when the reader scrolls up, so a streaming reply stops dragging them back down.
    @State private var followsTail = true

    /// Below this a backward move is momentum settling, not the reader asking for the wheel.
    private static let deliberateScroll: CGFloat = 2

    /// Where the reader sits and whether that is the end; a growing reply moves the end on its own.
    private struct ScrollMark: Equatable {
        var offset: CGFloat
        var atEnd: Bool
    }

    private var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .tool && (!$0.text.isEmpty || !$0.images.isEmpty || $0.state == .streaming) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: every anchored jump and the end test measure an estimated height
                VStack(spacing: Theme.Spacing.xl) {
                    ForEach(visibleMessages) { message in
                        ChatMessageView(
                            message: message,
                            status: message.id == visibleMessages.last?.id ? status : nil
                        )
                        .id(message.id)
                    }
                    if let total = usage?.totalTokens {
                        Text("\(total.formatted()) tokens")
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Color.clear
                        .frame(height: Theme.Spacing.xxs)
                        .id("ai-transcript-tail")
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.chatTranscriptBottom)
            }
            .edgeDissolve()
            .thinScrollbar()
            // Reopened chats start at the latest message; other anchor roles fight the reader.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: ScrollMark.self) { geometry in
                ScrollMark(
                    offset: geometry.contentOffset.y,
                    // The offset rests at `-insetTop`, so the end is that far past offset plus band
                    atEnd: geometry.contentOffset.y + geometry.containerSize.height
                        + geometry.contentInsets.top
                        >= geometry.contentSize.height - Theme.Spacing.chatFollowTailSlack)
            } action: { old, new in
                // The offset is the only signal every device gives; the end wins, tested first
                if new.atEnd {
                    followsTail = true
                } else if new.offset < old.offset - Self.deliberateScroll {
                    followsTail = false
                }
            }
            .onChange(of: visibleMessages.count) { follow(proxy, always: true) }
            .onChange(of: visibleMessages) { follow(proxy, always: false) }
            .onChange(of: usage) { follow(proxy, always: false) }
            .overlay(alignment: .bottom) {
                ResumeFollowingButton {
                    followsTail = true
                    follow(proxy, always: true)
                }
                .padding(.bottom, Theme.Spacing.lg)
                .opacity(followsTail ? 0 : 1)
                .allowsHitTesting(!followsTail)
                .animation(.easeOut(duration: Theme.Duration.chatFooter), value: followsTail)
            }
        }
    }

    /// A sent message always comes into view; a growing reply only while the reader is at the end.
    private func follow(_ proxy: ScrollViewProxy, always: Bool) {
        guard always || followsTail else { return }
        proxy.scrollTo("ai-transcript-tail", anchor: .bottom)
    }
}

/// A fast reply outruns a reader scrolling toward it, so this asks for the tail, not chases it.
private struct ResumeFollowingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Jump to Latest", systemImage: "arrow.down")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Colors.border))
        }
        .buttonStyle(.plain)
    }
}

private struct ChatMessageView: View {
    let message: ChatMessage
    let status: String?

    @State private var hovered = false

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: Theme.Spacing.xxl) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.xxs) {
                content
                if message.state != .streaming { footer }
            }
            .contentShape(Rectangle())
            .onHover { isHovered in
                if isHovered {
                    withAnimation(.easeOut(duration: Theme.Duration.chatFooter)) {
                        hovered = true
                    }
                } else {
                    hovered = false
                }
            }
            if message.role == .assistant { Spacer(minLength: Theme.Spacing.xxl) }
        }
    }

    /// Laid out at rest and only faded in, so a hover cannot reflow the transcript
    private var footer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if message.role == .user { timestamp }
            ChatCopyButton(text: message.text)
            if message.role == .assistant { timestamp }
        }
        .opacity(hovered ? 1 : 0)
        // A reply's footer hugs the same `sm` edge as its text.
        .padding(.horizontal, message.role == .user ? Theme.Spacing.md : Theme.Spacing.sm)
    }

    private var timestamp: some View {
        Text(message.sentAt.formatted(date: .omitted, time: .shortened))
            .font(Theme.Typography.keyCap)
            .foregroundStyle(Theme.Colors.textTertiary)
    }

    @ViewBuilder private var content: some View {
        if message.text.isEmpty, message.searches.isEmpty, message.state == .streaming {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                if let status { Text(status).foregroundStyle(.secondary) }
            }
            .padding(Theme.Spacing.md)
        } else {
            bubbleContent
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(message.state == .failed ? Theme.Colors.destructive : .primary)
                .textSelection(.enabled)
                // The user bubble is inset because it carries a fill; a reply clears the chevron
                .padding(.horizontal, message.role == .user ? Theme.Spacing.xl : Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(message.role == .user ? Theme.Colors.controlSurface : Color.clear)
                )
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.sm) {
            if !message.images.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(message.images, id: \.self) { image in
                        ChatImageThumbnail(image: image, edge: Theme.Size.chatImageThumb)
                    }
                }
            }
            if !message.text.isEmpty || !message.searches.isEmpty { rendered }
        }
    }

    /// Only a reply is markdown — what the user typed is shown back exactly as they typed it.
    @ViewBuilder private var rendered: some View {
        if message.role == .assistant {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(Array(message.segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        MarkdownView(blocks: MarkdownBlock.parse(text))
                    case .search(let search):
                        ChatSearchRow(search: search)
                    }
                }
            }
        } else {
            Text(message.text)
        }
    }
}

/// Decoded once per image off the render path; a streaming transcript re-renders every flush.
struct ChatImageThumbnail: View {
    let image: AIImage
    let edge: CGFloat
    @State private var decoded: NSImage?

    var body: some View {
        Group {
            if let decoded {
                Image(nsImage: decoded)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .task(id: image) { decoded = NSImage(data: image.data) }
    }
}

/// A web search or tool execution inside a reply: live while it runs, a record of what it looked up once done.
private struct ChatSearchRow: View {
    let search: ChatSearch

    private var iconName: String {
        guard let query = search.query?.lowercased() else { return "globe" }
        if query.hasPrefix("calc:") { return "function" }
        if query.hasPrefix("weather:") { return "cloud.sun" }
        if query.hasPrefix("location:") { return "location" }
        if query.hasPrefix("fetch:") || query.hasPrefix("http") { return "doc.text" }
        return "globe"
    }

    private var displayTitle: String {
        guard let raw = search.query else {
            return search.isComplete ? "Searched web" : "Searching web"
        }
        if raw.hasPrefix("calc:") {
            return search.isComplete ? "Calculated" : "Calculating"
        }
        if raw.hasPrefix("weather:") {
            return search.isComplete ? "Checked weather" : "Checking weather"
        }
        if raw.hasPrefix("location:") {
            return search.isComplete ? "Checked location" : "Finding location"
        }
        if raw.hasPrefix("fetch:") {
            return search.isComplete ? "Fetched page" : "Fetching page"
        }
        return search.isComplete ? "Searched web" : "Searching web"
    }

    private var displayQuery: String? {
        guard let raw = search.query else { return nil }
        if let colonIndex = raw.firstIndex(of: ":") {
            let after = String(raw[raw.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            return after.isEmpty ? nil : after
        }
        return raw.isEmpty ? nil : raw
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if search.isComplete {
                Image(systemName: iconName)
                    .font(Theme.Typography.rowTrailing)
                    .symbolRenderingMode(.hierarchical)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(displayTitle)
                .font(Theme.Typography.rowTrailing)
            if let query = displayQuery {
                Text("· \(query)")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .animation(.easeOut(duration: Theme.Duration.chatFooter), value: search.isComplete)
    }
}
