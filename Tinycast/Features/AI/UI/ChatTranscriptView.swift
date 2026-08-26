import SwiftUI

struct ChatTranscriptView: View {
    let messages: [ChatMessage]
    let status: String?
    let usage: AIUsage?

    @State private var followsTail = true

    /// Below this velocity, a scroll toward the top is treated as the user wanting to stay put;
    /// anything gentler might just be a finger lifting off a wheel.
    private static let deliberateScroll: CGFloat = 8

    /// Merges intermediate assistant chunks and tool turns into clean assistant messages for display.
    private var displayMessages: [ChatMessage] {
        var result: [ChatMessage] = []
        var currentAssistantTurn: ChatMessage?

        for message in messages {
            if message.role == .tool {
                continue
            }
            if message.role == .user {
                if let turn = currentAssistantTurn {
                    result.append(turn)
                    currentAssistantTurn = nil
                }
                result.append(message)
            } else if message.role == .assistant {
                if var turn = currentAssistantTurn {
                    for search in message.searches {
                        if let index = turn.searches.firstIndex(where: { $0.query == search.query }) {
                            turn.searches[index] = search
                        } else {
                            turn.searches.append(search)
                        }
                    }
                    if !message.text.isEmpty {
                        turn.text = message.text
                    }
                    turn.state = message.state
                    currentAssistantTurn = turn
                } else {
                    currentAssistantTurn = message
                }
            }
        }
        if let turn = currentAssistantTurn {
            result.append(turn)
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: a transcript is a few tall rows, and an estimated height is what every
                // anchored jump and the end test are measured against.
                VStack(spacing: Theme.Spacing.xl) {
                    ForEach(displayMessages) { message in
                        ChatMessageView(
                            message: message,
                            status: message.id == displayMessages.last?.id ? status : nil
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
                    // The offset rests at `-insetTop`, so the end sits that much past a raw
                    // offset plus the band — without it the true bottom never reads as the end.
                    atEnd: geometry.contentOffset.y + geometry.containerSize.height
                        + geometry.contentInsets.top
                        >= geometry.contentSize.height - Theme.Spacing.chatFollowTailSlack)
            } action: { old, new in
                // A plain wheel reports no ScrollPhase, so the offset is the only signal every
                // input device gives. Reaching the end is tested first and wins: a wheel settling
                // back a pixel off the end would otherwise hand control straight back again.
                if new.atEnd {
                    followsTail = true
                } else if new.offset < old.offset - Self.deliberateScroll {
                    followsTail = false
                }
            }
            .onChange(of: messages.count) { follow(proxy, always: true) }
            .onChange(of: messages) { follow(proxy, always: false) }
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

/// A fast reply grows the transcript quicker than a reader can scroll toward it, so arriving at
/// the end cannot be the only way to resume: this asks for the tail rather than chasing it.
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

    /// Laid out at rest and only faded in, so a hover can't reflow the transcript under the pointer.
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
                // Only the user bubble is inset: it carries a fill. A reply's `sm` is just enough
                // to put its first pixel under the header's back chevron.
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
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !message.searches.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(Array(message.searches.enumerated()), id: \.offset) { _, search in
                            ChatSearchRow(search: search)
                        }
                    }
                }
                if !message.text.isEmpty {
                    MarkdownView(blocks: MarkdownBlock.parse(message.text))
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
                    .scaledToFill()
            } else {
                Theme.Colors.controlSurface
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Colors.border)
        )
        .task(id: image) { decoded = NSImage(data: image.data) }
    }
}

/// A tool execution inside a reply: live while it runs, a record of what it looked up once done.
private struct ChatSearchRow: View {
    let search: ChatSearch

    private enum ToolKind {
        case weather(String)
        case location
        case calculate(String)
        case webpage(String)
        case webSearch(String)
    }

    private var toolKind: ToolKind {
        let raw = search.query ?? ""
        if raw.hasPrefix("weather:") {
            let loc = String(raw.dropFirst("weather:".count)).trimmingCharacters(in: .whitespaces)
            return .weather(loc.isEmpty ? "Current location" : loc)
        } else if raw.hasPrefix("loc:") || raw == "location" {
            return .location
        } else if raw.hasPrefix("calc:") {
            let expr = String(raw.dropFirst("calc:".count)).trimmingCharacters(in: .whitespaces)
            return .calculate(expr)
        } else if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            let host = URL(string: raw)?.host?.replacingOccurrences(of: "www.", with: "") ?? raw
            return .webpage(host)
        } else {
            return .webSearch(raw)
        }
    }

    var body: some View {
        let (icon, label, detail): (String, String, String) = {
            switch toolKind {
            case .weather(let place):
                let title = search.isComplete ? "Checked weather" : "Checking weather"
                return ("cloud.sun", title, place)
            case .location:
                let title = search.isComplete ? "Located" : "Locating"
                return ("location", title, "Current location")
            case .calculate(let expr):
                let title = search.isComplete ? "Calculated" : "Calculating"
                return ("function", title, expr)
            case .webpage(let host):
                let title = search.isComplete ? "Read webpage" : "Reading webpage"
                return ("doc.text", title, host)
            case .webSearch(let query):
                let title = search.isComplete ? "Searched web" : "Searching web"
                return ("globe", title, query)
            }
        }()

        HStack(spacing: Theme.Spacing.sm) {
            if search.isComplete {
                Image(systemName: icon)
                    .font(Theme.Typography.rowTrailing)
                    .symbolRenderingMode(.hierarchical)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(label)
                .font(Theme.Typography.rowTrailing)
            if !detail.isEmpty {
                Text("· \(detail)")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .animation(.easeOut(duration: Theme.Duration.chatFooter), value: search.isComplete)
    }
}

private struct ScrollMark: Equatable {
    let offset: CGFloat
    let atEnd: Bool
}
