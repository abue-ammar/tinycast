import AppKit
import SwiftUI

/// The window's right-hand side: the open conversation, and its composer beneath it.
struct AIChatDetailView: View {
    @Environment(AIChatCoordinator.self) private var coordinator
    @Environment(ChatFindState.self) private var find
    @State private var isDropTargeted = false
    @State private var showsContext = false

    private var chat: AIChatState { coordinator.chats.window }

    /// The last reply's options, once it has finished; typing or sending moves past them.
    private var suggestions: [String] {
        guard !chat.isStreaming, let last = chat.session.messages.last, last.role == .assistant,
            last.state == .complete
        else { return [] }
        return ChatChoices.split(last.text).choices
    }

    var body: some View {
        GeometryReader { geometry in
            pane(composerHeight: ChatComposerTextView.maximumHeight(in: geometry.size.height))
        }
        .animation(.easeOut(duration: Theme.Duration.tooltip), value: showsContext)
        .dropDestination(for: URL.self) { files, _ in
            coordinator.attach(files: files, to: chat)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted { dropHint }
        }
    }

    private func pane(composerHeight: CGFloat) -> some View {
        // Stacked, not floated: the transcript ends where the composer begins, never beneath it.
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // In the transcript's own frame, so the card can never leave the window.
                .overlay(alignment: .bottom) {
                    if showsContext {
                        HStack {
                            Spacer(minLength: 0)
                            ContextCard(report: coordinator.contextReport(for: chat))
                        }
                        .frame(maxWidth: Theme.Size.aiChatReadingWidth)
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.bottom, Theme.Spacing.sm)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                    }
                }
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !suggestions.isEmpty, chat.draft.isEmpty {
                    ChatSuggestionChips(choices: suggestions) { coordinator.send($0, in: chat) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                AIChatComposer(
                    chat: chat, coordinator: coordinator, settings: coordinator.aiSettings,
                    maximumTextHeight: composerHeight, showsContext: $showsContext,
                    isDropTargeted: $isDropTargeted)
            }
            .frame(maxWidth: Theme.Size.aiChatReadingWidth)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
            .animation(.snappy, value: suggestions)
            .animation(.snappy, value: chat.draft.isEmpty)
        }
    }

    @ViewBuilder private var content: some View {
        if chat.session.messages.isEmpty {
            // Read in the body, so a CLI signing in or a provider switched on is seen at once.
            let unavailability = coordinator.availability(for: chat)
            AIEmptyState(
                message: chat.notice ?? unavailability,
                canConfigure: chat.notice != nil || unavailability != nil,
                onConfigure: coordinator.showSettings)
        } else {
            let occurrences = find.occurrences(in: chat.session.messages)
            ChatTranscriptView(
                messages: chat.session.messages, status: chat.liveStatus, usage: chat.usage,
                surface: .window,
                onRegenerate: chat.isStreaming ? nil : { coordinator.regenerate(in: chat) },
                find: find.isSearching
                    ? ChatFindHighlight(
                        query: find.needle, matches: Set(occurrences.map(\.messageID)),
                        current: find.currentOccurrence(in: occurrences))
                    : nil
            )
            // A switched chat is a new scroll: its own tail-following, opening at its latest line.
            .id(chat.session.id)
            .overlay(alignment: .topTrailing) {
                if find.isSearching {
                    FindCounter(
                        position: occurrences.isEmpty
                            ? 0 : min(find.current, occurrences.count - 1) + 1,
                        count: occurrences.count,
                        step: { find.step($0, in: chat.session.messages) }
                    )
                    .padding(Theme.Spacing.md)
                }
            }
        }
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(
                Theme.Colors.dropTarget,
                style: StrokeStyle(lineWidth: Theme.Size.dropHintStroke, dash: [Theme.Size.dropHintDash])
            )
            .padding(Theme.Spacing.md)
            .allowsHitTesting(false)
    }
}

/// Staged files, the text, then the chat's options and Send, on one pane of Liquid Glass.
private struct AIChatComposer: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator
    let settings: AISettingsStore
    let maximumTextHeight: CGFloat
    @Binding var showsContext: Bool
    @Binding var isDropTargeted: Bool
    @State private var editor = ComposerTextViewHandle()

    private var canSend: Bool {
        !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chat.pendingAttachments.isEmpty
    }

    var body: some View {
        @Bindable var chat = chat
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if !chat.session.messages.isEmpty, let notice = chat.notice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.sm)
            }
            chips
            ZStack(alignment: .topLeading) {
                if chat.draft.isEmpty {
                    Text("Ask anything…")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                ChatComposerTextView(
                    text: $chat.draft, focusKey: chat.session.id,
                    maximumTextHeight: maximumTextHeight, handle: editor,
                    isFileDragTargeted: $isDropTargeted,
                    onDropFiles: { coordinator.attach(files: $0, to: chat) },
                    onInvalidate: { coordinator.dictation.cancel(in: $0) }, onSubmit: submit)
            }
            // The text's edge is the + glyph's, which sits centred in its own hover square.
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, Theme.Spacing.xs)
            controls
        }
        .padding(Theme.Spacing.md)
        .background {
            Color.clear.glassEffect(
                .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        }
        .animation(.snappy, value: settings.webSearchEnabled)
    }

    @ViewBuilder private var chips: some View {
        let addressed = coordinator.addressedServer(in: chat.draft)
        if !chat.pendingAttachments.isEmpty || addressed != nil {
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.sm) {
                    if let addressed {
                        ComposerChip(symbol: "wrench.and.screwdriver", label: "@\(addressed.slug)")
                    }
                    ForEach(chat.pendingAttachments) { attachment in
                        AttachmentChip(attachment: attachment) {
                            coordinator.removeAttachment(attachment.id, in: chat)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    /// Search gives up its word before the model name starts to truncate.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            controlRow(compactSearch: false)
            controlRow(compactSearch: true)
        }
    }

    private func controlRow(compactSearch: Bool) -> some View {
        let searches = coordinator.capabilities(for: chat).webSearch
        return HStack(spacing: Theme.Spacing.xxs) {
            AIAddMenu(chat: chat, coordinator: coordinator, settings: settings, offersSearch: searches)
            if searches, settings.webSearchEnabled {
                WebSearchPill(settings: settings, isCompact: compactSearch)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Spacer(minLength: Theme.Spacing.md)
            AIModelPicker(chat: chat, selected: coordinator.model(for: chat), coordinator: coordinator)
                .layoutPriority(-1)
            AIReasoningPicker(chat: chat, coordinator: coordinator)
            ContextGauge(
                report: coordinator.contextReport(for: chat, detailed: false), hovered: $showsContext)
            if coordinator.dictation.isEnabled {
                DictationButton(
                    dictation: coordinator.dictation, editor: editor,
                    onNeedsModel: coordinator.showDictationSettings)
            }
            sendButton.padding(.leading, Theme.Spacing.sm)
        }
    }

    /// A solid disc, so Send is the one strong mark on a row of quiet controls.
    private var sendButton: some View {
        let enabled = chat.isStreaming || canSend
        return Button(action: submit) {
            Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                .font(chat.isStreaming ? Theme.Typography.composerStop : Theme.Typography.composerSend)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(enabled ? Theme.Colors.composerSendInk : Theme.Colors.textTertiary)
                .frame(width: Theme.Size.aiChatComposerControl, height: Theme.Size.aiChatComposerControl)
                .background(
                    Circle().fill(enabled ? Theme.Colors.composerSend : Theme.Colors.controlSurface)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeOut(duration: Theme.Duration.hover), value: enabled)
        .help(chat.isStreaming ? "Stop Response" : "Send  ↵")
        .accessibilityLabel(chat.isStreaming ? "Stop Response" : "Send")
    }

    /// Return and the button are one action: Send, or Stop while a reply streams.
    private func submit() {
        if chat.isStreaming {
            coordinator.stopResponse(in: chat)
        } else if coordinator.send(chat.draft, in: chat) {
            chat.draft = ""
        }
    }
}

/// A composer control's face: one glyph slot, the callout title, then the menu's chevron.
private struct ComposerControlLabel<Icon: View>: View {
    var title: String?
    var showsChevron = true
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if Icon.self != EmptyView.self {
                icon.frame(width: Theme.Size.aiChatComposerGlyph, height: Theme.Size.aiChatComposerGlyph)
            }
            if let title {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, title == nil && !showsChevron ? 0 : Theme.Spacing.md)
        .frame(minWidth: Theme.Size.aiChatComposerControl)
        .frame(height: Theme.Size.aiChatComposerControl)
        .contentShape(Rectangle())
        // One element: VoiceOver would otherwise read the mark and the chevron as menus of their own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title ?? "")
    }
}

extension ComposerControlLabel where Icon == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

private struct ComposerSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name).font(Theme.Typography.composerSymbol)
    }
}

/// Bare at rest and filled under the pointer, so the row reads as one line until it is used.
private struct ComposerControlChrome: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        content
            .background(shape.fill(hovered ? Theme.Colors.controlSurface : Color.clear))
            .contentShape(shape)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
    }
}

extension View {
    fileprivate func composerControl() -> some View {
        modifier(ComposerControlChrome())
    }

    /// A stock menu with Tinycast's own face, so its hover and sizes match the rest of the row.
    fileprivate func composerMenu() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .composerControl()
    }
}

/// Files, web search and tools are set now and then, so one + holds them all.
private struct AIAddMenu: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator
    let settings: AISettingsStore
    let offersSearch: Bool

    var body: some View {
        @Bindable var settings = settings
        Menu {
            Button("Attach Files…", systemImage: "paperclip") { coordinator.chooseFiles(for: chat) }
                .help(attachHelp)
            Divider()
            if offersSearch {
                Toggle("Web Search", systemImage: "globe", isOn: $settings.webSearchEnabled)
            }
            AIToolsMenu(chat: chat, coordinator: coordinator)
        } label: {
            ComposerControlLabel(showsChevron: false) { ComposerSymbol(name: "plus") }
        }
        .composerMenu()
        .help("Attach files, search the web, choose tools")
        .accessibilityLabel("Add")
    }

    /// One entry for every kind; what this chat's model can read is what the help says.
    private var attachHelp: String {
        let can = coordinator.capabilities(for: chat)
        switch (can.images, can.documents) {
        case (true, true): return "Attach images, PDFs or text files"
        case (true, false): return "Attach images or text files"
        case (false, true): return "Attach PDFs or text files"
        case (false, false): return "Attach text files"
        }
    }
}

/// Only while Dictation is on: a click starts it into this field, another click inserts the text.
private struct DictationButton: View {
    let dictation: DictationCoordinator
    let editor: ComposerTextViewHandle
    let onNeedsModel: () -> Void

    var body: some View {
        let field = dictation.field
        let session = field?.editor == editor.textView.map(ObjectIdentifier.init) ? field : nil
        Button {
            guard dictation.hasModel else { return onNeedsModel() }
            if let textView = editor.textView { dictation.toggle(into: textView) }
        } label: {
            Group {
                if session?.isTranscribing == true {
                    ProgressView().controlSize(.small)
                } else if session != nil {
                    ComposerSymbol(name: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .foregroundStyle(Color.accentColor)
                } else {
                    ComposerSymbol(name: "mic")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(width: Theme.Size.aiChatComposerControl, height: Theme.Size.aiChatComposerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .composerControl()
        .disabled(session?.isTranscribing == true)
        .help(help(session))
        .accessibilityLabel(session == nil ? "Dictate" : "Stop Dictating")
    }

    private func help(_ session: DictationField?) -> String {
        guard dictation.hasModel else { return "Download a dictation model in Settings" }
        guard let session else { return "Dictate" }
        return session.isTranscribing ? "Transcribing…" : "Stop and insert the text  ↵"
    }
}

/// Web search is on beside the +; a click turns it off, the + menu turns it back on.
private struct WebSearchPill: View {
    let settings: AISettingsStore
    let isCompact: Bool

    var body: some View {
        Button {
            settings.webSearchEnabled = false
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                ComposerSymbol(name: "globe")
                    .frame(width: Theme.Size.aiChatComposerGlyph, height: Theme.Size.aiChatComposerGlyph)
                if !isCompact { Text("Search").font(.callout) }
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, isCompact ? 0 : Theme.Spacing.md)
            .frame(minWidth: Theme.Size.aiChatComposerControl)
            .frame(height: Theme.Size.aiChatComposerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .composerControl()
        .help("Web search is on; click to turn it off")
        .accessibilityLabel("Web search is on")
    }
}

/// Every configured model, grouped by where it runs; the pick belongs to this chat.
private struct AIModelPicker: View {
    let chat: AIChatState
    /// Handed in, never read from `chat`: a reply writes the session on every streaming flush.
    let selected: AIModelSelection?
    let coordinator: AIChatCoordinator

    var body: some View {
        let groups = coordinator.modelGroups
        Menu {
            if coordinator.isModelCatalogLoading {
                Text("Loading models…")
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.options) { option in
                        Toggle(
                            isOn: Binding(
                                get: { selected.map(option.matches) ?? false },
                                set: { if $0 { coordinator.selectModel(option, in: chat) } })
                        ) {
                            Label {
                                Text(option.title)
                            } icon: {
                                MenuIconImage(icon: option.menuIcon)
                            }
                        }
                    }
                }
            }
            if groups.isEmpty, !coordinator.isModelCatalogLoading {
                Button("Configure AI…", action: coordinator.showSettings)
            }
        } label: {
            ComposerControlLabel(
                title: coordinator.modelTitle(of: selected, among: groups.flatMap(\.options))
            ) {
                MenuIconImage(icon: coordinator.modelIcon(of: selected), edge: Theme.Size.menuBrandIcon)
                    .font(Theme.Typography.composerSymbol)
            }
        }
        .composerMenu()
        .help("Switch this chat's model")
    }
}

private struct AIReasoningPicker: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator

    /// Shown even when the model has no efforts, so the row never changes shape under the reader.
    var body: some View {
        let efforts = coordinator.reasoningEfforts(for: chat)
        let selected = coordinator.model(for: chat)?.effort
        Menu {
            ForEach(efforts, id: \.id) { effort in
                Toggle(
                    effort.title,
                    isOn: Binding(
                        get: { selected == effort.id },
                        set: { if $0 { coordinator.selectReasoningEffort(effort, in: chat) } }))
            }
        } label: {
            // A word, not a glyph: beside the model's name it already reads as that model's setting.
            ComposerControlLabel(
                title: efforts.isEmpty ? "Reasoning" : coordinator.selectedReasoningTitle(for: chat))
        }
        .composerMenu()
        .disabled(efforts.isEmpty)
        .help(efforts.isEmpty ? "This model has no reasoning setting" : "Change reasoning effort")
    }
}

/// This chat's MCP servers: all of them, some, or none; the model must be one that calls tools.
private struct AIToolsMenu: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator

    var body: some View {
        let servers = coordinator.mcpServers
        let scope = chat.toolScope
        let takesTools = coordinator.capabilities(for: chat).tools
        let active = servers.filter { scope.allows($0.slug) }.count
        Menu {
            if servers.isEmpty {
                Text("No MCP servers are connected")
            } else {
                Toggle(
                    "Use Tools",
                    isOn: Binding(
                        get: { scope.isEnabled },
                        set: { coordinator.setToolsEnabled($0, in: chat) }))
                Section("Servers") {
                    ForEach(servers) { server in
                        Toggle(
                            server.name.isEmpty ? server.slug : server.name,
                            isOn: Binding(
                                get: { scope.allows(server.slug) },
                                set: { _ in coordinator.toggleToolServer(server.slug, in: chat) })
                        )
                        .disabled(!scope.isEnabled)
                    }
                }
            }
            Divider()
            Button("MCP Settings…", action: coordinator.showMCPSettings)
        } label: {
            Label(
                !takesTools
                    ? "Tools · Not with this model"
                    : servers.isEmpty || !scope.isEnabled
                        ? "Tools · Off" : "Tools · \(active) of \(servers.count)",
                systemImage: "wrench.and.screwdriver")
        }
        .disabled(!takesTools)
    }
}

/// Where find is in the open chat, with the same steps ⌘G and ⇧⌘G take.
private struct FindCounter: View {
    let position: Int
    let count: Int
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(count == 0 ? "No matches" : "\(position) of \(count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Previous Match  ⇧⌘G")
            .disabled(count == 0)
            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .help("Next Match  ⌘G")
            .disabled(count == 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .glassEffect(.regular, in: Capsule())
    }
}

/// A ring for the share of the context in use; hovering it raises the composer's context card.
private struct ContextGauge: View {
    let report: ChatContextReport
    @Binding var hovered: Bool

    var body: some View {
        ContextRing(fill: min(max(report.fill, 0), 1), tint: report.tint)
            .frame(width: Theme.Size.aiChatComposerControl, height: Theme.Size.aiChatComposerControl)
            .composerControl()
            .onHover { hovered = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(report.accessibilitySummary)
    }
}

private struct ContextRing: View {
    let fill: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.border, lineWidth: Theme.Size.contextRingStroke)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(tint, style: StrokeStyle(lineWidth: Theme.Size.contextRingStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Theme.Size.chatContextGauge, height: Theme.Size.chatContextGauge)
    }
}

/// Tinycast's own card, never a popover: the tokens the chat holds, then what the next turn sends.
private struct ContextCard: View {
    let report: ChatContextReport

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Context").font(.headline)
                Spacer(minLength: Theme.Spacing.xxl)
                Text(report.fill.formatted(.percent.precision(.fractionLength(0))))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(report.tint)
            }
            ProgressView(value: min(report.fill, 1))
                .tint(report.tint)
            if report.historyBytes > report.budget {
                Text("The oldest messages no longer fit and are left out.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.destructive)
            }
            Grid(
                alignment: .leading, horizontalSpacing: Theme.Spacing.xl,
                verticalSpacing: Theme.Spacing.xs
            ) {
                section("Tokens")
                if let usage = report.usage, let context = usage.contextTokens {
                    row("In context", tokens(context, of: usage.contextWindow))
                    row("Input", input(usage))
                    row("Output", output(usage))
                    if let cost = usage.costUSD {
                        row(
                            "Cost",
                            cost.formatted(
                                .currency(code: "USD").precision(.significantDigits(2))))
                    }
                } else {
                    row("Last reply", "Not reported yet")
                }
                section("Next message")
                row("Model", report.modelTitle)
                row("History", "\(bytes(report.historyBytes)) of \(bytes(report.budget))")
                row("Messages", "\(report.sentMessages) of \(report.totalMessages)")
                if report.stagedFiles > 0 {
                    row("Attached", "\(report.stagedFiles) · \(bytes(report.stagedBytes))")
                }
                row("System prompt", report.systemPrompt ? "On" : "Off")
                row("Web search", report.webSearch ? "On" : "Off")
                row(
                    "MCP servers",
                    report.toolServers == 0 ? "None" : "\(report.toolServers) in reach")
            }
            .font(.callout)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: Theme.Size.chatContextCard, alignment: .leading)
        .glassEffect(.regular, in: shape)
        // Solid under the glass: the card rises over the transcript, whose text must not show through.
        .background { shape.fill(Theme.Colors.windowSurface) }
        .shadow(color: Theme.Colors.tooltipShadow, radius: Theme.Spacing.xl, y: Theme.Spacing.xs)
    }

    private func section(_ title: String) -> some View {
        GridRow {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .gridCellColumns(2)
                .padding(.top, Theme.Spacing.xs)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().lineLimit(1).truncationMode(.middle)
        }
    }

    private func bytes(_ count: Int) -> String {
        count.formatted(.byteCount(style: .file))
    }

    private func tokens(_ count: Int, of window: Int?) -> String {
        guard let window else { return count.formatted() }
        return "\(count.formatted()) of \(window.formatted(.number.notation(.compactName)))"
    }

    private func input(_ usage: AIUsage) -> String {
        let prompt = (usage.inputTokens ?? 0) + (usage.cachedInputTokens ?? 0)
        guard let cached = usage.cachedInputTokens, cached > 0 else { return prompt.formatted() }
        return "\(prompt.formatted()) · \(cached.formatted()) cached"
    }

    private func output(_ usage: AIUsage) -> String {
        let output = usage.outputTokens ?? 0
        guard let thinking = usage.reasoningTokens, thinking > 0 else { return output.formatted() }
        return "\(output.formatted()) · \(thinking.formatted()) thinking"
    }
}

extension ChatContextReport {
    fileprivate var tint: Color {
        if fill >= 1 { return Theme.Colors.destructive }
        return fill >= 0.8 ? Theme.Colors.warning : Theme.Colors.textSecondary
    }
}

/// A menu draws an image at its own size, so a brand mark is redrawn at the symbols' size.
private struct MenuIconImage: View {
    let icon: PopoverMenuIcon
    var edge: CGFloat = 16

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .asset(let name):
            if let image = Self.sized(name, edge: edge) {
                Image(nsImage: image)
            } else {
                Image(systemName: "sparkles")
            }
        case .file, .thumbnail, .blank:
            Image(systemName: "sparkles")
        }
    }

    private static func sized(_ name: String, edge: CGFloat) -> NSImage? {
        guard let source = NSImage(named: name) else { return nil }
        let size = NSSize(width: edge, height: edge)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
