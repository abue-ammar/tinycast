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
        // Never the open policy: a question resumes nothing, and an empty one just opens a chat.
        chat.startNewChat()
        paletteCoordinator.showPalette(mode: .ai)
        send(prompt)
    }

    /// The one place deciding whether summoning resumes; Pop to Root only forgets the screen.
    private func applyOpenPolicy() {
        // A reply still arriving was asked for; resetting would discard the answer.
        guard !chat.isStreaming else { return }
        let recent = core.chatHistory.conversations.first
        let isResident = !chat.session.messages.isEmpty
        // From history when nothing is resident, so the verdict still holds after a relaunch.
        let lastActiveAt = isResident ? chat.session.updatedAt : recent?.updatedAt
        let decision = AIConversationOpenPolicy.decide(
            opensTo: core.aiSettings.opensTo, newAfter: core.aiSettings.newChatAfter,
            lastActiveAt: lastActiveAt, now: Date())
        switch decision {
        case .resume:
            guard !isResident, let recent else { return }
            chat.open(id: recent.id)
        case .startNew:
            guard isResident else { return }
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
            return AIModelCapabilities(images: false, webSearch: false, tools: false)
        case .api(let connection, let model)?:
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

    /// ⌘V stages a picture, decoded off-main; false hands the chord back to the field editor.
    func attachPastedImage() -> Bool {
        guard capabilities.images else { return false }
        let pasteboard = NSPasteboard.general
        let file = Self.pastedImageFile(on: pasteboard)
        let pasted =
            pasteboard.string(forType: .string) == nil
            ? pasteboard.availableType(from: [.png, .tiff]).flatMap { pasteboard.data(forType: $0) }
            : nil
        guard file != nil || pasted != nil else { return false }
        stage(file: file, pasted: pasted)
        return true
    }

    /// The file first, raw bytes as fallback; the chord is consumed, never pasting a path
    private func stage(file: URL?, pasted: Data?) {
        let generation = chat.stagingGeneration
        Task { [weak self] in
            let staged = await Task.detached(priority: .userInitiated) { () -> (Data, String)? in
                if let file, let bytes = try? Data(contentsOf: file),
                    let png = Self.boundedPNG(bytes)
                {
                    return (png, file.lastPathComponent)
                }
                if let pasted, let png = Self.boundedPNG(pasted) { return (png, "Image") }
                return nil
            }.value
            guard let self else { return }
            guard generation == self.chat.stagingGeneration else {
                core.showMessage(
                    "That image was still loading and did not make it into the chat.",
                    tone: .neutral)
                return
            }
            guard let staged else {
                core.showMessage("That image could not be read.", tone: .neutral)
                return
            }
            let attachment = ChatAttachment(
                image: AIImage(data: staged.0, mimeType: "image/png"), name: staged.1)
            if let refusal = chat.attach(attachment) {
                core.showMessage(refusal.message, tone: .neutral)
            }
        }
    }

    private static func pastedImageFile(on pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        return urls.first { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// Backspace on an empty composer takes the last staged image before it backs out of chat.
    func removeLastAttachment() -> Bool {
        chat.removeLastAttachment()
    }

    func clearAttachments() {
        chat.clearAttachments()
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"
    ]

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
        let enabledProviders = core.aiSettings.enabledInstalledProviders
        return enabledProviders.contains(.codex) && core.chatGPTSubscription.phase == .starting
            || [InstalledAIKind.claude, .openCode].contains {
                enabledProviders.contains($0)
                    && core.installedAI.status(for: $0).phase == .checking
            }
    }

    var modelGroups: [AIModelOptionGroup] {
        let claude = core.installedAI.status(for: .claude)
        let openCode = core.installedAI.status(for: .openCode)
        let enabledProviders = core.aiSettings.enabledInstalledProviders
        return AIModelOption.groupedCatalog(
            appleIntelligence: core.aiSettings.isAppleIntelligenceAvailable(),
            codex: enabledProviders.contains(.codex) && core.chatGPTSubscription.isConnected
                ? core.chatGPTSubscription.models : [],
            claude: enabledProviders.contains(.claude) && claude.isReady ? claude.models : [],
            openCode: enabledProviders.contains(.openCode) && openCode.isReady
                ? openCode.models : [],
            connections: core.aiSettings.connections)
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
        case .api(let connection, let model)?:
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
        let stored = core.aiSettings.defaultModel
        if stored == nil {
            prepareModelSwitcher()
            resolveDefaultModel()
            return
        }
        switch stored {
        case .codex?, .claude?, .openCode?: prepareModelSwitcher()
        default: break
        }
    }

    /// Resolve only routes that do not make a new network or account choice for the reader.
    func resolveDefaultModel() {
        core.aiSettings.resolveDefaultModel()
    }

    private var selectedModelOption: AIModelOption? {
        guard let selected = core.aiSettings.defaultModel else { return nil }
        return modelOptions.first { $0.matches(selected) }
    }

    func selectModel(_ option: AIModelOption) {
        core.aiSettings.select(
            AIModelOption.withDefaultEffort(
                option.selection, codex: core.chatGPTSubscription.models,
                claude: core.installedAI.status(for: .claude).models,
                openCode: core.installedAI.status(for: .openCode).models))
    }

    @discardableResult
    func prepareModelSwitcher() -> Task<Void, Never> {
        return core.applyInstalledAILifecycle()
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

    /// An unrecognised model keeps the generic sparkle rather than borrowing someone's mark.
    static func icon(_ brand: AIBrand?) -> PopoverMenuIcon {
        brand.map { .asset($0.assetName) } ?? .symbol("sparkles")
    }

    /// Every route the Mac can reach, on-device first: it is the one an unconfigured Mac has.
    static func catalog(
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
                    selection: .api(connection: connection.id, model: model),
                    title: model,
                    sourceTitle: connection.title,
                    menuIcon: icon(AIBrand.resolve(provider: connection.provider, model: model)))
            }
        }
        return onDevice + codex + claude + openCode + api
    }

    static func groupedCatalog(
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

    static func withDefaultEffort(
        _ selection: AIModelSelection, codex: [ChatGPTSubscription.Model],
        claude: [InstalledAIModel], openCode: [InstalledAIModel]
    ) -> AIModelSelection {
        let effort: String?
        switch selection {
        case .codex(let model, _):
            effort = codex.first { $0.id == model }?.resolvedEffort(nil)
        case .claude(let model, _):
            effort = claude.first { $0.id == model }?.resolvedEffort(nil)
        case .openCode(let model, _):
            effort = openCode.first { $0.id == model }?.resolvedEffort(nil)
        case .appleIntelligence, .api:
            return selection
        }
        return selection.withEffort(effort)
    }

    var id: AIModelSelection { selection }
    var menuTitle: String { "\(title) · \(sourceTitle)" }

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
