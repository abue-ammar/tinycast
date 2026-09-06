import AppKit
import Foundation

/// Owns chat actions; views render `AIChatState` and route every mutation through here.
@MainActor
final class AIChatCoordinator {
    private let chat: AIChatState
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private unowned let core: AppCore

    init(
        chat: AIChatState, settings: AppSettings, appIndex: AppIndex, palette: PaletteState,
        paletteCoordinator: PaletteCoordinator, settingsCoordinator: SettingsCoordinator,
        core: AppCore
    ) {
        self.chat = chat
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.aiChat], settings.aiEnabled)
        guard settings.aiEnabled else {
            // Before the handle closes: cancelling an open reply saves the conversation it ends.
            chat.startNewChat()
            core.applyInstalledAILifecycle()
            core.chatHistory.close()
            if palette.mode == .ai || palette.mode == .aiHistory { palette.prepare(mode: .launcher) }
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

    func showChat() {
        guard settings.aiEnabled else { return }
        // Not `togglePalette`: the open policy decides a chat only on the way in.
        guard !paletteCoordinator.isShowing(.ai) else {
            paletteCoordinator.hidePalette()
            return
        }
        applyOpenPolicy()
        paletteCoordinator.showPalette(mode: .ai)
    }

    /// ⇥ and the AI fallback: a fresh chat that carries the question, already asked.
    func ask(_ prompt: String) {
        guard settings.aiEnabled else { return }
        // No question is no reason to skip the open policy: this is a summon, not an ask.
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showChat()
            return
        }
        chat.startNewChat()
        paletteCoordinator.showPalette(mode: .ai)
        send(prompt)
    }

    /// A file pasted at the launcher belongs in chat, never in a search for its name.
    func attachPastedFileFromLauncher(files: [URL]) -> Bool {
        guard settings.aiEnabled, !files.isEmpty else { return false }
        showChat()
        return attachPastedFile(files: files)
    }

    /// The one place deciding whether summoning resumes; Pop to Root only forgets the screen.
    private func applyOpenPolicy() {
        // A reply still arriving was asked for; resetting would discard the answer.
        guard !chat.isStreaming else { return }
        let recent = core.chatHistory.conversations.first
        let hasTranscript = !chat.session.messages.isEmpty
        // Staged files are unsent work: neither branch may throw them away on a plain re-summon.
        let hasStaging = !chat.pendingAttachments.isEmpty
        // From history when nothing is resident, so the verdict still holds after a relaunch.
        let lastActiveAt = hasTranscript ? chat.session.updatedAt : recent?.updatedAt
        let decision = AIConversationOpenPolicy.decide(
            opensTo: core.aiSettings.opensTo, newAfter: core.aiSettings.newChatAfter,
            lastActiveAt: lastActiveAt, now: Date())
        switch decision {
        case .resume:
            guard !hasTranscript, !hasStaging, let recent else { return }
            chat.open(id: recent.id)
        case .startNew:
            // An empty chat is already new; resetting it would only drop what is staged in it.
            guard hasTranscript else { return }
            chat.startNewChat()
        }
    }

    @discardableResult
    func send(_ input: String) -> Bool {
        guard settings.aiEnabled else { return false }
        do {
            let webSearch = core.aiSettings.webSearchEnabled && capabilities.webSearch
            let address = MCPComposerAddress.parse(input, slugs: core.mcpCoordinator.slugs)
            return chat.send(
                address.rest, using: try toolAware(core.aiProvider(), scopedTo: address.slug),
                webSearch: webSearch,
                instructions: AIInstructions.compose(
                    userPrompt: core.aiSettings.systemPrompt,
                    isEnabled: core.aiSettings.systemPromptEnabled),
                contextBudget: contextBudget)
        } catch {
            chat.report(error.localizedDescription)
            return false
        }
    }

    /// Only chat wraps a route in the tool loop; a text rewrite has nothing to call.
    private func toolAware(_ provider: any AIProvider, scopedTo slug: String?) -> any AIProvider {
        let tools = core.mcpCoordinator.tools(scopedTo: slug)
        guard capabilities.tools, !tools.isEmpty else { return provider }
        let chatID = chat.session.id
        return AIToolLoopProvider(base: provider, tools: tools) { [mcp = core.mcpCoordinator] call in
            await mcp.invoke(call, in: chatID)
        }
    }

    /// The server a draft is addressed to, so the composer can show it as a chip while typing.
    func addressedServer(in draft: String) -> MCPServer? {
        MCPComposerAddress.parse(draft, slugs: core.mcpCoordinator.slugs).slug
            .flatMap { core.mcpCoordinator.server(slug: $0) }
    }

    func startNewChat() {
        chat.startNewChat()
        palette.prepare(mode: .ai)
    }

    func showHistory() {
        palette.prepare(mode: .aiHistory)
    }

    func openChat(id: UUID) {
        guard chat.open(id: id) else { return }
        palette.prepare(mode: .ai)
    }

    func deleteChat(id: UUID) {
        chat.delete(id: id)
    }

    func deleteAllChats() async {
        guard
            await core.confirm(
                title: "Delete all chats?",
                message: "Every saved conversation will be removed. This can't be undone.",
                symbol: PaletteMode.aiHistory.systemImage, confirmTitle: "Delete All")
        else { return }
        chat.deleteAll()
    }

    func stopResponse() {
        chat.cancel()
    }

    func copyLastResponse() {
        guard let text = chat.lastAssistantText else { return }
        Paster.copyPlainText(text)
    }

    /// What the selected model can take; the footer offers only what applies.
    var capabilities: AIModelCapabilities {
        switch core.aiSettings.defaultModel {
        case .appleIntelligence?: return .appleIntelligence
        case .codex?: return .codex
        case .claude?, .openCode?:
            return AIModelCapabilities(
                images: false, documents: false, webSearch: false, tools: false)
        case .api(let connection, let model, _)?:
            return core.aiSettings.connection(id: connection)?.capabilities(for: model)
                ?? AIModelCapabilities.none
        case nil: return AIModelCapabilities.none
        }
    }

    /// How much history the selected route can hold; the on-device window is far smaller.
    private var contextBudget: Int {
        core.aiSettings.defaultModel?.isOnDevice == true
            ? AppleIntelligence.contextBudget : ChatSession.defaultTextBudget
    }

    /// ⌘V stages a file, read off-main; false hands the chord back to the field editor.
    func attachPastedFile(files: [URL]) -> Bool {
        let pasteboard = NSPasteboard.general
        // A copied text selection often carries a TIFF too; only a board with no string is a picture.
        let pasted =
            files.isEmpty && pasteboard.string(forType: .string) == nil
            ? pasteboard.availableType(from: [.png, .tiff]).flatMap { pasteboard.data(forType: $0) }
            : nil
        guard !files.isEmpty || pasted != nil else { return false }
        if let refusal = unattachable(files) {
            core.showMessage(refusal.message, tone: .neutral)
            return true
        }
        if pasted != nil, !capabilities.images {
            core.showMessage(ChatAttachmentRefusal.imagesUnsupported.message, tone: .neutral)
            return true
        }
        stage(files: files, pasted: pasted)
        return true
    }

    /// The first refusal the current route forces, so a paste explains itself rather than dropping.
    private func unattachable(_ files: [URL]) -> ChatAttachmentRefusal? {
        let can = capabilities
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
    private func stage(files: [URL], pasted: Data?) {
        let generation = chat.stagingGeneration
        Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { () -> [Read] in
                if !files.isEmpty { return files.map(Self.read) }
                guard let pasted, let png = Self.boundedPNG(pasted) else { return [.failed(.size)] }
                return [
                    .staged(
                        Staged(
                            payload: .image(AIImage(data: png, mimeType: "image/png")),
                            name: "Image", preview: Self.preview(png)))
                ]
            }.value
            guard let self else { return }
            guard generation == self.chat.stagingGeneration else {
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

    /// Carries what a staged file becomes across the detached read.
    private struct Staged: Sendable {
        let payload: ChatAttachment.Payload
        let name: String
        let preview: Data?
    }

    /// A refusal rather than a nil, so one bad file in a paste is named instead of vanishing.
    private enum Read: Sendable {
        case staged(Staged)
        case failed(ChatAttachmentRefusal)
    }

    /// Sized before it is read, so a four-gigabyte CSV can never be slurped into memory.
    nonisolated private static func read(_ file: URL) -> Read {
        let name = file.lastPathComponent
        guard let kind = AIAttachmentPolicy.kind(forFileName: name) else {
            return .failed(.unsupported(file.pathExtension.lowercased()))
        }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let ceiling =
            kind == .text ? AIAttachmentBudget.maxInlinedTextBytes : AIAttachmentBudget.maxBytes
        guard size <= ceiling else { return .failed(kind == .text ? .textTooLong : .size) }
        guard let bytes = try? Data(contentsOf: file) else { return .failed(.unreadable) }
        let mimeType = AIAttachmentPolicy.mimeType(forFileName: name)
        switch kind {
        case .image:
            guard let png = boundedPNG(bytes) else { return .failed(.unreadable) }
            return .staged(
                Staged(
                    payload: .image(AIImage(data: png, mimeType: "image/png")), name: name,
                    preview: preview(png)))
        case .pdf:
            return .staged(
                Staged(
                    payload: .document(AIDocument(data: bytes, mimeType: mimeType, name: name)),
                    name: name, preview: nil))
        case .text:
            // Re-encoded from the decoded string, so undecodable bytes refuse rather than mojibake.
            guard let decoded = String(data: bytes, encoding: .utf8) else {
                return .failed(.undecodable)
            }
            return .staged(
                Staged(
                    payload: .document(
                        AIDocument(data: Data(decoded.utf8), mimeType: mimeType, name: name)),
                    name: name, preview: nil))
        }
    }

    /// The pill's thumbnail, encoded once here rather than decoded per keystroke in the header.
    nonisolated private static func preview(_ png: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: png) else { return nil }
        let edge: CGFloat = 40
        let scale = min(1, edge / max(CGFloat(source.pixelsWide), CGFloat(source.pixelsHigh)))
        let size = NSSize(
            width: max(1, (CGFloat(source.pixelsWide) * scale).rounded()),
            height: max(1, (CGFloat(source.pixelsHigh) * scale).rounded()))
        guard
            let scaled = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: scaled)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return scaled.representation(using: .png, properties: [:])
    }

    /// Backspace on an empty composer takes the last staged image before it backs out of chat.
    func removeLastAttachment() -> Bool {
        chat.removeLastAttachment()
    }

    func clearAttachments() {
        chat.clearAttachments()
    }

    func removeAttachment(_ id: UUID) {
        chat.removeAttachment(id)
    }

    nonisolated private static let maxImageEdge: CGFloat = 1_568

    nonisolated private static func boundedPNG(_ data: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: data) else { return nil }
        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        let scale = min(1, maxImageEdge / max(width, height))
        guard scale < 1 else {
            return source.representation(using: .png, properties: [:])
        }
        let size = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        guard
            let scaled = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: scaled)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return scaled.representation(using: .png, properties: [:])
    }

    var modelOptions: [AIModelOption] {
        modelGroups.flatMap(\.options)
    }

    var isModelCatalogLoading: Bool {
        core.aiSettings.enabledInstalledProviders.contains { kind in
            switch kind {
            case .codex: core.chatGPTSubscription.phase == .starting
            case .claude, .openCode: core.installedAI.status(for: kind).phase == .checking
            }
        }
    }

    var modelGroups: [AIModelOptionGroup] {
        AIModelOption.availableGroups(
            settings: core.aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI)
    }

    /// Shortened here, not by layout: a flexible label would take the row from the search field.
    var selectedModelTitle: String {
        guard let selected = core.aiSettings.defaultModel else { return "Choose Model" }
        let title = selectedModelOption?.title ?? selected.model
        guard title.count > Self.maxModelTitleLength else { return title }
        let keep = Self.maxModelTitleLength / 2
        return "\(title.prefix(keep))…\(title.suffix(keep))"
    }

    private static let maxModelTitleLength = 26

    /// From the selection, not the loaded list: the list arrives after the picker first paints.
    var selectedModelIcon: PopoverMenuIcon {
        switch core.aiSettings.defaultModel {
        case .appleIntelligence?: return AIModelOption.appleIntelligenceIcon
        case .codex?: return .asset(AIBrand.openAI.assetName)
        case .claude?: return .asset(AIBrand.claude.assetName)
        case .openCode(let model, _)?: return AIModelOption.icon(AIBrand.resolve(model: model))
        case .api(let connection, let model, _)?:
            return AIModelOption.icon(
                core.aiSettings.connection(id: connection).flatMap {
                    AIBrand.resolve(provider: $0.provider, model: model)
                })
        case nil: return AIModelOption.icon(nil)
        }
    }

    /// Fetches the list so the title is a name, and a default can resolve without Settings.
    /// What entering chat costs once: the model list resolved, and the servers connected.
    func prepareForChat() {
        warmUpModelList()
        core.mcpCoordinator.warmUp()
    }

    func warmUpModelList() {
        guard let stored = core.aiSettings.defaultModel else {
            prepareModelSwitcher()
            core.aiSettings.resolveDefaultModel()
            return
        }
        // Only an installed route needs checking; every other one is already settled on disk.
        if stored.source.installedKind != nil { prepareModelSwitcher() }
    }

    private var selectedModelOption: AIModelOption? {
        guard let selected = core.aiSettings.defaultModel else { return nil }
        return modelOptions.first { $0.matches(selected) }
    }

    func selectModel(_ option: AIModelOption) {
        core.aiSettings.select(
            AIModelOption.withDefaultEffort(
                option.selection, settings: core.aiSettings,
                subscription: core.chatGPTSubscription, installedAI: core.installedAI))
    }

    var reasoningEfforts: [ChatGPTSubscription.Effort] {
        AIModelOption.efforts(
            for: core.aiSettings.defaultModel, settings: core.aiSettings,
            subscription: core.chatGPTSubscription, installedAI: core.installedAI)
    }

    var selectedReasoningTitle: String {
        guard let selected = core.aiSettings.defaultModel?.effort,
            let effort = reasoningEfforts.first(where: { $0.id == selected })
        else { return "Reasoning" }
        return effort.title
    }

    func selectReasoningEffort(_ effort: ChatGPTSubscription.Effort) {
        guard let selection = core.aiSettings.defaultModel else { return }
        core.aiSettings.select(selection.withEffort(effort.id))
    }

    @discardableResult
    func prepareModelSwitcher() -> Task<Void, Never> {
        core.applyInstalledAILifecycle()
    }

    func showSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        settingsCoordinator.showSettings(tab: .ai)
    }

    func availability() -> String? {
        do {
            _ = try core.aiProvider()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

struct AIModelOption: Identifiable {
    let selection: AIModelSelection
    let title: String
    let sourceTitle: String
    let menuIcon: PopoverMenuIcon

    static let appleIntelligenceIcon = PopoverMenuIcon.symbol("apple.intelligence")

    @MainActor
    static func availableGroups(
        settings: AISettingsStore, subscription: ChatGPTSubscriptionManager,
        installedAI: InstalledAIManager
    ) -> [AIModelOptionGroup] {
        let enabled = settings.enabledInstalledProviders
        let claude = installedAI.status(for: .claude)
        let openCode = installedAI.status(for: .openCode)
        return groupedCatalog(
            appleIntelligence: settings.isAppleIntelligenceAvailable(),
            codex: enabled.contains(.codex) && subscription.isConnected
                ? subscription.models : [],
            claude: enabled.contains(.claude) && claude.isReady ? claude.models : [],
            openCode: enabled.contains(.openCode) && openCode.isReady ? openCode.models : [],
            connections: settings.connections)
    }

    /// An unrecognised model keeps the generic sparkle rather than borrowing someone's mark.
    static func icon(_ brand: AIBrand?) -> PopoverMenuIcon {
        brand.map { .asset($0.assetName) } ?? .symbol("sparkles")
    }

    /// Every route the Mac can reach, on-device first: it is the one an unconfigured Mac has.
    private static func catalog(
        appleIntelligence: Bool,
        codex: [ChatGPTSubscription.Model],
        claude: [InstalledAIModel],
        openCode: [InstalledAIModel],
        connections: [AIConnection]
    ) -> [AIModelOption] {
        let onDevice =
            appleIntelligence
            ? [
                AIModelOption(
                    selection: .appleIntelligence, title: AppleIntelligence.title,
                    sourceTitle: "On device", menuIcon: appleIntelligenceIcon)
            ] : []
        let codex = codex.map { model in
            AIModelOption(
                selection: .codex(model: model.id, effort: nil),
                title: model.name,
                sourceTitle: "Codex",
                menuIcon: .asset(AIBrand.openAI.assetName))
        }
        let claude = claude.map { model in
            AIModelOption(
                selection: .claude(model: model.id, effort: nil), title: model.name,
                sourceTitle: "Claude", menuIcon: .asset(AIBrand.claude.assetName))
        }
        let openCode = openCode.map { model in
            AIModelOption(
                selection: .openCode(model: model.id, effort: nil), title: model.name,
                sourceTitle: "OpenCode", menuIcon: icon(AIBrand.resolve(model: model.id)))
        }
        let api = connections.flatMap { connection in
            connection.models.map { model in
                AIModelOption(
                    selection: .api(connection: connection.id, model: model, effort: nil),
                    title: model,
                    sourceTitle: connection.title,
                    menuIcon: icon(AIBrand.resolve(provider: connection.provider, model: model)))
            }
        }
        return onDevice + codex + claude + openCode + api
    }

    private static func groupedCatalog(
        appleIntelligence: Bool,
        codex: [ChatGPTSubscription.Model],
        claude: [InstalledAIModel],
        openCode: [InstalledAIModel],
        connections: [AIConnection]
    ) -> [AIModelOptionGroup] {
        var groups: [AIModelOptionGroup] = []
        for option in catalog(
            appleIntelligence: appleIntelligence, codex: codex, claude: claude,
            openCode: openCode, connections: connections)
        {
            if groups.last?.id == option.selection.source {
                groups[groups.count - 1].options.append(option)
            } else {
                groups.append(
                    AIModelOptionGroup(
                        source: option.selection.source, title: option.sourceTitle,
                        options: [option]))
            }
        }
        return groups
    }

    /// The model list only names a route; the effort it comes with is the one that route defaults to.
    @MainActor
    static func withDefaultEffort(
        _ selection: AIModelSelection, settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager
    ) -> AIModelSelection {
        let model = selection.model
        let effort: String?
        switch selection.source {
        case .appleIntelligence:
            return selection
        case .codex:
            effort = subscription.models.first { $0.id == model }?.resolvedEffort(nil)
        case .claude, .openCode:
            effort = installedAI.models(for: selection.source)
                .first { $0.id == model }?.resolvedEffort(nil)
        case .api(let connection):
            effort = settings.connection(id: connection)?
                .reasoningOptions?[model]?.resolvedEffort(nil)
        }
        return selection.withEffort(effort)
    }

    @MainActor
    static func efforts(
        for selection: AIModelSelection?, settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager
    ) -> [ChatGPTSubscription.Effort] {
        guard let selection else { return [] }
        let model = selection.model
        switch selection.source {
        case .appleIntelligence:
            return []
        case .codex:
            return subscription.models.first { $0.id == model }?.efforts ?? []
        case .claude, .openCode:
            return installedAI.models(for: selection.source).first { $0.id == model }?.efforts ?? []
        case .api(let connection):
            return settings.connection(id: connection)?.reasoningOptions?[model]?
                .efforts.map { ChatGPTSubscription.Effort(id: $0, detail: nil) } ?? []
        }
    }

    var id: AIModelSelection { selection }
    func matches(_ other: AIModelSelection) -> Bool {
        selection.source == other.source && selection.model == other.model
    }
}

struct AIModelOptionGroup: Identifiable {
    let source: AIModelSource
    let title: String
    var options: [AIModelOption]
    var id: AIModelSource { source }
}
