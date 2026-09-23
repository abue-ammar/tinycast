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
                    showsContext: $showsContext)
            }
            .frame(maxWidth: Theme.Size.aiChatReadingWidth)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
            .animation(.snappy, value: suggestions)
            .animation(.snappy, value: chat.draft.isEmpty)
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
    @Binding var showsContext: Bool

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
            }
            chips
            ZStack(alignment: .topLeading) {
                if chat.draft.isEmpty {
                    Text("Ask anything…")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                ChatComposerTextView(text: $chat.draft, focusKey: chat.session.id, onSubmit: submit)
            }
            controls
        }
        .padding(Theme.Spacing.xl)
        .background {
            Color.clear.glassEffect(
                .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        }
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

    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            ComposerIconButton(symbol: "paperclip", help: attachHelp) {
                coordinator.chooseFiles(for: chat)
            }
            AIModelPicker(chat: chat, selected: coordinator.model(for: chat), coordinator: coordinator)
            AIReasoningPicker(chat: chat, coordinator: coordinator)
            AIToolsPicker(chat: chat, coordinator: coordinator)
            if coordinator.capabilities(for: chat).webSearch {
                WebSearchToggle(settings: settings)
            }
            Spacer(minLength: 0)
            ContextGauge(
                report: coordinator.contextReport(for: chat, detailed: false), hovered: $showsContext)
            sendButton
        }
    }

    /// One paperclip for every kind; what this chat's model can read is what the help says.
    private var attachHelp: String {
        let can = coordinator.capabilities(for: chat)
        switch (can.images, can.documents) {
        case (true, true): return "Attach images, PDFs or text files"
        case (true, false): return "Attach images or text files"
        case (false, true): return "Attach PDFs or text files"
        case (false, false): return "Attach text files"
        }
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: chat.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .disabled(!chat.isStreaming && !canSend)
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

private struct ComposerIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
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
            Label {
                Text(coordinator.modelTitle(of: selected, among: groups.flatMap(\.options)))
            } icon: {
                MenuIconImage(icon: coordinator.modelIcon(of: selected))
            }
            .labelStyle(.titleAndIcon)
        }
        .composerPill()
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
            Label(
                efforts.isEmpty ? "Reasoning" : coordinator.selectedReasoningTitle(for: chat),
                systemImage: "brain"
            )
            .labelStyle(.titleAndIcon)
        }
        .composerPill()
        .disabled(efforts.isEmpty)
        .help(efforts.isEmpty ? "This model has no reasoning setting" : "Change reasoning effort")
    }
}

/// This chat's MCP servers: all of them, some, or none; the model must be one that calls tools.
private struct AIToolsPicker: View {
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
                servers.isEmpty || !scope.isEnabled ? "Tools" : "\(active) of \(servers.count)",
                systemImage: "wrench.and.screwdriver"
            )
            .labelStyle(.titleAndIcon)
        }
        .composerPill()
        .disabled(!takesTools)
        .help(
            takesTools
                ? "Choose the tools this chat may call"
                : "This model can't call tools")
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

/// The same switch as Settings → AI's: a prompt reaches a search engine only once it is on.
private struct WebSearchToggle: View {
    let settings: AISettingsStore

    var body: some View {
        @Bindable var settings = settings
        Toggle(isOn: $settings.webSearchEnabled) {
            Image(systemName: "globe")
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .help(settings.webSearchEnabled ? "Web search is on" : "Web search is off")
        .accessibilityLabel("Web search")
    }
}

/// A ring for the share of the context in use; hovering it raises the composer's context card.
private struct ContextGauge: View {
    let report: ChatContextReport
    @Binding var hovered: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ContextRing(fill: min(max(report.fill, 0), 1), tint: report.tint)
            Text(report.fill.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .contentShape(Rectangle())
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

extension View {
    /// The composer's menus read as options, not links: a capsule the size of the row.
    fileprivate func composerPill() -> some View {
        menuStyle(.button)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .fixedSize()
    }
}

/// A menu draws an image at its own size, so a brand mark is redrawn at the symbols' size.
private struct MenuIconImage: View {
    let icon: PopoverMenuIcon

    private static let edge: CGFloat = 16

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .asset(let name):
            if let image = Self.sized(name) {
                Image(nsImage: image)
            } else {
                Image(systemName: "sparkles")
            }
        case .file, .thumbnail, .blank:
            Image(systemName: "sparkles")
        }
    }

    private static func sized(_ name: String) -> NSImage? {
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
