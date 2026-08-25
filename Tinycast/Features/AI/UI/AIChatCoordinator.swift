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
            core.chatGPTSubscription.stop()
            core.chatHistory.close()
            if palette.mode == .ai || palette.mode == .aiHistory { palette.prepare(mode: .launcher) }
            return
        }
        // Deferred off the launch path like the clipboard's own read; history fills in behind it.
        Task { core.chatHistory.load() }
    }

    func showChat() {
        guard settings.aiEnabled else { return }
        paletteCoordinator.showPalette(mode: .ai)
    }

    @discardableResult
    func send(_ input: String) -> Bool {
        guard settings.aiEnabled else { return false }
        do {
            let webSearch = core.aiSettings.webSearchEnabled && capabilities.webSearch
            return chat.send(
                input, using: try core.aiProvider(), webSearch: webSearch,
                instructions: AIInstructions.compose(userPrompt: core.aiSettings.systemPrompt))
        } catch {
            chat.report(error.localizedDescription)
            return false
        }
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
        case .chatGPT?: return .chatGPT
        case .api(let connection, let model)?:
            return core.aiSettings.connection(id: connection)?.capabilities(for: model)
                ?? AIModelCapabilities(images: false, webSearch: false)
        case nil: return AIModelCapabilities(images: false, webSearch: false)
        }
    }

    /// ⌘V with a picture on the pasteboard — a screenshot, or an image file from Finder — stages
    /// it; anything with text pastes as text. False lets the field editor have the chord.
    ///
    /// The pasteboard is read here and the picture decoded off-main: unpacking, rescaling and
    /// re-encoding a display-sized screenshot is megabytes of work that has no business on a
    /// keystroke.
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

    /// The file first and the raw pasteboard bytes as the fallback, in the order they were decoded
    /// inline. A refusal is explained where it happened, and the chord is consumed either way: ⌘V on
    /// a picture never falls through to the field editor pasting its path as text.
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
        let subscription = core.chatGPTSubscription.models.map { model in
            AIModelOption(
                selection: .chatGPT(
                    model: model.id, effort: model.resolvedEffort(nil)),
                title: model.name,
                sourceTitle: "ChatGPT",
                brand: .openAI)
        }
        let api = core.aiSettings.connections.flatMap { connection in
            connection.models.map { model in
                AIModelOption(
                    selection: .api(connection: connection.id, model: model),
                    title: model,
                    sourceTitle: connection.title,
                    brand: AIBrand.resolve(provider: connection.provider, model: model))
            }
        }
        return subscription + api
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
        let brand: AIBrand?
        switch core.aiSettings.defaultModel {
        case .chatGPT?: brand = .openAI
        case .api(let connection, let model)?:
            brand = core.aiSettings.connection(id: connection).flatMap {
                AIBrand.resolve(provider: $0.provider, model: model)
            }
        case nil: brand = nil
        }
        return brand.map { .asset($0.assetName) } ?? .symbol("sparkles")
    }

    /// Opening the chat on a ChatGPT model fetches its list, so the title is the display name
    /// rather than the raw id until the first send would have loaded it. With nothing stored, that
    /// same fetch is what lets the app resolve a default rather than send the reader to Settings.
    func warmUpModelList() {
        let stored = core.aiSettings.defaultModel
        if stored == nil {
            prepareModelSwitcher()
            resolveDefaultModel()
            awaitModelList()
            return
        }
        guard case .chatGPT? = stored else { return }
        prepareModelSwitcher()
    }

    /// Resolving a first default used to live only in the settings pane, so a signed-in
    /// subscription still asked the reader to go there and pick what the app already knew about.
    func resolveDefaultModel() {
        guard core.aiSettings.defaultModel == nil, let first = modelOptions.first else { return }
        core.aiSettings.select(first.selection)
    }

    /// A subscription signs in after the screen is already up, so its model list arrives late;
    /// without this the empty state sits there until the reader leaves and comes back.
    private func awaitModelList() {
        withObservationTracking {
            _ = core.chatGPTSubscription.models
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.core.aiSettings.defaultModel == nil else { return }
                self.resolveDefaultModel()
                if self.core.aiSettings.defaultModel == nil { self.awaitModelList() }
            }
        }
    }

    private var selectedModelOption: AIModelOption? {
        guard let selected = core.aiSettings.defaultModel else { return nil }
        return modelOptions.first { $0.matches(selected) }
    }

    func selectModel(_ option: AIModelOption) {
        core.aiSettings.select(option.selection)
    }

    func prepareModelSwitcher() {
        if core.chatGPTSubscription.phase == .idle {
            core.chatGPTSubscription.refresh()
        }
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
    /// The vendor's mark for the picker row; `nil` keeps the generic sparkle.
    let brand: AIBrand?

    var id: AIModelSelection { selection }
    var menuTitle: String { "\(title) · \(sourceTitle)" }
    var menuIcon: PopoverMenuIcon { brand.map { .asset($0.assetName) } ?? .symbol("sparkles") }

    func matches(_ other: AIModelSelection) -> Bool {
        selection.source == other.source && selection.model == other.model
    }
}
