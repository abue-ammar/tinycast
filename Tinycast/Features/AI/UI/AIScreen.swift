import SwiftUI

/// AI chat as one native palette screen: the search field is its composer.
struct AIScreen: PaletteScreen {
    let vm: PaletteState
    let chat: AIChatState
    let settings: AISettingsStore
    let coordinator: AIChatCoordinator
    let core: AppCore

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
        } else if let _ = Self.activeMention(in: vm.query) {
            Self.completeSelectedMention(at: selection, in: vm, core: core)
        } else if coordinator.send(vm.query) {
            vm.query = ""
        }
    }

    func move(_ delta: Int, axis: Axis, from selection: Int) -> Int? {
        guard axis == .vertical, let mentionQuery = Self.activeMention(in: vm.query) else {
            return nil
        }
        let items = Self.mentionItems(for: mentionQuery, installed: core.extensions.installed)
        let activeItems = Array(items.prefix(6))
        guard !activeItems.isEmpty else { return nil }
        let current = min(max(selection, 0), activeItems.count - 1)
        let next = (current + delta + activeItems.count) % activeItems.count
        return next
    }

    func secondary(at selection: Int) -> Bool { false }

    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        let attachments = chat.pendingImages
        guard !attachments.isEmpty else { return nil }
        return PaletteHeaderAccessory(
            width: PendingAttachmentsChips.width(for: attachments) + Theme.Size.menuWidth,
            fieldNames: [], firstIncompleteField: nil,
            view: AnyView(PendingAttachmentsChips(attachments: attachments)))
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ZStack(alignment: .topLeading) {
                AIChatView(
                    chat: chat, settings: settings, availability: coordinator.availability,
                    onConfigure: coordinator.showSettings, onAppear: coordinator.warmUpModelList)

                if let mentionQuery = Self.activeMention(in: vm.query) {
                    AIMentionTypeaheadView(
                        query: mentionQuery,
                        selection: selection,
                        installed: core.extensions.installed,
                        onSelect: { item in
                            Self.applyMention(item, to: vm, in: chat)
                        },
                        onHover: { idx in
                            vm.selection = idx
                        }
                    )
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.leading, Theme.Spacing.xl)
                }
            }
        )
    }

    static func activeMention(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex > text.startIndex {
            let prevIndex = text.index(before: atIndex)
            if !text[prevIndex].isWhitespace { return nil }
        }
        let after = text[text.index(after: atIndex)...]
        if after.contains(where: \.isWhitespace) { return nil }
        return String(after)
    }

    static func mentionItems(for query: String, installed: [InstalledExtension]) -> [AIMentionItem] {
        let builtins = [
            AIMentionItem(
                id: "websearch", token: "websearch", title: "Web Search",
                iconName: "globe", iconPath: nil),
            AIMentionItem(
                id: "calculator", token: "calculator", title: "Calculator",
                iconName: "function", iconPath: nil),
            AIMentionItem(
                id: "weather", token: "weather", title: "Weather",
                iconName: "cloud.sun.fill", iconPath: nil),
            AIMentionItem(
                id: "location", token: "location", title: "Location",
                iconName: "location.fill", iconPath: nil)
        ]

        let extensions = installed.map { ext in
            AIMentionItem(
                id: ext.manifest.name,
                token: ext.manifest.name,
                title: ext.title,
                iconName: nil,
                iconPath: ext.iconPath
            )
        }

        let combined = builtins + extensions
        if query.isEmpty {
            return combined
        }
        return combined.filter {
            $0.token.localizedCaseInsensitiveContains(query) ||
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    static func completeSelectedMention(at selection: Int? = nil, in vm: PaletteState, core: AppCore) {
        guard let mentionQuery = activeMention(in: vm.query) else { return }
        let items = mentionItems(for: mentionQuery, installed: core.extensions.installed)
        guard !items.isEmpty else { return }
        let maxIndex = min(items.count - 1, 5)
        let index = max(0, min(selection ?? vm.selection, maxIndex))
        let selectedItem = items[index]
        applyMention(selectedItem, to: vm, in: core.aiChat)
    }

    static func applyMention(_ item: AIMentionItem, to vm: PaletteState, in chat: AIChatState) {
        guard let atIndex = vm.query.lastIndex(of: "@") else { return }
        let prefix = String(vm.query[..<atIndex])
        vm.query = prefix
        chat.stageMention(item)
        vm.selection = 0
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

/// Staged images sit after the typed text as named pills; the row is too thin for a thumbnail.
private struct PendingAttachmentsChips: View {
    let attachments: [ChatAttachment]

    static func width(for attachments: [ChatAttachment]) -> CGFloat {
        let font = Theme.Typography.chipNSFont
        return attachments.reduce(0) { total, attachment in
            let label = (attachment.name as NSString).size(withAttributes: [.font: font]).width
            return total + Theme.Size.chatAttachmentGlyph + label + Theme.Spacing.md * 3
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(attachments) { attachment in
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "photo")
                        .font(Theme.Typography.chip)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: Theme.Size.chatAttachmentGlyph)
                    Text(attachment.name)
                        .font(Theme.Typography.chip)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Capsule().fill(Theme.Colors.controlSurface))
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


// MARK: - @ Mention Typeahead



/// A unified square badge icon with vibrant tile background for AI tools.
struct AIToolBadgeView: View {
    let iconName: String
    var size: CGFloat = 18
    var cornerRadius: CGFloat = 4

    private var tileColor: Color {
        switch iconName {
        case "globe":
            return Color.blue
        case "function", "plus.forwardslash.minus":
            return Color.orange
        case "cloud.sun", "cloud.sun.fill":
            return Color.cyan
        case "location", "location.fill":
            return Color.indigo
        case "doc.text":
            return Color.gray
        default:
            return Color.blue
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tileColor)
            Image(systemName: iconName)
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// A staged tool / extension chip displayed inside the search bar before the cursor.
struct AIMentionChip: View {
    let item: AIMentionItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if let iconPath = item.iconPath {
                ExtensionIconView(
                    resolved: ExtensionImage.Resolved(source: .file(iconPath)),
                    size: 16)
            } else if let iconName = item.iconName {
                AIToolBadgeView(iconName: iconName, size: 18, cornerRadius: 4)
            }

            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.Colors.border, lineWidth: 0.5)
        )
    }
}

private struct AIMentionTypeaheadView: View {
    let query: String
    let selection: Int
    let installed: [InstalledExtension]
    let onSelect: (AIMentionItem) -> Void
    let onHover: (Int) -> Void
    @Environment(PaletteState.self) private var palette

    private var items: [AIMentionItem] {
        Array(AIScreen.mentionItems(for: query, installed: installed).prefix(6))
    }

    var body: some View {
        let currentSel = min(max(selection, 0), max(items.count - 1, 0))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Size.menuRowSpacing) {
                Text("Extensions & Tools")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.xs / 2)

                VStack(alignment: .leading, spacing: Theme.Size.menuRowSpacing) {
                    ForEach(items.indices, id: \.self) { index in
                        AIMentionRowView(
                            item: items[index],
                            isSelected: index == currentSel,
                            onActivate: { onSelect(items[index]) }
                        )
                        .onContinuousHover { phase in
                            guard palette.hoverHighlightArmed, case .active = phase else { return }
                            onHover(index)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.sm)
            .frame(width: Theme.Size.menuWidth)
            .glassEffect(
                .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
            )
        }
    }
}

private struct AIMentionRowView: View {
    let item: AIMentionItem
    let isSelected: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: Theme.Spacing.sm) {
                if let iconPath = item.iconPath {
                    ExtensionIconView(
                        resolved: ExtensionImage.Resolved(source: .file(iconPath)),
                        size: Theme.Size.menuIcon)
                } else if let iconName = item.iconName {
                    AIToolBadgeView(iconName: iconName, size: Theme.Size.menuIcon, cornerRadius: 4)
                }

                Text(item.title)
                    .font(Theme.Typography.menuRow)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Spacer(minLength: Theme.Spacing.sm)

                Text("@" + item.token)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Color.secondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(
                maxWidth: .infinity, minHeight: Theme.Size.menuRowHeight,
                maxHeight: Theme.Size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(isSelected ? Theme.Colors.selection : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
