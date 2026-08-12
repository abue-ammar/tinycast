import AppKit
import Foundation

/// What the palette is showing for the running command.
enum ExtensionSessionState: Equatable {
    case idle
    case launching
    case rendered(RenderTree)
    case failed(String)
    /// A no-view command that ran to completion.
    case finished
}

/// Owns the installed set, the JS runtime and the one running command.
///
/// **One command at a time.** Starting a command stops whatever was running first. Host calls carry no
/// session id, so `activeExtensionName` is what namespaces storage, cache and preferences — an
/// invariant the single-session rule is what makes safe. It also matches the UI: the palette shows one
/// extension screen.
@MainActor
@Observable
final class ExtensionManager: ExtensionRuntimeDelegate, ExtensionHostContext {
    private(set) var installed: [InstalledExtension] = []
    private(set) var state: ExtensionSessionState = .idle
    /// The command whose session is live, if any.
    private(set) var running: ExtensionCommandRef?
    /// Toasts the running command asked for, newest last.
    private(set) var toasts: [ExtensionToast] = []
    /// Depth of the extension's own navigation stack; >1 means Escape should pop rather than close.
    private(set) var navigationDepth = 1

    /// The master switch. Off means nothing is scanned, nothing is published and no context exists —
    /// the feature costs what an unused stored property costs. `ExtensionCoordinator` sets it.
    private(set) var isEnabled = false
    /// Whether the commands reach the launcher at all; independent of `isEnabled`.
    private(set) var showsInLauncher = true

    let storage: ExtensionStorage
    /// Per-extension icon overrides, owned here alongside `storage` for the same reason: both are
    /// extension-scoped state the launcher and Settings read through this manager.
    let appearances = ExtensionAppearanceStore()
    @ObservationIgnored private let runtime: ExtensionRuntime
    @ObservationIgnored private let bridge: ExtensionHostBridge
    @ObservationIgnored private weak var appIndex: AppIndex?
    @ObservationIgnored private weak var coordinator: ExtensionCoordinator?

    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var nextToastID = 1

    init(clipboardStore: ClipboardStore) {
        storage = ExtensionStorage(directory: ExtensionCatalog.storageDirectory())
        bridge = ExtensionHostBridge(clipboardStore: clipboardStore)
        runtime = ExtensionRuntime(hostAPI: bridge)
        bridge.context = self
    }

    /// Wires the collaborators only. The coordinator applies the switches straight after, which is
    /// what decides whether anything is scanned at all.
    func start(appIndex: AppIndex, coordinator: ExtensionCoordinator) {
        self.appIndex = appIndex
        self.coordinator = coordinator
        runtime.setDelegate(self)
    }

    // MARK: - The switches

    /// Turning off tears everything down: the running command, the JS context and the launcher rows.
    /// Turning on re-scans. Both are idempotent, so applying settings on launch is the same call.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        guard enabled else {
            await stop()
            installed = []
            appIndex?.setExtensionCommands([])
            return
        }
        await refresh()
    }

    func setShowsInLauncher(_ shows: Bool) {
        guard shows != showsInLauncher else { return }
        showsInLauncher = shows
        publishLauncherEntries()
    }

    // MARK: - Installed set

    func refresh() async {
        guard isEnabled else { return }
        let found = await Task.detached(priority: .utility) { ExtensionCatalog.scan() }.value
        guard found != installed else { return }
        installed = found
        publishLauncherEntries()
    }

    func extensionNamed(_ name: String) -> InstalledExtension? {
        installed.first { $0.manifest.name == name }
    }

    /// Surface every runnable command as a launcher row. Menu-bar commands are listed too — activating
    /// one explains why it can't run, which beats silently hiding it.
    private func publishLauncherEntries() {
        guard isEnabled, showsInLauncher else {
            appIndex?.setExtensionCommands([])
            return
        }
        let entries = installed.flatMap { installedExtension -> [AppEntry] in
            let iconPath = installedExtension.iconPath
            // A chosen appearance replaces the shipped icon for every command of the extension.
            let appearance = appearances.appearance(for: installedExtension.manifest.name)
            return installedExtension.manifest.commands.compactMap { command -> AppEntry? in
                let reference = ExtensionCommandRef(
                    extensionName: installedExtension.manifest.name, commandName: command.name)
                return AppEntry(
                    id: reference.entryID,
                    name: command.title,
                    url: installedExtension.directory,
                    bundleID: nil,
                    kind: .extensionCommand,
                    imageIconPath: appearance == nil
                        ? (commandIconPath(command, in: installedExtension) ?? iconPath) : nil,
                    kindLabelOverride: installedExtension.title,
                    appearance: appearance)
            }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        appIndex?.setExtensionCommands(entries)
    }

    /// Settings picked (or cleared) an icon: persist it and re-publish, so the launcher rows change
    /// under the user rather than on the next scan.
    func setAppearance(_ appearance: ExtensionAppearance?, for extensionName: String) {
        appearances.set(appearance, for: extensionName)
        publishLauncherEntries()
    }

    /// Bulk apply from a settings backup.
    func replaceAppearances(_ overrides: [String: ExtensionAppearance]) {
        appearances.replace(overrides)
        publishLauncherEntries()
    }

    private func commandIconPath(_ command: ExtensionCommand, in owner: InstalledExtension) -> String? {
        guard let icon = command.icon else { return nil }
        let candidate = owner.directory.appendingPathComponent("assets").appendingPathComponent(icon)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate.path : nil
    }

    // MARK: - Install / uninstall

    func install(from source: URL) async throws {
        _ = try ExtensionCatalog.install(from: source)
        await refresh()
    }

    func uninstall(_ installedExtension: InstalledExtension) async {
        if running?.extensionName == installedExtension.manifest.name { await stop() }
        try? ExtensionCatalog.uninstall(installedExtension)
        storage.removeAll(extension: installedExtension.manifest.name)
        await refresh()
    }

    // MARK: - Running a command

    enum LaunchError: LocalizedError {
        case unknownCommand(String)
        case unsupported(String)
        case notBuilt(String)
        case missingPreferences([ExtensionPreferenceSchema])

        var errorDescription: String? {
            switch self {
            case .unknownCommand(let id): return "No installed extension provides '\(id)'."
            case .unsupported(let reason): return reason
            case .notBuilt(let name):
                return "\(name) has no built bundle — reinstall the extension."
            case .missingPreferences(let schemas):
                let names = schemas.map(\.displayTitle).joined(separator: ", ")
                return "This command needs its preferences set first: \(names)."
            }
        }
    }

    /// Resolve a launcher row to a command, or nil when the row isn't an extension command.
    func resolve(_ entry: AppEntry) -> (InstalledExtension, ExtensionCommand)? {
        guard let reference = ExtensionCommandRef(entryID: entry.id),
            let owner = extensionNamed(reference.extensionName),
            let command = owner.command(named: reference.commandName)
        else { return nil }
        return (owner, command)
    }

    func run(_ entry: AppEntry, arguments: [String: String] = [:]) async {
        guard let (owner, command) = resolve(entry) else {
            state = .failed(LaunchError.unknownCommand(entry.id).localizedDescription)
            return
        }
        await run(owner, command: command, arguments: arguments)
    }

    func run(
        _ owner: InstalledExtension, command: ExtensionCommand, arguments: [String: String] = [:]
    ) async {
        await stop()

        if let reason = command.mode.unsupportedReason {
            state = .failed(reason)
            running = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            return
        }
        let schemas = owner.manifest.preferences + command.preferences
        let missing = storage.missingRequiredPreferences(
            extension: owner.manifest.name, schemas: schemas)
        guard missing.isEmpty else {
            running = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            state = .failed(LaunchError.missingPreferences(missing).localizedDescription)
            return
        }
        guard let bundle = owner.bundleURL(for: command) else {
            running = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            state = .failed(LaunchError.notBuilt(command.title).localizedDescription)
            return
        }

        running = ExtensionCommandRef(extensionName: owner.manifest.name, commandName: command.name)
        navigationDepth = 1
        state = .launching

        let supportPath = ExtensionCatalog.supportPath(for: owner.manifest.name)
        try? FileManager.default.createDirectory(at: supportPath, withIntermediateDirectories: true)

        do {
            // No-op while a context is already up; after `stop()` this builds a fresh one.
            try await runtime.boot(config: .current(supportDirectory: supportPath))
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        // Reading the bundle is IO on a file that can be a few hundred KB; keep it off the main actor.
        let code = await Task.detached(priority: .userInitiated) {
            (try? String(contentsOf: bundle, encoding: .utf8)) ?? ""
        }.value
        guard !code.isEmpty else {
            state = .failed(LaunchError.notBuilt(command.title).localizedDescription)
            return
        }

        let session = UUID().uuidString
        sessionID = session
        let context = ExtensionLaunchContext(
            extensionName: owner.manifest.name,
            extensionTitle: owner.title,
            commandName: command.name,
            commandMode: command.mode,
            assetsPath: owner.assetsPath,
            supportPath: supportPath.path,
            preferences: storage.resolvedPreferences(
                extension: owner.manifest.name, schemas: schemas),
            caches: storage.caches(extension: owner.manifest.name),
            arguments: command.completeArguments(arguments),
            fallbackText: nil)

        await runtime.start(
            session: session, code: code, file: bundle, mode: command.mode, context: context)
    }

    func stop() async {
        guard let sessionID else {
            resetSessionState()
            return
        }
        self.sessionID = nil
        await runtime.stop(session: sessionID)
        // Then discard the context outright, so nothing an extension left behind reaches the next run.
        runtime.shutdown()
        storage.flush()
        resetSessionState()
    }

    private func resetSessionState() {
        state = .idle
        running = nil
        toasts = []
        navigationDepth = 1
    }

    // MARK: - Events from the palette

    func dispatch(handler: String, arguments: [Any] = []) {
        guard let sessionID else { return }
        let payload = ExtensionRuntime.jsonString(from: arguments)
        Task { await runtime.dispatch(session: sessionID, handler: handler, payload: payload) }
    }

    /// Escape inside a pushed screen pops the extension's stack; returns false when there's nothing to
    /// pop and the palette should close instead.
    func popNavigation() async -> Bool {
        guard let sessionID, navigationDepth > 1 else { return false }
        return await runtime.popNavigation(session: sessionID)
    }

    func runToastAction(token: String) {
        Task { await runtime.runToastAction(token: token) }
    }

    // MARK: - ExtensionRuntimeDelegate

    func runtime(_ runtime: ExtensionRuntime, session: String, didRender tree: RenderTree) {
        guard session == sessionID else { return }
        state = .rendered(tree)
        navigationDepth = tree.depth
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didFail message: String) {
        guard session == sessionID else { return }
        state = .failed(message)
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, navigationDepth depth: Int) {
        guard session == sessionID else { return }
        navigationDepth = depth
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didFinish: Void) {
        guard session == sessionID else { return }
        // A no-view command is done: the palette is already closing, so just release the session.
        state = .finished
        Task { await stop() }
    }

    func runtime(_ runtime: ExtensionRuntime, log level: String, message: String) {
        #if DEBUG
            print("[extension \(level)] \(message)")
        #endif
    }

    // MARK: - ExtensionHostContext

    var activeExtensionName: String? { running?.extensionName }
    var pasteTarget: NSRunningApplication? { coordinator?.pasteTarget }
    var applicationURLs: [URL] { coordinator?.applicationURLs ?? [] }

    func closeMainWindow(clearRootSearch: Bool) {
        coordinator?.closeMainWindow()
    }

    func reopenPalette() {
        coordinator?.reopenPalette(hasRunningCommand: running != nil)
    }

    func popToRoot() {
        coordinator?.popExtensionToRoot()
    }

    func clearSearchBar() {
        coordinator?.clearSearchBar()
    }

    func openPreferences(scope: String) {
        guard let running, let owner = extensionNamed(running.extensionName) else { return }
        coordinator?.showExtensionSettings(for: owner)
    }

    func present(toast: ExtensionToast) -> Int {
        var stamped = toast
        stamped.id = nextToastID
        nextToastID += 1
        // A no-view command's toast has no palette to appear in; show it as a HUD instead of dropping it.
        guard coordinator?.isPaletteVisible == true else {
            coordinator?.showHUD(
                [toast.title, toast.message].compactMap { $0 }.joined(separator: " — "))
            return stamped.id
        }
        toasts.append(stamped)
        // Non-animated toasts self-dismiss; an animated one stays until the command hides it.
        if stamped.style != .animated { scheduleToastDismissal(id: stamped.id) }
        return stamped.id
    }

    func update(toast id: Int, with toast: ExtensionToast) {
        guard let index = toasts.firstIndex(where: { $0.id == id }) else { return }
        var stamped = toast
        stamped.id = id
        toasts[index] = stamped
        if stamped.style != .animated { scheduleToastDismissal(id: id) }
    }

    func hide(toast id: Int) {
        toasts.removeAll { $0.id == id }
    }

    private func scheduleToastDismissal(id: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.hide(toast: id)
        }
    }

    func showHUD(_ text: String) {
        coordinator?.showHUD(text)
    }

    func confirmAlert(_ alert: ExtensionAlert) async -> Bool {
        let panel = NSAlert()
        panel.messageText = alert.title
        if let message = alert.message { panel.informativeText = message }
        panel.alertStyle = alert.isDestructive ? .warning : .informational
        panel.addButton(withTitle: alert.primaryTitle)
        panel.addButton(withTitle: alert.dismissTitle)
        return panel.runModal() == .alertFirstButtonReturn
    }

    func openWithPicker(path: String) async {
        let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: target)
        guard candidates.count > 1 else {
            NSWorkspace.shared.open(target)
            return
        }
        let panel = NSAlert()
        panel.messageText = "Open With"
        panel.informativeText = target.lastPathComponent
        for candidate in candidates.prefix(4) {
            panel.addButton(withTitle: candidate.deletingPathExtension().lastPathComponent)
        }
        panel.addButton(withTitle: "Cancel")
        let response = panel.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard response >= 0, response < min(candidates.count, 4) else { return }
        NSWorkspace.shared.open(
            [target], withApplicationAt: candidates[Int(response)],
            configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// `launchCommand` from a running command: same extension unless it names another.
    func launch(command name: String, extensionName: String?, arguments: [String: String]) throws {
        let owningName = extensionName ?? running?.extensionName
        guard let owningName, let owner = extensionNamed(owningName),
            let command = owner.command(named: name)
        else { throw LaunchError.unknownCommand(name) }
        Task { await run(owner, command: command, arguments: arguments) }
    }
}
