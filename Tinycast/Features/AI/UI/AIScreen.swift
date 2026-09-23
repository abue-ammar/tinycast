import SwiftUI

/// Quick AI: one palette screen whose search field is the composer.
struct AIScreen: PaletteScreen {
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let chat: AIChatState
    let coordinator: QuickAICoordinator
    let chatCoordinator: AIChatCoordinator
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
                PopoverMenuItem(title: "Stop Response", systemImage: "stop.fill", shortcut: "⌘.") {
                    coordinator.stopResponse()
                })
        }
        items.append(
            PopoverMenuItem(
                title: chat.session.messages.isEmpty ? "Open AI Chat" : "Continue in AI Chat",
                systemImage: "bubble.left.and.bubble.right", shortcut: "⌘J"
            ) {
                coordinator.continueInChat()
            })
        items.append(
            PopoverMenuItem(title: "New Chat", systemImage: "plus.bubble", shortcut: "⌘N") {
                coordinator.startNewChat()
            })
        if canRegenerate {
            items.append(
                PopoverMenuItem(
                    title: "Regenerate Response", systemImage: "arrow.clockwise", shortcut: "⌘R"
                ) {
                    coordinator.regenerate()
                })
        }
        if chat.lastAssistantText != nil {
            items.append(
                PopoverMenuItem(
                    title: "Copy Last Response", systemImage: "doc.on.doc", startsSection: true,
                    shortcut: "⇧⌘C"
                ) {
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
                title: "Chat History", systemImage: "clock.arrow.circlepath", startsSection: true,
                shortcut: "⌘Y"
            ) {
                coordinator.showHistory()
            })
        items.append(
            PopoverMenuItem(
                title: "AI Settings", systemImage: "slider.horizontal.3", shortcut: "⌥⌘,"
            ) {
                chatCoordinator.showSettings()
            })
        return PopoverMenuContent(header: chatCoordinator.title(of: chat), items: items)
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

    /// Raycast's chords where it has one; ⌘Y is History, as in Safari, and ⌘. is Stop.
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .continueInChat: coordinator.continueInChat()
        case .newItem: coordinator.startNewChat()
        case .restart where canRegenerate: coordinator.regenerate()
        case .copyFile where chat.lastAssistantText != nil: coordinator.copyLastResponse()
        case .quickLook: coordinator.showHistory()
        case .pin where chat.isStreaming: coordinator.stopResponse()
        case .settings: chatCoordinator.showSettings()
        default: return false
        }
        return true
    }

    private var canRegenerate: Bool {
        !chat.isStreaming && chat.session.messages.last?.role == .assistant
    }

    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        let attachments = chat.pendingAttachments
        let addressed = chatCoordinator.addressedServer(in: vm.query)
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
                chat: chat,
                availability: { chatCoordinator.availability(for: chat) },
                onConfigure: chatCoordinator.showSettings,
                onAppear: chatCoordinator.prepareForChat,
                onChoose: { coordinator.send($0) }))
    }
}

private struct AIChatView: View {
    let chat: AIChatState
    let availability: () -> String?
    let onConfigure: () -> Void
    let onAppear: () -> Void
    let onChoose: (String) -> Void

    var body: some View {
        Group {
            if chat.session.messages.isEmpty {
                // Read in the body, so a CLI signing in or a provider switched on is seen at once.
                let unavailability = availability()
                AIEmptyState(
                    message: chat.notice ?? unavailability,
                    canConfigure: chat.notice != nil || unavailability != nil,
                    onConfigure: onConfigure)
            } else {
                ChatTranscriptView(
                    messages: chat.session.messages,
                    status: chat.liveStatus,
                    usage: chat.usage,
                    surface: .palette,
                    onChoose: chat.isStreaming ? nil : onChoose)
            }
        }
        .onAppear(perform: onAppear)
    }
}

/// Every staged file in one pill: the newest's glyph, a count of the rest, all names on hover.
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
                if let newest = attachments.last { AttachmentGlyph(attachment: newest) }
                if let others = Self.others(attachments) {
                    Text(others)
                        .font(metrics.typography.chip)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.trailing, metrics.spacing.xs)
                }
            }
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

/// The newest file's kind as a glyph; its picture waits in the menu, where a row has the room.
private struct AttachmentGlyph: View {
    @Environment(\.metrics) private var metrics
    let attachment: ChatAttachment

    var body: some View {
        Image(systemName: attachment.glyph)
            .font(metrics.typography.chip)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: metrics.size.chatAttachmentThumb, height: metrics.size.chatAttachmentThumb)
    }
}

extension ChatAttachment {
    /// One glyph per kind: the pill's, and a menu row's when there is no picture to show.
    var glyph: String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.plaintext"
        }
    }

    var menuIcon: PopoverMenuIcon {
        guard case .image = kind, let preview else { return .symbol(glyph) }
        return .thumbnail(id: id, data: preview)
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
            symbolSize: Theme.Size.barBrandIcon,
            isOpen: isOpen,
            help: "Change reasoning effort",
            action: action
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}
