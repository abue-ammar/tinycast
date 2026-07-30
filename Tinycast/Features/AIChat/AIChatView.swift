import SwiftUI

struct AIChatView: View {
    @EnvironmentObject private var aiStore: AIStore
    @EnvironmentObject private var vm: PaletteViewModel
    @State private var scrollToken = UUID()

    var body: some View {
        if !aiStore.isEnabled {
            EmptyResults(text: "AI Chat is disabled. Enable it in Settings.")
        } else if aiStore.messages.isEmpty && aiStore.streamingText.isEmpty {
            EmptyResults(text: "Start a conversation by typing below")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        ForEach(aiStore.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }

                        if !aiStore.streamingText.isEmpty {
                            MessageRow(
                                message: AIMessage(
                                    role: .assistant, content: aiStore.streamingText))
                                .id("streaming")
                        }

                        if aiStore.isLoading && aiStore.streamingText.isEmpty {
                            LoadingIndicator()
                                .id("loading")
                        }

                        if let error = aiStore.lastError {
                            ErrorCard(message: error)
                                .id("error")
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md * 2)
                    .padding(.vertical, Theme.Spacing.lg)
                    .hideNativeScrollers()
                }
                .thinScrollbar()
                .edgeDissolve()
                .onChange(of: aiStore.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: aiStore.streamingText) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: scrollToken) { _, _ in
                    scrollToBottom(proxy)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if !aiStore.streamingText.isEmpty {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let last = aiStore.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

private struct MessageRow: View {
    let message: AIMessage
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            // Icon
            Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
                .font(.system(size: 20))
                .foregroundStyle(message.role == .user ? .secondary : .primary)
                .frame(width: Theme.Size.rowIcon)

            // Content
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(Theme.Typography.rowTitle.weight(.medium))
                    .foregroundStyle(.primary)

                Text(message.content)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : Color.clear)
        )
        .onHover { hovered = $0 }
    }
}

private struct LoadingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .onAppear { isAnimating = true }
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)

            Text(message)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}
