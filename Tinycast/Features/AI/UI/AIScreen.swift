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
        if !chat.pendingAttachments.isEmpty {
            items.append(
                PopoverMenuItem(title: "Remove Attachments", systemImage: "paperclip") {
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
        let attachments = chat.pendingAttachments
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
                    PendingAttachmentsChips(
                        attachments: attachments,
                        onRemove: coordinator.removeAttachment)
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

/// The MCP `@server` pill: a glyph and a word, unchanged by what attachments do.
private struct ComposerChip: View {
    let symbol: String
    let label: String

    /// Load-bearing: `RootPaletteView.searchFieldWidth(for:)` shrinks the field by exactly this.
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

/// A staged file: an image states itself, a document names itself, and either can be taken back.
private struct AttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    @State private var hovered = false

    /// A long file name is middle-truncated here rather than by layout, so the width is knowable.
    private static let nameLimit = 16

    /// Every kind is labelled: a bare thumbnail beside an ✕ reads as two stray marks, not a pill.
    private static func shortened(_ name: String) -> String {
        guard name.count > nameLimit else { return name }
        let head = name.prefix(nameLimit - 7)
        let tail = name.suffix(6)
        return "\(head)…\(tail)"
    }

    static func width(for attachment: ChatAttachment) -> CGFloat {
        let text = (Self.shortened(attachment.name) as NSString).size(
            withAttributes: [.font: Theme.Typography.chipNSFont]
        ).width
        return Theme.Size.chatAttachmentInset * 2 + Theme.Size.chatAttachmentThumb
            + Theme.Spacing.sm + text + Theme.Spacing.sm + Theme.Size.chatAttachmentRemove
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            leading
            Text(Self.shortened(attachment.name))
                .font(Theme.Typography.chip)
                .lineLimit(1)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(
                        width: Theme.Size.chatAttachmentRemove,
                        height: Theme.Size.chatAttachmentRemove
                    )
                    .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(attachment.name)")
        }
        // Inset under the inner gap, so the thumbnail reads as filling the pill.
        .padding(.horizontal, Theme.Size.chatAttachmentInset)
        .padding(.vertical, Theme.Size.chatAttachmentInset)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.attachmentChip, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attached \(attachment.name)")
    }

    @ViewBuilder private var leading: some View {
        switch attachment.kind {
        case .image:
            ComposerThumbnail(data: attachment.preview, id: attachment.id)
        case .pdf, .text:
            Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "doc.plaintext")
                .font(Theme.Typography.chip)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(
                    width: Theme.Size.chatAttachmentThumb,
                    height: Theme.Size.chatAttachmentThumb)
        }
    }
}

/// Decoded once per attachment: `ForEach` keys on its id, so a per-keystroke re-render reuses it.
private struct ComposerThumbnail: View {
    let data: Data?
    let id: UUID

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(Theme.Typography.chip)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: Theme.Size.chatAttachmentThumb, height: Theme.Size.chatAttachmentThumb)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
        .task(id: id) { image = data.flatMap(NSImage.init(data:)) }
    }
}

/// Staged files follow the typed text; past two they become a count, the width being the field's.
private struct PendingAttachmentsChips: View {
    let attachments: [ChatAttachment]
    let onRemove: (UUID) -> Void

    /// Two, because a third chip plus its name leaves the field too narrow to read what you type.
    private static let visibleLimit = 2

    private static func visible(_ attachments: [ChatAttachment]) -> [ChatAttachment] {
        Array(attachments.prefix(visibleLimit))
    }

    private static func overflowLabel(_ attachments: [ChatAttachment]) -> String? {
        let hidden = attachments.count - visibleLimit
        return hidden > 0 ? "+\(hidden)" : nil
    }

    static func width(for attachments: [ChatAttachment]) -> CGFloat {
        var total = visible(attachments).reduce(0) { $0 + AttachmentChip.width(for: $1) }
        total += CGFloat(max(0, visible(attachments).count - 1)) * Theme.Spacing.xs
        if let label = overflowLabel(attachments) {
            let text = (label as NSString).size(
                withAttributes: [.font: Theme.Typography.chipNSFont]
            ).width
            total += Theme.Spacing.xs + text + Theme.Spacing.sm * 2
        }
        return total
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Self.visible(attachments)) { attachment in
                AttachmentChip(attachment: attachment) { onRemove(attachment.id) }
            }
            if let label = Self.overflowLabel(attachments) {
                Text(label)
                    .font(Theme.Typography.chip)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.attachmentChip, style: .continuous
                        ).fill(Theme.Colors.controlSurface)
                    )
                    .help("\(attachments.count) files attached")
                    .accessibilityLabel("\(attachments.count) files attached")
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

struct AIReasoningButton: View {
    let title: String
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        HeaderMenuButton(
            title: title,
            systemImage: "brain",
            isOpen: isOpen,
            help: "Change reasoning effort",
            action: action
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}
