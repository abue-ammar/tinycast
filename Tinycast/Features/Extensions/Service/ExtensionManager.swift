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

/// Owns the installed set, the runtime and the one running command. See docs/features/extensions.md.
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

    /// Off means nothing scanned, published or held: the feature costs an unused stored property.
    private(set) var isEnabled = false
    /// Whether the commands reach the launcher at all; independent of `isEnabled`.
    private(set) var showsInLauncher = true

    let storage: ExtensionStorage
    /// Extension-scoped state the launcher and Settings read through here, like `storage`.
    let appearances = ExtensionAppearanceStore()
    @ObservationIgnored private let runtime: ExtensionRuntime
    @ObservationIgnored private let bridge: ExtensionHostBridge
    @ObservationIgnored private weak var appIndex: AppIndex?
    @ObservationIgnored private weak var coordinator: ExtensionCoordinator?

    /// The entry ids an uninstall invalidated, so another feature can drop what it keyed to them.
    @ObservationIgnored var onDidUninstall: (([String]) -> Void)?

    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var nextToastID = 1

    init(clipboardStore: ClipboardStore) {
        storage = ExtensionStorage(directory: ExtensionCatalog.storageDirectory())
        bridge = ExtensionHostBridge(clipboardStore: clipboardStore)
        runtime = ExtensionRuntime(hostAPI: bridge)
        bridge.context = self
    }

    /// Wires collaborators only; the coordinator applies the switches, deciding whether anything scans.
    func start(appIndex: AppIndex, coordinator: ExtensionCoordinator) {
        self.appIndex = appIndex
        self.coordinator = coordinator
        runtime.setDelegate(self)
        // Not gated on `isEnabled`: a stranded workspace is ours whether or not the feature is on.
        let temp = FileManager.default.temporaryDirectory
        Task.detached(priority: .utility) { ExtensionCleanup.sweepWorkspaces(in: temp) }
    }

    // MARK: - The switches

    /// Idempotent both ways, so applying settings on launch is the same call as flipping the switch.
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

    /// Built from the installed set, not `AppIndex`: a shortcut can fire before a row ever exists.
    func launcherEntry(forEntryID entryID: String) -> AppEntry? {
        guard let reference = ExtensionCommandRef(entryID: entryID),
            let owner = extensionNamed(reference.extensionName),
            let command = owner.command(named: reference.commandName)
        else { return nil }
        return entry(for: command, in: owner)
    }

    /// Menu-bar commands are listed too: activating one explains itself, which beats hiding it.
    private func publishLauncherEntries() {
        guard isEnabled, showsInLauncher else {
            appIndex?.setExtensionCommands([])
            return
        }
        let entries =
            installed
            .flatMap { owner in owner.manifest.commands.map { entry(for: $0, in: owner) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        appIndex?.setExtensionCommands(entries)
    }

    /// One command as a row; a chosen appearance replaces the shipped icon for all of them.
    private func entry(for command: ExtensionCommand, in owner: InstalledExtension) -> AppEntry {
        let appearance = appearances.appearance(for: owner.manifest.name)
        let reference = ExtensionCommandRef(
            extensionName: owner.manifest.name, commandName: command.name)
        return AppEntry(
            id: reference.entryID,
            name: command.title,
            url: owner.directory,
            bundleID: nil,
            kind: .extensionCommand,
            iconOverride: icon(for: command, in: owner, appearance: appearance),
            labelOverride: owner.title)
    }

    /// Persist and re-publish, so rows change under the user rather than on the next scan.
    func setAppearance(_ appearance: ExtensionAppearance?, for extensionName: String) {
        appearances.set(appearance, for: extensionName)
        publishLauncherEntries()
    }

    /// Bulk apply from a settings backup.
    func replaceAppearances(_ overrides: [String: ExtensionAppearance]) {
        appearances.replace(overrides)
        publishLauncherEntries()
    }

    /// An appearance wins, else the shipped artwork: the launcher is handed the answer, not the why.
    private func icon(
        for command: ExtensionCommand, in owner: InstalledExtension,
        appearance: ExtensionAppearance?
    ) -> EntryIcon {
        if let appearance {
            return .tintedSymbol(name: appearance.symbol, tint: appearance.tint.symbolTint)
        }
        guard let path = commandIconPath(command, in: owner) ?? owner.iconPath else {
            return .symbol("puzzlepiece.extension")
        }
        return .artwork(path: path, extent: ExtensionIconCache.extent)
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

    /// Scanned off-main: it reads a manifest per directory, and a full Raycast install is dozens.
    func raycastImportCandidates() async -> [RaycastImportCandidate] {
        let candidates = await Task.detached(priority: .userInitiated) {
            ExtensionCatalog.importableFromRaycast()
        }.value
        let have = Set(installed.map(\.manifest.name))
        return candidates.map {
            RaycastImportCandidate(installed: $0, isInstalled: have.contains($0.manifest.name))
        }
    }

    /// Progress is reported per step: building from source can take minutes.
    func install(
        listing: ExtensionListing, packageManager: ExtensionPackageManager,
        onProgress: @Sendable @escaping (ExtensionInstaller.Progress) -> Void
    ) async throws {
        let installer = ExtensionInstaller(packageManager: packageManager)
        try await installer.install(listing, onProgress: onProgress)
        await refresh()
    }

    /// Refreshes once at the end, and returns what failed so the pane can name it.
    @discardableResult
    func importAllFromRaycast(
        _ candidates: [InstalledExtension], onProgress: (Int) -> Void = { _ in }
    ) async -> [String] {
        var failed: [String] = []
        for (index, candidate) in candidates.enumerated() {
            do {
                _ = try ExtensionCatalog.install(from: candidate.directory)
            } catch {
                failed.append(candidate.title)
            }
            onProgress(index + 1)
        }
        await refresh()
        return failed
    }

    /// Takes everything keyed to it: files, storage, icon, and through `onDidUninstall` its shortcuts.
    func uninstall(_ installedExtension: InstalledExtension) async {
        if running?.extensionName == installedExtension.manifest.name { await stop() }
        let entryIDs = installedExtension.manifest.commands.map {
            ExtensionCommandRef(
                extensionName: installedExtension.manifest.name, commandName: $0.name
            ).entryID
        }
        try? ExtensionCatalog.uninstall(installedExtension)
        storage.removeAll(extension: installedExtension.manifest.name)
        appearances.set(nil, for: installedExtension.manifest.name)
        onDidUninstall?(entryIDs)
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

    /// Pops the extension's stack; false when there is nothing to pop and the palette should close.
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
        await coordinator?.confirmExtensionAlert(alert) ?? false
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
