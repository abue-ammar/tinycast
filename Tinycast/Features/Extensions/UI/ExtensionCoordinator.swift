import Foundation

/// Extension commands in the launcher: their rows, the one run funnel and the extension screen.
@MainActor
@Observable
final class ExtensionCoordinator {
    /// The view command on the extension screen, until the screen closes.
    struct Shown {
        let id: ExtensionCommandID
        let session: ExtensionSession
    }

    /// One row per command of every bundle that may run, read from manifests alone.
    private(set) var entries: [AppEntry] = []
    private(set) var shown: Shown?

    private let settings: AppSettings
    private let appIndex: AppIndex
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    @ObservationIgnored private var bundles: [String: ExtensionBundle] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        settings: AppSettings, appIndex: AppIndex, palette: PaletteState,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func name(of id: ExtensionCommandID) -> String? {
        lookUp(id)?.command.title
    }

    // MARK: - Feature presence

    /// Off drops every row and leaves the screen; the manager has already stopped the processes.
    func applyPresence() {
        guard settings.extensionsEnabled else {
            refreshTask?.cancel()
            refreshTask = nil
            publish([])
            return
        }
        refresh()
    }

    /// A newer refresh replaces one in flight, so a switch flipped meanwhile is never lost.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard settings.extensionsEnabled else { return nil }
        refreshTask?.cancel()
        let developerMode = isDeveloperModeOn
        let task = Task {
            let found = await Self.scan(developerMode: developerMode)
            guard !Task.isCancelled, settings.extensionsEnabled else { return }
            refreshTask = nil
            publish(found)
        }
        refreshTask = task
        return task
    }

    private var isDeveloperModeOn: Bool {
        #if DEBUG
            settings.extensionDeveloperMode
        #else
            false
        #endif
    }

    @concurrent
    private static func scan(developerMode: Bool) async -> [ExtensionBundle] {
        ExtensionBundle.available(developerMode: developerMode)
    }

    /// A screen whose extension is no longer listed is left, so it never shows a command that's gone.
    private func publish(_ found: [ExtensionBundle]) {
        bundles = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let shown, bundles[shown.id.extensionID] == nil { leaveScreen() }
        let rows = found.flatMap { bundle in bundle.manifest.commands.map { AppEntry(bundle, command: $0) } }
        guard rows != entries else { return }
        entries = rows
        appIndex.setExtensionCommands(rows)
    }

    // MARK: - Running

    /// The one funnel for a launcher row, a global shortcut and a link.
    func run(_ id: ExtensionCommandID) {
        guard settings.extensionsEnabled else { return }
        if let found = lookUp(id) { return start(id, bundle: found.bundle, mode: found.command.mode) }
        // A chord can name a command packed or installed since the last scan.
        guard let scan = refresh() else { return }
        Task {
            await scan.value
            guard settings.extensionsEnabled, let found = lookUp(id) else { return }
            start(id, bundle: found.bundle, mode: found.command.mode)
        }
    }

    private func start(
        _ id: ExtensionCommandID, bundle: ExtensionBundle, mode: ExtensionManifest.Command.Mode
    ) {
        switch mode {
        case .view:
            openScreen(id, bundle: bundle)
        case .noView, .menuBar:
            // A menu-bar command run here renders a snapshot no item draws yet; it idles out.
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette() }
            core.extensions.run(bundle, command: id.command, reason: .user)
        }
    }

    /// A second press of the command's shortcut closes its screen, as for every palette mode.
    private func openScreen(_ id: ExtensionCommandID, bundle: ExtensionBundle) {
        if paletteCoordinator.isShowing(.extensionCommand), let shown, shown.id == id,
            shown.session.state != .gone
        {
            paletteCoordinator.hidePalette()
            return
        }
        closeScreen()
        guard let session = core.extensions.run(bundle, command: id.command, reason: .user),
            session.state != .gone
        else { return }
        session.isShown = true
        shown = Shown(id: id, session: session)
        paletteCoordinator.showPalette(mode: .extensionCommand)
    }

    /// Leaving the screen any way ends its command.
    func closeScreen() {
        shown?.session.stop(.closed)
        shown = nil
    }

    private func leaveScreen() {
        if palette.mode == .extensionCommand { palette.prepare(mode: .launcher) }
        closeScreen()
    }

    func search(_ text: String) {
        guard let session = shown?.session, session.ui?.handlesSearch == true else { return }
        session.send(.search(text: text))
    }

    func select(_ row: String?) {
        shown?.session.send(.select(item: row))
    }

    func perform(_ action: String) {
        shown?.session.send(.action(action))
    }

    private func lookUp(
        _ id: ExtensionCommandID
    ) -> (bundle: ExtensionBundle, command: ExtensionManifest.Command)? {
        guard let bundle = bundles[id.extensionID],
            let command = bundle.manifest.commands.first(where: { $0.name == id.command })
        else { return nil }
        return (bundle, command)
    }
}

private extension AppEntry {
    /// Named as the extension wrote it, with the extension's name as what the command acts on.
    init(_ bundle: ExtensionBundle, command: ExtensionManifest.Command) {
        self.init(
            id: ExtensionCommandID(extensionID: bundle.id, command: command.name).entryID,
            name: command.title, url: bundle.url, bundleID: nil, kind: .extensionCommand,
            subtitle: bundle.manifest.name,
            iconOverride: .image(path: bundle.iconURL.path, stamp: bundle.iconStamp))
    }
}
