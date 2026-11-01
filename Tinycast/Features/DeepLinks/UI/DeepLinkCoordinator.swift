import AppKit
import OSLog

/// Runs built-in `tinycast://` links; extension links never reach it. See docs/features/deeplinks.md.
@MainActor
final class DeepLinkCoordinator {
    /// A link a quicklink opened was chosen in Tinycast, so only `outside` ever asks.
    enum Source {
        case outside
        case tinycast
    }

    struct AllowedLink: Identifiable {
        let id: String
        let name: String
    }

    private enum ConsentChoice: Int {
        case alwaysAllow, runOnce, cancel
    }

    private static let logger = Logger(subsystem: "com.tinycast", category: "DeepLinks")

    private let scheme: String
    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private unowned let core: AppCore
    private var isAskingConsent = false

    init(
        scheme: String, settings: AppSettings, hotKeys: HotKeyManager,
        paletteCoordinator: PaletteCoordinator, settingsCoordinator: SettingsCoordinator,
        core: AppCore
    ) {
        self.scheme = scheme
        self.settings = settings
        self.hotKeys = hotKeys
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
    }

    func handles(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
            && url.host(percentEncoded: false)?.lowercased() != DeepLink.extensionsHost
    }

    func url(forEntryID entryID: String) -> URL? {
        DeepLink.url(forEntryID: entryID, scheme: scheme)
    }

    func open(_ url: URL, source: Source = .outside) {
        guard let link = DeepLink(url: url, scheme: scheme) else { return reportUnknownLink() }
        switch link {
        case .launcher(let text):
            paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: text == nil, seeding: text)
        case .settings(let slug):
            guard let tab = SettingsTab(slug: slug) else { return reportUnknownLink() }
            settingsCoordinator.showSettings(tab: tab)
        case .entry(let action, let input):
            run(action, input: input, source: source)
        }
    }

    // MARK: - Allowed links

    /// Named for Settings; a row deleted since keeps its ID as its name, so it can still go.
    var allowedLinks: [AllowedLink] {
        settings.deepLinkAllowedEntryIDs.map { entryID in
            let name = HotKeyAction(entryID: entryID).map(hotKeys.displayName(of:))
            return AllowedLink(id: entryID, name: name ?? entryID)
        }
    }

    func revoke(_ link: AllowedLink) {
        settings.deepLinkAllowedEntryIDs.removeAll { $0 == link.id }
    }

    // MARK: - Running

    private func reportUnknownLink() {
        core.showMessage(String(localized: "Tinycast can’t open this link"), tone: .danger)
    }

    private func run(_ action: HotKeyAction, input: DeepLinkInput, source: Source) {
        guard core.allowsHotKeyAction(action) else {
            let name = hotKeys.displayName(of: action)
            core.showMessage(String(localized: "“\(name)” is turned off"), tone: .danger)
            return
        }
        guard source == .outside, DeepLinkConsentPolicy.requiresConsent(action) else {
            return dispatch(action, input: input)
        }
        // Every parsed link names a row; one that didn't would run unasked, so it never runs.
        guard let entryID = action.entryID else { return }
        if settings.deepLinkAllowedEntryIDs.contains(entryID) { return dispatch(action, input: input) }
        askConsent(action, entryID: entryID, input: input)
    }

    private func askConsent(_ action: HotKeyAction, entryID: String, input: DeepLinkInput) {
        guard !isAskingConsent else {
            Self.logger.notice("Dropped a link that arrived while another awaited consent")
            return
        }
        isAskingConsent = true
        let name = hotKeys.displayName(of: action)
        Task {
            let answer = await core.choose(
                title: String(localized: "Run “\(name)” from a link?"),
                message: String(
                    localized: "An app or web page asked Tinycast to run this. Allow only links you trust."),
                symbol: "link",
                options: [
                    DialogAction(title: String(localized: "Always Allow")),
                    DialogAction(title: String(localized: "Run Once")),
                    DialogAction(title: String(localized: "Cancel"), role: .cancel)
                ],
                defaultIndex: ConsentChoice.runOnce.rawValue)
            isAskingConsent = false
            let choice = ConsentChoice(rawValue: answer) ?? .cancel
            // The dialog was a wait, and a feature switched off meanwhile must still win.
            guard choice != .cancel, core.allowsHotKeyAction(action) else { return }
            if choice == .alwaysAllow, !settings.deepLinkAllowedEntryIDs.contains(entryID) {
                settings.deepLinkAllowedEntryIDs.append(entryID)
            }
            dispatch(action, input: input)
        }
    }

    /// Input reaches the targets that take it; everything else runs as its hotkey would.
    private func dispatch(_ action: HotKeyAction, input: DeepLinkInput) {
        if !input.isEmpty, run(action, with: input) { return }
        hotKeys.perform(action)
    }

    private func run(_ action: HotKeyAction, with input: DeepLinkInput) -> Bool {
        switch action {
        case .command(let id):
            return runCommand(id, with: input)
        case .quicklink(let id):
            return openQuicklink(id: id, with: input)
        case .customCommand(let id):
            return runCustomCommand(id: id, with: input)
        default:
            return false
        }
    }

    private func runCommand(_ id: CommandID, with input: DeepLinkInput) -> Bool {
        switch id {
        case .createQuicklink:
            return createQuicklink(from: input)
        case .createSnippet:
            return createSnippet(from: input)
        case .createNote:
            guard let text = input.context["text"] ?? input.fallbackText else { return false }
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
            core.notesCoordinator.createNote(text: text)
            return true
        default:
            guard let text = input.fallbackText else { return false }
            return open(id, with: text)
        }
    }

    /// The screens that take text open on it already typed; it is never sent or run.
    private func open(_ id: CommandID, with text: String) -> Bool {
        switch id {
        case .clipboardHistory: paletteCoordinator.togglePalette(mode: .clipboard, seeding: text)
        case .searchEmoji: paletteCoordinator.togglePalette(mode: .emoji, seeding: text)
        case .calculatorHistory:
            paletteCoordinator.togglePalette(mode: .calculatorHistory, seeding: text)
        case .searchQuicklinks: paletteCoordinator.togglePalette(mode: .quicklinks, seeding: text)
        case .searchFiles: core.fileSearchCoordinator.show(query: text)
        case .define: core.dictionaryCoordinator.show(term: text)
        case .quickAI: core.quickAICoordinator.show(draft: text)
        case .searchSnippets: core.snippetCoordinator.showSnippets(query: text)
        case .searchCustomCommands: core.customCommandCoordinator.showCustomCommands(query: text)
        case .searchMenuItems: core.menuSearchCoordinator.show(query: text)
        case .switchWindows: core.windowSwitchCoordinator.show(query: text)
        default: return false
        }
        return true
    }

    /// `fallbackText` is the link field, the editor's first, as Raycast fills a first input.
    private func createQuicklink(from input: DeepLinkInput) -> Bool {
        let context = input.context
        guard let link = context["link"] ?? input.fallbackText else { return false }
        let openWith = context["openWith"].flatMap { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil ? nil : bundleID
        }
        core.quicklinkCoordinator.createQuicklink(
            name: context["name"] ?? "", link: link, openWithBundleID: openWith)
        return true
    }

    /// Raycast's own payloads say `title` and `snippet` as often as `name` and `text`.
    private func createSnippet(from input: DeepLinkInput) -> Bool {
        let context = input.context
        guard let text = context["text"] ?? context["snippet"] ?? input.fallbackText else {
            return false
        }
        core.snippetCoordinator.createSnippet(
            name: context["name"] ?? context["title"] ?? "", text: text,
            keyword: context["keyword"] ?? "")
        return true
    }

    private func openQuicklink(id: UUID, with input: DeepLinkInput) -> Bool {
        guard let quicklink = core.quicklinks.quicklink(id: id) else { return false }
        guard input.arguments != nil else {
            guard let text = input.fallbackText else { return false }
            core.quicklinkCoordinator.openQuicklink(id: id, filling: text)
            return true
        }
        let names = SnippetTemplateEngine.declaredArguments(in: quicklink.link).map(\.name)
        let values = input.fieldValues(names: names, fieldID: { names[$0] })
        core.quicklinkCoordinator.openQuicklink(id: id, values: values)
        return true
    }

    private func runCustomCommand(id: UUID, with input: DeepLinkInput) -> Bool {
        guard let command = core.customCommands.command(id: id) else { return false }
        let values = input.fieldValues(
            names: command.arguments.map(\.name), fieldID: CustomCommandArgument.fieldID(at:))
        core.customCommandCoordinator.runCustomCommand(id: id, values: values)
        return true
    }
}
