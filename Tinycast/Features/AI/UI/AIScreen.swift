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
        } else if coordinator.send(vm.query) {
            vm.query = ""
        }
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
            ZStack(alignment: .bottomLeading) {
                AIChatView(
                    chat: chat, settings: settings, availability: coordinator.availability,
                    onConfigure: coordinator.showSettings, onAppear: coordinator.warmUpModelList)

                if let mentionQuery = Self.activeMention(in: vm.query) {
                    AIMentionTypeaheadView(
                        query: mentionQuery,
                        installed: core.extensions.installed,
                        onSelect: { token in
                            Self.applyMention(token, to: vm)
                        }
                    )
                    .padding(.leading, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
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

    static func applyMention(_ token: String, to vm: PaletteState) {
        guard let atIndex = vm.query.lastIndex(of: "@") else { return }
        let prefix = String(vm.query[..<atIndex])
        vm.query = prefix + "@" + token + " "
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

struct AIMentionItem: Identifiable, Hashable {
    let id: String
    let token: String
    let title: String
    let subtitle: String
    let iconName: String?
    let iconPath: String?
}

private struct AIMentionTypeaheadView: View {
    let query: String
    let installed: [InstalledExtension]
    let onSelect: (String) -> Void

    private var items: [AIMentionItem] {
        // 1. Built-in Tools
        let builtins = [
            AIMentionItem(id: "web", token: "web", title: "Web Search & Fetch", subtitle: "Search the web and read pages", iconName: "globe", iconPath: nil),
            AIMentionItem(id: "calc", token: "calc", title: "Calculator", subtitle: "Evaluate math and unit conversions", iconName: "function", iconPath: nil),
            AIMentionItem(id: "weather", token: "weather", title: "Weather & Location", subtitle: "Get local forecast and coordinates", iconName: "cloud.sun", iconPath: nil)
        ]

        // 2. Installed Extensions
        let extensions = installed.map { ext in
            let toolCount = ext.manifest.tools.count
            let sub = toolCount > 0 ? "\(toolCount) AI command\(toolCount == 1 ? "" : "s")" : ext.manifest.description
            return AIMentionItem(
                id: ext.manifest.name,
                token: ext.manifest.name,
                title: ext.title,
                subtitle: sub,
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

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items.prefix(5)) { item in
                    Button(action: { onSelect(item.token) }) {
                        AIMentionRowView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 320)
            .padding(.vertical, 4)
            .background(VisualEffectView())
            .background(Theme.Colors.panelScrim)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
}

private struct AIMentionRowView: View {
    let item: AIMentionItem

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let iconPath = item.iconPath {
                ExtensionIconView(
                    resolved: ExtensionImage.Resolved(source: .file(iconPath)),
                    size: 20)
            } else if let iconName = item.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                    Text("@" + item.token)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
