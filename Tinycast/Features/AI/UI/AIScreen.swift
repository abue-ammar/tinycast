import SwiftUI

/// AI chat as one native palette screen: the search field is its composer.
struct AIScreen: PaletteScreen {
    let vm: PaletteState
    let chat: AIChatState
    let settings: AISettingsStore
    let coordinator: AIChatCoordinator

    struct Row: Identifiable {
        let id = "ai-chat"
    }

    let rows = [Row()]

    /// One footer pill for Return's two jobs: Send, or Stop while a response streams.
    var primaryActionTitle: String { chat.isStreaming ? "Stop" : "Send" }

    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []
        if chat.isStreaming {
            items.append(
                PopoverMenuItem(title: "Stop Response", systemImage: "stop.fill") {
                    coordinator.stopResponse()
                })
        }
        items.append(
            PopoverMenuItem(title: "New Chat", systemImage: "plus.bubble") {
                coordinator.startNewChat()
            })
        if chat.lastAssistantText != nil {
            items.append(
                PopoverMenuItem(title: "Copy Last Response", systemImage: "doc.on.doc") {
                    coordinator.copyLastResponse()
                })
        }
        if !chat.pendingImages.isEmpty {
            items.append(
                PopoverMenuItem(title: "Remove Attachments", systemImage: "photo.badge.minus") {
                    coordinator.clearAttachments()
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Chat History", systemImage: "clock.arrow.circlepath"
            ) {
                coordinator.showHistory()
            })
        items.append(
            PopoverMenuItem(title: "AI Settings", systemImage: "slider.horizontal.3") {
                coordinator.showSettings()
            })
        return PopoverMenuContent(header: chat.session.title, items: items)
    }

    /// Return and the pill are the same action; an empty composer sends nothing.
    func activate(at selection: Int) {
        if chat.isStreaming {
            coordinator.stopResponse()
        } else if coordinator.send(vm.query) {
            vm.query = ""
        }
    }

    func secondary(at selection: Int) -> Bool { false }

    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        let attachments = chat.pendingImages
        let addressed = coordinator.addressedServer(in: vm.query)
        guard !attachments.isEmpty || addressed != nil else { return nil }
        let width =
            PendingAttachmentsChips.width(for: attachments)
            + (addressed.map { ComposerChip.width(of: "@\($0.slug)") } ?? 0)
        return PaletteHeaderAccessory(
            width: width + Theme.Size.menuWidth,
            fieldNames: [], firstIncompleteField: nil,
            view: AnyView(
                HStack(spacing: Theme.Spacing.sm) {
                    if let addressed {
                        ComposerChip(symbol: "wrench.and.screwdriver", label: "@\(addressed.slug)")
                    }
                    PendingAttachmentsChips(attachments: attachments)
                }))
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            AIChatView(
                chat: chat, settings: settings, availability: coordinator.availability,
                onConfigure: coordinator.showSettings, onAppear: coordinator.prepareForChat))
    }
}

private struct AIChatView: View {
    let chat: AIChatState
    let settings: AISettingsStore
    let availability: () -> String?
    let onConfigure: () -> Void
    let onAppear: () -> Void
    @State private var unavailability: String?

    var body: some View {
        Group {
            if chat.session.messages.isEmpty {
                AIEmptyState(
                    message: chat.notice ?? unavailability,
                    canConfigure: chat.notice != nil || unavailability != nil,
                    onConfigure: onConfigure)
            } else {
                ChatTranscriptView(
                    messages: chat.session.messages,
                    status: chat.liveStatus,
                    usage: chat.usage)
            }
        }
        .onAppear {
            unavailability = availability()
            onAppear()
        }
        .onChange(of: settings.defaultModel) { unavailability = availability() }
    }
}

private struct AIEmptyState: View {
    let message: String?
    let canConfigure: Bool
    let onConfigure: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text("Ask anything")
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                if canConfigure { Button("Configure AI", action: onConfigure) }
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Send a message")
                    KeyCapChip(text: "↵")
                }
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Spacing.xxl)
    }
}

/// One pill beside the composer; the row is too thin for anything but a glyph and a word.
private struct ComposerChip: View {
    let symbol: String
    let label: String

    static func width(of label: String) -> CGFloat {
        let font = Theme.Typography.chipNSFont
        let text = (label as NSString).size(withAttributes: [.font: font]).width
        return Theme.Size.chatAttachmentGlyph + text + Theme.Spacing.md * 3
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(Theme.Typography.chip)
                .symbolRenderingMode(.hierarchical)
                .frame(width: Theme.Size.chatAttachmentGlyph)
            Text(label)
                .font(Theme.Typography.chip)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Capsule().fill(Theme.Colors.controlSurface))
    }
}

/// Staged images sit after the typed text as named pills; the row is too thin for a thumbnail.
private struct PendingAttachmentsChips: View {
    let attachments: [ChatAttachment]

    static func width(for attachments: [ChatAttachment]) -> CGFloat {
        attachments.reduce(0) { $0 + ComposerChip.width(of: $1.name) }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(attachments) { attachment in
                ComposerChip(symbol: "photo", label: attachment.name)
            }
        }
    }
}

/// The chat header's model control, sharing the clipboard filter's menu-button chrome.
struct AIModelButton: View {
    let title: String
    let icon: PopoverMenuIcon
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        HeaderMenuButton(
            title: title,
            icon: icon,
            isOpen: isOpen,
            help: "Switch AI model",
            action: action
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}
