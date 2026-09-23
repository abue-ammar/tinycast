import AppKit
import SwiftUI

/// Chat actions for both surfaces, plus the AI Chat window's own; views route every mutation here.
@MainActor
@Observable
final class AIChatCoordinator {
    let chats: AIChatSurfacesState
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private unowned let core: AppCore
    private let window: AppWindowController
    /// Chats with a title request in flight, so a quick second reply never asks twice.
    @ObservationIgnored private var naming: [UUID: Task<Void, Never>] = [:]

    init(
        chats: AIChatSurfacesState, settings: AppSettings, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator, settingsCoordinator: SettingsCoordinator,
        core: AppCore
    ) {
        self.chats = chats
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
        window = AppWindowController(
            title: "AI Chat", contentSize: Theme.Size.aiChatWindow,
            minimumSize: Theme.Size.aiChatWindowMinimum, resizable: true,
            autosaveName: "AIChatWindow", activation: core.activationPolicy)
        chats.onReplyFinished = { [weak self] chat in self?.nameIfNeeded(chat) }
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.aiChat, .quickAI], settings.aiEnabled)
        guard settings.aiEnabled else {
            for request in naming.values { request.cancel() }
            naming = [:]
            // Before the handle closes: cancelling an open reply saves the conversation it ends.
            chats.reset()
            window.close()
            core.applyInstalledAILifecycle()
            core.chatHistory.close()
            core.quickAICoordinator.leave()
            return
        }
        core.applyInstalledAILifecycle()
        // Deferred off the launch path like the clipboard's own read; history fills in behind it.
        Task {
            core.chatHistory.load()
            // Inside the enabled branch only: off means the file is untouched, however old it gets.
            applyRetention()
        }
    }

    func applyRetention() {
        guard settings.aiEnabled,
            let cutoff = core.aiSettings.retention.cutoff(from: Date())
        else { return }
        core.chatHistory.prune(before: cutoff)
    }

    // MARK: - The window

    /// Reopens on whatever it last showed: the conversation is `AppCore`'s, not the window's.
    func showWindow() {
        guard settings.aiEnabled else { return }
        prepareForChat()
        guard !window.focus() else { return }
        // One find per window: the chrome's search field writes it, the transcript reads it.
        let find = ChatFindState()
        window.show(chrome: AIChatWindowChrome(coordinator: self, chats: chats, find: find)) {
            AIChatSplitViewController(
                sidebar: AIChatSidebarView().environment(self),
                detail: AIChatDetailView().environment(self).environment(find))
        }
    }

    /// The window's views read these through the coordinator, never through `AppCore`.
    var history: ChatHistoryStore { core.chatHistory }
    var aiSettings: AISettingsStore { core.aiSettings }

    func focusExisting() -> Bool {
        window.focus()
    }

    /// ⌘Q's target while the window is key; false leaves the chord to Settings.
    func closeWindowIfKey() -> Bool {
        guard NSApp.keyWindow?.identifier == AIChatWindowChrome.windowIdentifier else {
            return false
        }
        window.close()
        return true
    }

    func newChat() {
        chats.newWindowChat()
    }

    func openChat(id: UUID) {
        guard chats.openInWindow(id: id) else {
            core.showMessage("That chat could not be opened.", tone: .danger)
            return
        }
    }

    /// Quick AI's ⌘J: the conversation, its staged files and the half-typed line all move over.
    func continueInWindow(draft: String) {
        chats.continueQuickAIInWindow(draft: draft)
        showWindow()
    }

    /// A chat with no message yet is unsaved, so it has nothing to pin, copy or delete.
    func isSaved(_ chat: AIChatState) -> Bool {
        core.chatHistory.conversation(id: chat.session.id) != nil
    }

    func isPinned(_ chat: AIChatState) -> Bool {
        core.chatHistory.conversation(id: chat.session.id)?.isPinned == true
    }

    func togglePin(id: UUID) {
        guard let conversation = core.chatHistory.conversation(id: id) else { return }
        core.chatHistory.setPinned(!conversation.isPinned, id: id)
    }

    func rename(id: UUID, to title: String) {
        core.chatHistory.rename(id: id, to: title)
    }

    /// The title the window and the sidebar show, a rename included.
    func title(of chat: AIChatState) -> String {
        core.chatHistory.conversation(id: chat.session.id)?.displayTitle ?? chat.session.title
    }

    func copyChat(id: UUID) {
        guard let markdown = markdownTranscript(of: id) else { return }
        Paster.copyPlainText(markdown.text)
        core.showMessage("Chat copied")
    }

    /// The same Markdown Copy Chat makes, written where the reader chooses.
    func exportChat(id: UUID) {
        guard let markdown = markdownTranscript(of: id) else { return }
        let panel = NSSavePanel()
        // A title may hold a slash or a colon, neither of which a file name can.
        panel.nameFieldStringValue = markdown.title.replacing(/[\/:]/, with: "-") + ".md"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(markdown.text.utf8).write(to: url, options: .atomic)
        } catch {
            core.showMessage("The chat could not be exported.", tone: .danger)
        }
    }

    /// Live wherever a surface holds the chat, so an answer still arriving is included.
    private func markdownTranscript(of id: UUID) -> (title: String, text: String)? {
        guard let session = chats.holder(of: id)?.session ?? core.chatHistory.session(id: id)
        else { return nil }
        let title = core.chatHistory.conversation(id: id)?.displayTitle ?? session.title
        return (title, session.markdownTranscript(title: title))
    }

    func deleteChat(id: UUID) async {
        let title = core.chatHistory.conversation(id: id)?.displayTitle ?? "This chat"
        guard
            await core.confirm(
                title: "Delete chat?", message: "“\(title)” will be removed. This can't be undone.",
                symbol: "trash", confirmTitle: "Delete")
        else { return }
        chats.delete(id: id)
    }

    func deleteAllChats() async {
        guard
            await core.confirm(
                title: "Delete all chats?",
                message: "Every saved conversation except pinned ones will be removed. "
                    + "This can't be undone.",
                symbol: "trash", confirmTitle: "Delete All")
        else { return }
        chats.deleteAll()
    }

    // MARK: - Titles

    /// Asked on the first send, again after an answer if that failed, and never over a rename.
    private func nameIfNeeded(_ chat: AIChatState) {
        let session = chat.session
        guard let conversation = core.chatHistory.conversation(id: session.id),
            conversation.customTitle == nil, conversation.generatedTitle == nil,
            let description = ChatTitle.description(of: session),
            naming[session.id] == nil
        else { return }
        let selection = model(for: chat)
        let servers = titleServers(for: chat, on: selection)
        naming[session.id] = Task {
            let title = await self.title(
                describing: description, with: selection, servers: servers)
            // Whoever cancelled already cleared the entry, which may now be a newer request's.
            guard !Task.isCancelled else { return }
            naming[session.id] = nil
            if let title { core.chatHistory.setGeneratedTitle(title, id: session.id) }
        }
    }

    /// Codex's list is fixed at launch, so a title borrows the reply's servers and may call none.
    private func titleServers(
        for chat: AIChatState, on selection: AIModelSelection?
    ) -> AIToolServerSession? {
        guard case .codex? = selection else { return nil }
        let scope = chat.session.messages.first { $0.role == .user }?.toolScope
        return toolServers(for: chat, scopedTo: scope).map { borrowed in
            AIToolServerSession(rounds: 1, servers: borrowed.servers) { _ in false }
        }
    }

    /// Claude's CLI names sessions itself; every other route is asked once, in a side request.
    private func title(
        describing description: String, with selection: AIModelSelection?,
        servers: AIToolServerSession?
    ) async -> String? {
        if case .claude? = selection, let title = await core.installedAI.claudeTitle(for: description) {
            return title
        }
        guard let selection,
            let provider = try? AIProviderFactory.make(
                selection: selection, settings: core.aiSettings,
                subscription: core.chatGPTSubscription, installedAI: core.installedAI,
                toolServers: servers)
        else { return nil }
        let request = AIRequest(
            instructions: ChatTitle.instructions,
            messages: [AIMessage(role: .user, text: description)])
        var text = ""
        do {
            for try await event in provider.stream(request) {
                if case .text(let delta) = event { text += delta }
                if case .finished = event { break }
            }
        } catch {
            return nil
        }
        return ChatTitle.sanitize(text)
    }

    // MARK: - Either surface

    @discardableResult
    func send(_ input: String, in chat: AIChatState) -> Bool {
        guard settings.aiEnabled else { return false }
        do {
            let address = MCPComposerAddress.parse(input, slugs: core.mcpCoordinator.slugs)
            let sent = chat.send(
                address.rest, using: try provider(for: chat, scopedTo: address.slug),
                model: model(for: chat), webSearch: webSearch(for: chat),
                instructions: instructions, contextBudget: contextBudget(for: chat),
                toolScope: address.slug)
            // Named while the answer streams, so the sidebar has a title before the reply ends.
            if sent { nameIfNeeded(chat) }
            return sent
        } catch {
            chat.report(error.localizedDescription)
            return false
        }
    }

    /// The same question, asked of whichever model is selected now, of the server it named.
    func regenerate(in chat: AIChatState) {
        guard settings.aiEnabled else { return }
        let scope = chat.session.messages.last { $0.role == .user }?.toolScope
        do {
            chat.regenerate(
                using: try provider(for: chat, scopedTo: scope),
                model: model(for: chat), webSearch: webSearch(for: chat),
                instructions: instructions, contextBudget: contextBudget(for: chat))
        } catch {
            chat.report(error.localizedDescription)
        }
    }

    private func webSearch(for chat: AIChatState) -> Bool {
        core.aiSettings.webSearchEnabled && capabilities(for: chat).webSearch
    }

    private var instructions: String? {
        AIInstructions.compose(
            userPrompt: core.aiSettings.systemPrompt,
            isEnabled: core.aiSettings.systemPromptEnabled)
    }

    /// A turn's route and its tools: a CLI with its own client is handed servers, others the loop.
    private func provider(for chat: AIChatState, scopedTo slug: String?) throws -> any AIProvider {
        guard model(for: chat)?.runsItsOwnTools == true else {
            return toolAware(try provider(for: chat), scopedTo: slug, in: chat)
        }
        return try provider(for: chat, toolServers: toolServers(for: chat, scopedTo: slug))
    }

    /// The same narrowing as `tools(for:scopedTo:)`, for a client that starts its own servers.
    private func toolServers(for chat: AIChatState, scopedTo slug: String?) -> AIToolServerSession? {
        guard capabilities(for: chat).tools, chat.toolScope.isEnabled else { return nil }
        let excluded = chat.toolScope.excluded
        let chatID = chat.session.id
        let mcp = core.mcpCoordinator
        return AIToolServerSession(rounds: core.aiSettings.toolRounds.limit) {
            await mcp.toolServers(scopedTo: slug).filter { !excluded.contains($0.handle) }
        } consent: { call in
            await mcp.permit(call, in: chatID)
        }
    }

    /// Only chat wraps a route in the tool loop; a text rewrite has nothing to call.
    private func toolAware(
        _ provider: any AIProvider, scopedTo slug: String?, in chat: AIChatState
    ) -> any AIProvider {
        let tools = tools(for: chat, scopedTo: slug)
        guard capabilities(for: chat).tools, !tools.isEmpty else { return provider }
        let chatID = chat.session.id
        return AIToolLoopProvider(
            base: provider, tools: tools, maxRounds: core.aiSettings.toolRounds.limit
        ) { [mcp = core.mcpCoordinator] call in
            await mcp.invoke(call, in: chatID)
        }
    }

    /// `@server` narrows a turn further, but never past what the chat's tools menu switched off.
    private func tools(for chat: AIChatState, scopedTo slug: String?) -> [AITool] {
        guard chat.toolScope.isEnabled else { return [] }
        let excluded = chat.toolScope.excluded
        return core.mcpCoordinator.tools(scopedTo: slug).filter { tool in
            guard let route = MCPToolName.parse(tool.name) else { return true }
            return !excluded.contains(route.slug)
        }
    }

    /// The servers a chat's tools menu offers; empty when MCP is off or nothing is set up.
    var mcpServers: [MCPServer] { core.mcpCoordinator.servers }

    func setToolsEnabled(_ enabled: Bool, in chat: AIChatState) {
        chat.toolScope.isEnabled = enabled
    }

    func toggleToolServer(_ slug: String, in chat: AIChatState) {
        chat.toolScope.toggle(slug)
    }

    func showMCPSettings() {
        settingsCoordinator.showSettings(tab: .ai)
    }

    /// The server a draft is addressed to, so the composer can show it as a chip while typing.
    func addressedServer(in draft: String) -> MCPServer? {
        MCPComposerAddress.parse(draft, slugs: core.mcpCoordinator.slugs).slug
            .flatMap { core.mcpCoordinator.server(slug: $0) }
    }

    func stopResponse(in chat: AIChatState) {
        chat.cancel()
    }

    func copyLastResponse(in chat: AIChatState) {
        guard let text = chat.lastAssistantText else { return }
        Paster.copyPlainText(text)
    }

    /// What the chat's model can take; the composer offers only what applies.
    func capabilities(for chat: AIChatState) -> AIModelCapabilities {
        switch model(for: chat) {
        case .appleIntelligence?: return .appleIntelligence
        case .codex?: return .codex
        case .claude?: return .claudeCommand
        case .grok?, .openCode?, .cursor?:
            return AIModelCapabilities(
                images: false, documents: false, webSearch: false, tools: false)
        case .api(let connection, let model, _)?:
            return core.aiSettings.connection(id: connection)?.capabilities(for: model)
                ?? AIModelCapabilities.none
        case nil: return AIModelCapabilities.none
        }
    }

    /// How much history the chat's route can hold; the on-device window is far smaller.
    func contextBudget(for chat: AIChatState) -> Int {
        model(for: chat)?.isOnDevice == true
            ? AppleIntelligence.contextBudget : ChatSession.defaultTextBudget
    }

    /// The context card's facts; the gauge redraws per flush, so it skips the card's model title.
    func contextReport(for chat: AIChatState, detailed: Bool = true) -> ChatContextReport {
        let session = chat.session
        let budget = contextBudget(for: chat)
        let can = capabilities(for: chat)
        let scope = chat.toolScope
        return ChatContextReport(
            modelTitle: detailed ? selectedModelTitle(for: chat) : "",
            historyBytes: session.historyBytes, budget: budget,
            sentMessages: session.sentMessageCount(textBudget: budget),
            totalMessages: session.historyMessages.count,
            stagedFiles: chat.pendingAttachments.count,
            stagedBytes: chat.pendingAttachments.reduce(0) { $0 + $1.payload.byteCount },
            usage: chat.usage,
            systemPrompt: core.aiSettings.systemPromptEnabled,
            webSearch: core.aiSettings.webSearchEnabled && can.webSearch,
            toolServers: can.tools && scope.isEnabled
                ? mcpServers.count { scope.allows($0.slug) } : 0)
    }

    // MARK: - Attachments

    /// ⌘V stages a file, read off-main; false hands the chord back to the field editor.
    func attachPastedFile(files: [URL], to chat: AIChatState) -> Bool {
        let pasteboard = NSPasteboard.general
        // A copied text selection often carries a TIFF too; only a board with no string is a picture.
        let pasted =
            files.isEmpty && pasteboard.string(forType: .string) == nil
            ? pasteboard.availableType(from: [.png, .tiff]).flatMap { pasteboard.data(forType: $0) }
            : nil
        guard !files.isEmpty || pasted != nil else { return false }
        if let refusal = unattachable(files, in: chat) {
            core.showMessage(refusal.message, tone: .neutral)
            return true
        }
        if pasted != nil, !capabilities(for: chat).images {
            core.showMessage(ChatAttachmentRefusal.imagesUnsupported.message, tone: .neutral)
            return true
        }
        stage(files: files, pasted: pasted, into: chat)
        return true
    }

    /// A drop or the paperclip: the same refusals as a paste, since the route is what decides.
    func attach(files: [URL], to chat: AIChatState) {
        let files = files.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        if let refusal = unattachable(files, in: chat) {
            core.showMessage(refusal.message, tone: .neutral)
            return
        }
        stage(files: files, pasted: nil, into: chat)
    }

    /// An accessory app must activate first, or the panel opens behind the frontmost app.
    func chooseFiles(for chat: AIChatState) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        panel.message = "Choose images, PDFs or text files to send with your next message."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        attach(files: panel.urls, to: chat)
    }

    func clearAttachments(in chat: AIChatState) {
        chat.clearAttachments()
    }

    func removeAttachment(_ id: UUID, in chat: AIChatState) {
        chat.removeAttachment(id)
    }

    /// The first refusal the current route forces, so a paste explains itself rather than dropping.
    private func unattachable(_ files: [URL], in chat: AIChatState) -> ChatAttachmentRefusal? {
        let can = capabilities(for: chat)
        for file in files {
            guard let kind = AIAttachmentPolicy.kind(forFileName: file.lastPathComponent) else {
                return .unsupported(file.pathExtension.lowercased())
            }
            switch kind {
            case .image where !can.images: return .imagesUnsupported
            case .pdf where !can.documents: return .documentsUnsupported
            default: continue
            }
        }
        return nil
    }

    /// Files first, raw bytes as fallback; the chord is consumed, never pasting a path.
    private func stage(files: [URL], pasted: Data?, into chat: AIChatState) {
        let generation = chat.stagingGeneration
        Task { [weak self, weak chat] in
            let read = await Task.detached(priority: .userInitiated) {
                () -> [ChatAttachmentReader.Outcome] in
                if !files.isEmpty { return files.map(ChatAttachmentReader.read) }
                return pasted.map { [ChatAttachmentReader.image($0)] } ?? []
            }.value
            guard let self, let chat else { return }
            guard generation == chat.stagingGeneration else {
                core.showMessage(
                    "That file was still loading and did not make it into the chat.",
                    tone: .neutral)
                return
            }
            // Stops at the first refusal so a mixed paste says which file it could not take.
            for outcome in read {
                switch outcome {
                case .failed(let refusal):
                    core.showMessage(refusal.message, tone: .neutral)
                    return
                case .staged(let item):
                    let attachment = ChatAttachment(
                        payload: item.payload, name: item.name, preview: item.preview)
                    if let refusal = chat.attach(attachment) {
                        core.showMessage(refusal.message, tone: .neutral)
                        return
                    }
                }
            }
        }
    }

    // MARK: - Models

    var modelOptions: [AIModelOption] {
        modelGroups.flatMap(\.options)
    }

    var isModelCatalogLoading: Bool {
        core.aiSettings.enabledInstalledProviders.contains { kind in
            switch kind {
            case .codex: core.chatGPTSubscription.phase == .starting
            case .claude, .grok, .openCode, .cursor:
                core.installedAI.status(for: kind).phase == .checking
            }
        }
    }

    var modelGroups: [AIModelOptionGroup] {
        AIModelOption.availableGroups(
            settings: core.aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI)
    }

    /// The chat's own model while it is still reachable; otherwise the default a new chat takes.
    func model(for chat: AIChatState) -> AIModelSelection? {
        if let own = chat.session.model, isReachable(own) { return own }
        return core.aiSettings.defaultModel
    }

    /// A route removed in Settings falls back to the default rather than failing the chat.
    private func isReachable(_ selection: AIModelSelection) -> Bool {
        switch selection {
        case .appleIntelligence:
            return true
        case .api(let connection, let model, _):
            return core.aiSettings.connection(id: connection)?.models.contains(model) == true
        case .codex, .claude, .grok, .openCode, .cursor:
            return selection.source.installedKind.map {
                core.aiSettings.enabledInstalledProviders.contains($0)
            } ?? false
        }
    }

    private func provider(
        for chat: AIChatState, toolServers: AIToolServerSession? = nil
    ) throws -> any AIProvider {
        guard let selection = model(for: chat) else {
            throw AIProviderError.unavailable("Choose a default AI model in Settings.")
        }
        return try AIProviderFactory.make(
            selection: selection, settings: core.aiSettings,
            subscription: core.chatGPTSubscription, installedAI: core.installedAI,
            toolServers: toolServers)
    }

    /// Tinycast runs a local server itself only while some live chat's route cannot.
    var everyChatRunsItsOwnTools: Bool {
        chats.live.allSatisfy { model(for: $0)?.runsItsOwnTools == true }
    }

    func selectedModelTitle(for chat: AIChatState) -> String {
        modelTitle(of: model(for: chat), among: modelOptions)
    }

    /// Shortened here, not by layout: a flexible label would take the row from the search field.
    func modelTitle(of selected: AIModelSelection?, among options: [AIModelOption]) -> String {
        guard let selected else { return "Choose Model" }
        let title = options.first { $0.matches(selected) }?.title ?? selected.model
        guard title.count > Self.maxModelTitleLength else { return title }
        let keep = Self.maxModelTitleLength / 2
        return "\(title.prefix(keep))…\(title.suffix(keep))"
    }

    private static let maxModelTitleLength = 26

    func selectedModelIcon(for chat: AIChatState) -> PopoverMenuIcon {
        modelIcon(of: model(for: chat))
    }

    /// From the selection, not the loaded list: the list arrives after the picker first paints.
    func modelIcon(of selected: AIModelSelection?) -> PopoverMenuIcon {
        switch selected {
        case .appleIntelligence?: return AIModelOption.appleIntelligenceIcon
        case .codex?: return .asset(AIBrand.openAI.assetName)
        case .claude?: return .asset(AIBrand.claude.assetName)
        case .grok?: return .asset(AIBrand.x.assetName)
        case .cursor?: return AIModelOption.cursorIcon
        case .openCode(let model, _)?: return AIModelOption.icon(AIBrand.resolve(model: model))
        case .api(let connection, let model, _)?:
            return AIModelOption.icon(
                core.aiSettings.connection(id: connection).flatMap {
                    AIBrand.resolve(provider: $0.provider, model: model)
                })
        case nil: return AIModelOption.icon(nil)
        }
    }

    /// What entering chat costs once: the model list resolved, and the servers connected.
    func prepareForChat() {
        warmUpModelList()
        core.mcpCoordinator.warmUp()
    }

    /// Fetches the list so the title is a name, and a default can resolve without Settings.
    func warmUpModelList() {
        guard let stored = core.aiSettings.defaultModel else {
            prepareModelSwitcher()
            core.aiSettings.resolveDefaultModel()
            return
        }
        // Only an installed route needs checking; every other one is already settled on disk.
        if stored.source.installedKind != nil { prepareModelSwitcher() }
    }

    /// The chat keeps the pick; the default follows it, so the next new chat starts there too.
    func selectModel(_ option: AIModelOption, in chat: AIChatState) {
        let selection = AIModelOption.withDefaultEffort(
            option.selection, settings: core.aiSettings,
            subscription: core.chatGPTSubscription, installedAI: core.installedAI)
        chat.setModel(selection)
        core.aiSettings.select(selection)
    }

    func reasoningEfforts(for chat: AIChatState) -> [ChatGPTSubscription.Effort] {
        AIModelOption.efforts(
            for: model(for: chat), settings: core.aiSettings,
            subscription: core.chatGPTSubscription, installedAI: core.installedAI)
    }

    func selectedReasoningTitle(for chat: AIChatState) -> String {
        guard let selected = model(for: chat)?.effort,
            let effort = reasoningEfforts(for: chat).first(where: { $0.id == selected })
        else { return "Reasoning" }
        return effort.title
    }

    func selectReasoningEffort(_ effort: ChatGPTSubscription.Effort, in chat: AIChatState) {
        guard let selection = model(for: chat)?.withEffort(effort.id) else { return }
        chat.setModel(selection)
        core.aiSettings.select(selection)
    }

    @discardableResult
    func prepareModelSwitcher() -> Task<Void, Never> {
        core.applyInstalledAILifecycle()
    }

    func showSettings() {
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        settingsCoordinator.showSettings(tab: .ai)
    }

    func availability(for chat: AIChatState) -> String? {
        do {
            _ = try provider(for: chat)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// What the context card lays out; history is counted in bytes, the unit the budget is kept in.
struct ChatContextReport: Equatable {
    let modelTitle: String
    let historyBytes: Int
    let budget: Int
    let sentMessages: Int
    let totalMessages: Int
    let stagedFiles: Int
    let stagedBytes: Int
    let usage: AIUsage?
    let systemPrompt: Bool
    let webSearch: Bool
    let toolServers: Int

    /// The model's own window when the route reported one; otherwise Tinycast's history budget.
    var fill: Double {
        if let tokens = usage?.contextTokens, let window = usage?.contextWindow, window > 0 {
            return Double(tokens) / Double(window)
        }
        return Double(historyBytes) / Double(max(budget, 1))
    }

    var accessibilitySummary: String {
        let percent = fill.formatted(.percent.precision(.fractionLength(0)))
        return "Context \(percent), \(sentMessages) of \(totalMessages) messages sent"
    }
}
