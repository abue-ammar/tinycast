import AppKit
import OSLog

/// Runs built-in `tinycast://` links, never extension ones. See docs/features/deeplinks.md.
@MainActor
final class DeepLinkCoordinator {
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

    func open(_ url: URL, source: DeepLinkSource = .outside) {
        guard let link = DeepLink(url: url, scheme: scheme) else { return reportUnknownLink() }
        switch link {
        case .launcher(let text):
            openLauncher(typing: text, source: source)
        case .settings(let slug):
            guard let tab = SettingsTab(slug: slug) else { return reportUnknownLink() }
            settingsCoordinator.showSettings(tab: tab)
        case .note(let name):
            guard isAllowed(.command(.showNotes)) else { return }
            core.notesCoordinator.open(NoteID(rawValue: name))
        case .chat(let id):
            guard isAllowed(.command(.aiChat)) else { return }
            core.aiChatCoordinator.showChat(id: id)
        case .windowSize(let size):
            runWindowSize(size, source: source)
        case .entry(let action, let input):
            run(action, input: input, source: source)
        }
    }

    // MARK: - Building and copying links

    /// Typed field values ride along, so the link fills the fields as they were.
    func url(forEntryID entryID: String, values: [String: String] = [:]) -> URL? {
        DeepLink.url(forEntryID: entryID, scheme: scheme, input: typedInput(values, entryID: entryID))
    }

    func copyLink(toNote id: NoteID) {
        guard let url = DeepLink.url(forNote: id.rawValue, scheme: scheme) else { return }
        copy(url)
    }

    func copyLink(toChat id: UUID) {
        guard let url = DeepLink.url(forChat: id, scheme: scheme) else { return }
        copy(url)
    }

    func copy(_ url: URL) {
        guard Paster.copyPlainText(url.absoluteString) else {
            core.showMessage(String(localized: "Couldn’t copy link"), tone: .danger)
            return
        }
        core.showMessage(String(localized: "Deeplink copied"))
    }

    /// A custom command's fields are `$1`…, so they travel in order; everything else by name.
    private func typedInput(_ values: [String: String], entryID: String) -> DeepLinkInput {
        let typed = values.filter { !$0.value.isEmpty }
        guard !typed.isEmpty else { return .none }
        guard case .customCommand? = HotKeyAction(entryID: entryID) else {
            return DeepLinkInput(arguments: .named(typed))
        }
        let ordered = (0..<CustomCommandArgument.limit).map {
            values[CustomCommandArgument.fieldID(at: $0)] ?? ""
        }
        let filled = ordered.prefix(through: ordered.lastIndex { !$0.isEmpty } ?? 0)
        return DeepLinkInput(arguments: .positional(Array(filled)))
    }

    // MARK: - Allowed links

    /// Named for Settings; a row deleted since keeps its ID as its name, so it can still go.
    var allowedLinks: [AllowedLink] {
        settings.allowedDeepLinks.map { AllowedLink(id: $0, name: consentName(forKey: $0)) }
    }

    func revoke(_ link: AllowedLink) {
        settings.allowedDeepLinks.removeAll { $0 == link.id }
    }

    private func consentName(forKey key: String) -> String {
        if key == DeepLink.windowSizeHost { return String(localized: "Custom Size") }
        guard let parts = DeepLinkConsentPolicy.parts(ofKey: key),
            let action = parts.entryID == DeepLink.searchHost
                ? .togglePalette : HotKeyAction(entryID: parts.entryID)
        else { return key }
        let name = hotKeys.displayName(of: action)
        return parts.input.isEmpty ? name : name + " · " + parts.input.summary
    }

    // MARK: - Running

    private func reportUnknownLink() {
        core.showMessage(String(localized: "Tinycast can’t open this link"), tone: .danger)
    }

    /// The gate hotkeys use, reported rather than silent: a link has no other way to say no.
    private func isAllowed(_ action: HotKeyAction) -> Bool {
        guard core.allowsHotKeyAction(action) else {
            let name = hotKeys.displayName(of: action)
            core.showMessage(String(localized: "“\(name)” is turned off"), tone: .danger)
            return false
        }
        return true
    }

    private func run(_ action: HotKeyAction, input: DeepLinkInput, source: DeepLinkSource) {
        guard source.mayRun(action) else {
            core.showMessage(
                String(localized: "A quicklink can’t open another quicklink"), tone: .danger)
            return
        }
        // Every parsed link names a row; one that didn't would run unasked, so it never runs.
        guard let entryID = action.entryID else { return }
        // Before any question: asking about a row that isn't there only teaches a page what is.
        guard exists(action) else { return reportUnknownLink() }
        guard isAllowed(action) else { return }
        runAfterConsent(
            name: hotKeys.displayName(of: action), input: input,
            key: DeepLinkConsentPolicy.key(entryID: entryID, input: input),
            asks: DeepLinkConsentPolicy.requiresConsent(action, input: input), source: source
        ) { [weak self] in
            // The question was a wait, and a feature switched off meanwhile must still win.
            guard let self, core.allowsHotKeyAction(action) else { return }
            dispatch(action, input: input)
        }
    }

    /// The catalogs' rows always exist; a row you made is known by the name it resolves to.
    private func exists(_ action: HotKeyAction) -> Bool {
        switch action {
        case .command, .systemAction, .windowCommand: true
        default: hotKeys.displayName?(action) != nil
        }
    }

    /// Typed text is one Return from a fallback row, so it asks like any other input.
    private func openLauncher(typing text: String?, source: DeepLinkSource) {
        guard let text else {
            return paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
        }
        let input = DeepLinkInput(fallbackText: text)
        runAfterConsent(
            name: hotKeys.displayName(of: .togglePalette), input: input,
            key: DeepLinkConsentPolicy.key(entryID: DeepLink.searchHost, input: input), asks: true,
            source: source
        ) { [weak self] in
            self?.paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: false, seeding: text)
        }
    }

    private func runWindowSize(_ size: CustomWindowSize, source: DeepLinkSource) {
        let name = String(localized: "Custom Size")
        guard settings.windowManagementEnabled else {
            core.showMessage(String(localized: "“\(name)” is turned off"), tone: .danger)
            return
        }
        runAfterConsent(
            name: name, input: .none, key: DeepLink.windowSizeHost, asks: true, source: source
        ) { [weak self] in
            self?.core.windowCommandCoordinator.runWindowSize(size)
        }
    }

    /// One question at a time; a link arriving meanwhile is dropped, since nobody saw it.
    private func runAfterConsent(
        name: String, input: DeepLinkInput, key: String, asks: Bool, source: DeepLinkSource,
        _ body: @escaping @MainActor () -> Void
    ) {
        guard asks, source == .outside, !settings.allowedDeepLinks.contains(key) else {
            return body()
        }
        guard !isAskingConsent else {
            Self.logger.notice("Dropped a link that arrived while another awaited consent")
            return
        }
        isAskingConsent = true
        Task {
            let choice = await askConsent(name: name, input: input)
            isAskingConsent = false
            guard choice != .cancel else { return }
            if choice == .alwaysAllow, !settings.allowedDeepLinks.contains(key) {
                settings.allowedDeepLinks.append(key)
            }
            body()
        }
    }

    /// Cancel is the default: the panel takes key, and a stray Return must not run anything.
    private func askConsent(name: String, input: DeepLinkInput) async -> ConsentChoice {
        let message =
            input.isEmpty
            ? String(localized: "An app or web page asked Tinycast to run this. Allow only links you trust.")
            : String(
                localized: """
                    An app or web page asked Tinycast to run this with “\(input.summary)”. \
                    Allow only links you trust.
                    """)
        let answer = await core.choose(
            title: String(localized: "Run “\(name)” from a link?"),
            message: message,
            symbol: "link",
            options: [
                DialogAction(title: String(localized: "Always Allow")),
                DialogAction(title: String(localized: "Run Once")),
                DialogAction(title: String(localized: "Cancel"), role: .cancel)
            ],
            defaultIndex: ConsentChoice.cancel.rawValue)
        return ConsentChoice(rawValue: answer) ?? .cancel
    }

    /// Input reaches the targets that take it; everything else runs as its hotkey would.
    private func dispatch(_ action: HotKeyAction, input: DeepLinkInput) {
        if !input.isEmpty, run(action, with: input) { return }
        hotKeys.perform(action)
    }

    // MARK: - Input

    private func run(_ action: HotKeyAction, with input: DeepLinkInput) -> Bool {
        switch action {
        case .command(let id):
            return runCommand(id, with: input)
        case .quicklink(let id):
            return openQuicklink(id: id, with: input)
        case .customCommand(let id):
            return runCustomCommand(id: id, with: input)
        case .systemAction(.setVolume):
            return setVolume(with: input)
        default:
            return false
        }
    }

    private func runCommand(_ id: CommandID, with input: DeepLinkInput) -> Bool {
        switch id {
        case .createQuicklink:
            return createQuicklinks(from: input)
        case .createSnippet:
            return createSnippets(from: input)
        case .createNote:
            guard let text = input.contextFields?["text"] ?? input.fallbackText else { return false }
            hidePalette()
            core.notesCoordinator.createNote(text: text)
            return true
        case .aiChat:
            guard let text = input.fallbackText else { return false }
            hidePalette()
            core.aiChatCoordinator.showWindow(appendingDraft: text)
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

    /// One object fills the editor, a list is a batch that asks first; `fallbackText` is the link.
    private func createQuicklinks(from input: DeepLinkInput) -> Bool {
        if case .list(let list) = input.context {
            let offered = list.map {
                Quicklink(
                    name: $0["name"] ?? "", link: $0["link"] ?? "",
                    openWithBundleID: installedBundleID($0["openWith"]))
            }
            Task { await core.quicklinkCoordinator.importQuicklinks(offered: offered) }
            return true
        }
        let fields = input.contextFields ?? [:]
        guard let link = fields["link"] ?? input.fallbackText else { return false }
        core.quicklinkCoordinator.createQuicklink(
            name: fields["name"] ?? "", link: link, openWithBundleID: installedBundleID(fields["openWith"]))
        return true
    }

    /// As for quicklinks, with `fallbackText` as the snippet's text.
    private func createSnippets(from input: DeepLinkInput) -> Bool {
        if case .list(let list) = input.context {
            let offered = list.compactMap { fields -> Snippet? in
                guard let name = fields["name"], let text = fields["text"], !name.isEmpty, !text.isEmpty
                else { return nil }
                return Snippet(
                    name: name, text: text, keyword: fields["keyword"].flatMap { $0.isEmpty ? nil : $0 })
            }
            Task { await core.snippetCoordinator.importSnippets(offered: offered) }
            return true
        }
        let fields = input.contextFields ?? [:]
        guard let text = fields["text"] ?? input.fallbackText else { return false }
        core.snippetCoordinator.createSnippet(
            name: fields["name"] ?? "", text: text, keyword: fields["keyword"] ?? "")
        return true
    }

    /// Only an app that is installed, so a link can't leave a quicklink pointing at nothing.
    private func installedBundleID(_ bundleID: String?) -> String? {
        bundleID.flatMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) == nil ? nil : $0
        }
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

    /// `volume` by name, in order, or as `fallbackText`; a level that doesn't read is refused.
    private func setVolume(with input: DeepLinkInput) -> Bool {
        let typed = input.fieldValues(names: ["volume"], fieldID: { _ in "volume" })["volume"]
        guard let typed else { return false }
        guard let level = VolumeLevel.level(fromPercent: typed) else {
            reportUnknownLink()
            return true
        }
        core.systemActionCoordinator.setVolume(level)
        return true
    }

    private func hidePalette() {
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
    }
}
