import SwiftUI

/// AI chat as one native palette screen: the search field is its composer.
struct AIScreen: PaletteScreen {
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let chat: AIChatState
    let settings: AISettingsStore
    let coordinator: AIChatCoordinator
    /// The staged files' menu is the palette's to hang, like every other header menu.
    let openAttachments: () -> Void

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
                PopoverMenuItem(title: "Copy Last Response", systemImage: "doc.on.doc", startsSection: true) {
                    coordinator.copyLastResponse()
                })
        }
        if !chat.pendingAttachments.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: "Remove Attachments", systemImage: "paperclip",
                    startsSection: chat.lastAssistantText == nil
                ) {
                    coordinator.clearAttachments()
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Chat History", systemImage: "clock.arrow.circlepath", startsSection: true
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
            (attachments.isEmpty ? 0 : AttachmentsPill.width(for: attachments, metrics))
            + (addressed == nil ? 0 : ComposerChip.width(metrics))
            + (attachments.isEmpty || addressed == nil ? 0 : metrics.spacing.sm)
        return PaletteHeaderAccessory(
            width: width + metrics.spacing.md,
            fieldNames: [], firstIncompleteField: nil,
            view: AnyView(
                HStack(spacing: metrics.spacing.sm) {
                    if let addressed {
                        ComposerChip(symbol: "wrench.and.screwdriver", label: "@\(addressed.slug)")
                    }
                    // Absent, not empty: an empty stack would still take a gap after the `@` chip.
                    if !attachments.isEmpty {
                        AttachmentsPill(attachments: attachments, onOpen: openAttachments)
                    }
                }
                // Clear of the caret, so a chip never reads as laid over the last word.
                .padding(.leading, metrics.spacing.md)))
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

    @Environment(\.metrics) private var metrics
    let message: String?
    let canConfigure: Bool
    let onConfigure: () -> Void

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text("Ask anything")
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                if canConfigure { Button("Configure AI", action: onConfigure) }
            } else {
                HStack(spacing: metrics.spacing.sm) {
                    Text("Send a message")
                    KeyCapChip(text: "↵")
                }
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, metrics.spacing.xxl)
    }
}

/// The MCP `@server` pill: its glyph alone, since the handle it confirms is already in the text.
private struct ComposerChip: View {
    @Environment(\.metrics) private var metrics
    let symbol: String
    let label: String

    /// Load-bearing: part of the strip width that `searchFieldWidth(for:)` takes out of the field.
    static func width(_ metrics: InterfaceMetrics) -> CGFloat {
        metrics.size.chatAttachmentGlyph + metrics.spacing.sm * 2
    }

    var body: some View {
        Image(systemName: symbol)
            .font(metrics.typography.chip)
            .symbolRenderingMode(.hierarchical)
            .frame(width: metrics.size.chatAttachmentGlyph)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.xxs)
            .background(Capsule().fill(Theme.Colors.controlSurface))
            .tooltip("Offers only \(label)'s tools", edge: .bottom)
            .accessibilityLabel("Addressed to \(label)")
    }
}

/// Every staged file in one pill: the newest's preview, a count of the rest, all names on hover.
private struct AttachmentsPill: View {
    @Environment(\.metrics) private var metrics
    let attachments: [ChatAttachment]
    let onOpen: () -> Void

    private static func others(_ attachments: [ChatAttachment]) -> String? {
        attachments.count > 1 ? "+\(attachments.count - 1)" : nil
    }

    /// Load-bearing: part of the strip width that `searchFieldWidth(for:)` takes out of the field.
    static func width(for attachments: [ChatAttachment], _ metrics: InterfaceMetrics) -> CGFloat {
        let pill = metrics.size.chatAttachmentInset * 2 + metrics.size.chatAttachmentThumb
        guard let others = others(attachments) else { return pill }
        let text = (others as NSString).size(
            withAttributes: [.font: metrics.typography.chipNSFont]
        ).width
        return pill + metrics.spacing.xs + text + metrics.spacing.xs
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: metrics.spacing.xs) {
                if let newest = attachments.last { AttachmentPreview(attachment: newest) }
                if let others = Self.others(attachments) {
                    Text(others)
                        .font(metrics.typography.chip)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.trailing, metrics.spacing.xs)
                }
            }
            // Inset under the inner gap, so the thumbnail reads as filling the pill.
            .padding(metrics.size.chatAttachmentInset)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.attachmentChip, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(attachments.map(\.name).joined(separator: "\n"), edge: .bottom)
        .accessibilityLabel(
            attachments.count == 1
                ? "Attached \(attachments[0].name)" : "\(attachments.count) files attached")
    }
}

/// An image states itself; a document shows the glyph of its kind.
private struct AttachmentPreview: View {
    @Environment(\.metrics) private var metrics
    let attachment: ChatAttachment

    var body: some View {
        switch attachment.kind {
        case .image:
            ComposerThumbnail(data: attachment.preview, id: attachment.id)
        case .pdf, .text:
            Image(systemName: attachment.glyph)
                .font(metrics.typography.chip)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(
                    width: metrics.size.chatAttachmentThumb,
                    height: metrics.size.chatAttachmentThumb)
        }
    }
}

extension ChatAttachment {
    /// One glyph per kind, for the pill's documents and the menu's rows alike.
    var glyph: String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.plaintext"
        }
    }
}

/// Decoded once per attachment: the task keys on its id, so a per-keystroke re-render reuses it.
private struct ComposerThumbnail: View {
    @Environment(\.metrics) private var metrics
    let data: Data?
    let id: UUID

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(metrics.typography.chip)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: metrics.size.chatAttachmentThumb, height: metrics.size.chatAttachmentThumb)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
        .task(id: id) { image = data.flatMap(NSImage.init(data:)) }
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
