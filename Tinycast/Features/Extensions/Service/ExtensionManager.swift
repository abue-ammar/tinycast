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

/// Owns the installed set, the runtime and the running command.
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

    var isAuthorizing: Bool { oauthSession.isAuthorizing }

    let storage: ExtensionStorage
    /// Extension-scoped state the launcher and Settings read through here, like `storage`.
    let appearances = ExtensionAppearanceStore()
    private let commandMetadata = ExtensionCommandMetadataStore(
        fileURL: ExtensionCatalog.commandMetadataFile())
    @ObservationIgnored private let runtime: ExtensionRuntime
    @ObservationIgnored private let bridge: ExtensionHostBridge
    @ObservationIgnored private let oauthSession = ExtensionOAuthSession()
    @ObservationIgnored private weak var appIndex: AppIndex?
    @ObservationIgnored private weak var coordinator: ExtensionCoordinator?

    /// The entry ids an uninstall invalidated, so another feature can drop what it keyed to them.
    @ObservationIgnored var onDidUninstall: (([String]) -> Void)?

    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var backgroundSessionID: String?
    @ObservationIgnored private var backgroundRef: ExtensionCommandRef?
    @ObservationIgnored private var backgroundContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var backgroundFailure: String?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private var nextToastID = 1
    @ObservationIgnored private var lastOAuthExtensionName: String?

    init(clipboardStore: ClipboardStore) {
        storage = ExtensionStorage(directory: ExtensionCatalog.storageDirectory())
        bridge = ExtensionHostBridge(clipboardStore: clipboardStore)
        runtime = ExtensionRuntime(hostAPI: bridge)
        bridge.context = self
    }

    /// Wires collaborators only; the coordinator decides whether anything scans.
    func start(appIndex: AppIndex, coordinator: ExtensionCoordinator) {
        self.appIndex = appIndex
        self.coordinator = coordinator
        runtime.setDelegate(self)
        // Not gated on `isEnabled`: a stranded workspace is ours whether or not the feature is on.
        let temp = FileManager.default.temporaryDirectory
        Task.detached(priority: .utility) { ExtensionCleanup.sweepWorkspaces(in: temp) }
    }

    // MARK: - The switches

    /// Idempotent both ways, so launch and the switch are the same call.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        guard enabled else {
            await stop()
            backgroundTask?.cancel()
            backgroundTask = nil
            installed = []
            appIndex?.setExtensionCommands([])
            return
        }
        await refresh()
        ensureBackgroundLoop()
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
        restartBackgroundLoop()
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
        let metadata = commandMetadata.metadata(
            extension: owner.manifest.name, command: command.name)
        // A dropped `interval` retires the dot with it, however stale the stored flag is.
        let schedulable = ExtensionRefreshPolicy.isSchedulable(
            mode: command.mode, interval: command.interval)
        return AppEntry(
            id: reference.entryID,
            name: command.title,
            url: owner.directory,
            bundleID: nil,
            kind: .extensionCommand,
            subtitle: ExtensionRefreshPolicy.displaySubtitle(
                manifest: command.subtitle, override: metadata.subtitle, ownerTitle: owner.title),
            backgroundRefresh: ExtensionRefreshPolicy.indicator(
                schedulable: schedulable, backgroundEnabled: metadata.backgroundEnabled,
                lastError: metadata.lastError),
            iconOverride: icon(for: command, in: owner, appearance: appearance),
            ownerName: owner.title)
    }

    /// Persist and re-publish, so rows change under the user rather than on the next scan.
    func setAppearance(_ appearance: ExtensionAppearance?, for extensionName: String) {
        appearances.set(appearance, for: extensionName)
        publishLauncherEntries()
    }

    /// An appearance wins, else the shipped artwork; the launcher gets the answer.
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
        additionalSearchPaths: [String] = [],
        onProgress: @Sendable @escaping (ExtensionInstaller.Progress) -> Void
    ) async throws {
        let installer = ExtensionInstaller(
            packageManager: packageManager, additionalSearchPaths: additionalSearchPaths)
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

    /// Takes everything keyed to it: files, storage, icon, and its shortcuts.
    func uninstall(_ installedExtension: InstalledExtension) async {
        if running?.extensionName == installedExtension.manifest.name { await stop() }
        if backgroundRef?.extensionName == installedExtension.manifest.name {
            await abortBackgroundRun()
        }
        let entryIDs = installedExtension.manifest.commands.map {
            ExtensionCommandRef(
                extensionName: installedExtension.manifest.name, commandName: $0.name
            ).entryID
        }
        ExtensionOAuthKeychain.removeAllTokens(extensionName: installedExtension.manifest.name)
        try? ExtensionCatalog.uninstall(installedExtension)
        storage.removeAll(extension: installedExtension.manifest.name)
        commandMetadata.removeAll(extension: installedExtension.manifest.name)
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
            case .unknownCommand(let id): return String(
                localized: "No installed extension provides '\(id)'.",
                bundle: .appLanguage)
            case .unsupported(let reason): return reason
            case .notBuilt(let name):
                return String(localized: "\(name) has no built bundle — reinstall the extension.", bundle: .appLanguage)
            case .missingPreferences(let schemas):
                let names = schemas.map(\.displayTitle).joined(separator: ", ")
                return String(localized: "This command needs its preferences set first: \(names).", bundle: .appLanguage)
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

        // The runtime holds one context: a background tick in flight yields to the manual run.
        await abortBackgroundRun()

        // Raycast activates the schedule on first manual open; the run itself is the first refresh.
        if ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval) {
            commandMetadata.activateBackgroundRefresh(
                extension: owner.manifest.name, command: command.name, now: Date())
            restartBackgroundLoop()
        }

        let supportPath = ExtensionCatalog.supportPath(for: owner.manifest.name)
        try? FileManager.default.createDirectory(at: supportPath, withIntermediateDirectories: true)

        do {
            // No-op while a context is already up; after `stop()` this builds a fresh one.
            try await runtime.boot(config: .current(supportDirectory: supportPath))
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        // Reading a few hundred KB of bundle is IO; keep it off the main actor.
        let code = await Task.detached(priority: .userInitiated) {
            (try? String(contentsOf: bundle, encoding: .utf8)) ?? ""
        }.value
        guard !code.isEmpty else {
            state = .failed(LaunchError.notBuilt(command.title).localizedDescription)
            return
        }

        let session = UUID().uuidString
        sessionID = session
        let context = makeLaunchContext(
            owner: owner, command: command, arguments: arguments, supportPath: supportPath,
            launchType: .userInitiated)

        await runtime.start(
            session: session, code: code, file: bundle, mode: command.mode, context: context)
    }

    private func makeLaunchContext(
        owner: InstalledExtension, command: ExtensionCommand, arguments: [String: String],
        supportPath: URL, launchType: ExtensionLaunchType
    ) -> ExtensionLaunchContext {
        let schemas = owner.manifest.preferences + command.preferences
        return ExtensionLaunchContext(
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
            fallbackText: nil,
            launchType: launchType,
            isDarkAppearance: NSApp.effectiveAppearance.isDark)
    }

    func stop() async {
        oauthSession.cancel()
        guard let sessionID else {
            resetSessionState()
            return
        }
        self.sessionID = nil
        await runtime.stop(session: sessionID)
        // Discard the context outright, so nothing left behind reaches the next run.
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

    // MARK: - Background refresh

    func backgroundInfo(extension name: String, command: String) -> ExtensionCommandMetadata {
        commandMetadata.metadata(extension: name, command: command)
    }

    func setBackgroundEnabled(_ enabled: Bool, extension name: String, command: String) {
        commandMetadata.setBackgroundEnabled(enabled, extension: name, command: command)
        if !enabled { commandMetadata.clearBackgroundError(extension: name, command: command) }
        publishLauncherEntries()
        restartBackgroundLoop()
    }

    /// Whether the Actions menu can offer refresh controls for this row.
    func isBackgroundSchedulable(for entry: AppEntry) -> Bool {
        guard let (_, command) = resolve(entry) else { return false }
        return ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval)
    }

    func isBackgroundEnabled(for entry: AppEntry) -> Bool {
        guard let reference = ExtensionCommandRef(entryID: entry.id) else { return false }
        return commandMetadata.metadata(
            extension: reference.extensionName, command: reference.commandName
        ).backgroundEnabled
    }

    func toggleBackgroundRefresh(for entry: AppEntry) {
        guard let reference = ExtensionCommandRef(entryID: entry.id),
            isBackgroundSchedulable(for: entry)
        else { return }
        let enabled = commandMetadata.metadata(
            extension: reference.extensionName, command: reference.commandName
        ).backgroundEnabled
        setBackgroundEnabled(!enabled, extension: reference.extensionName, command: reference.commandName)
    }

    /// One headless run right now, without touching the enable flag or the palette.
    func refreshNow(_ entry: AppEntry) {
        guard let (owner, command) = resolve(entry),
            ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval),
            running == nil, backgroundSessionID == nil
        else { return }
        Task { [weak self] in
            await self?.runInBackground(owner, command: command)
            self?.restartBackgroundLoop()
        }
    }

    /// Starts the loop once, and only when a command wants it: with nothing enabled there is
    /// no task at all, so an unused schedule costs nothing.
    private func ensureBackgroundLoop() {
        guard isEnabled, backgroundTask == nil, hasEnabledBackgroundCommands else { return }
        backgroundTask = Task { [weak self] in await self?.backgroundLoop() }
    }

    /// Whether any installed command currently wants background ticks.
    private var hasEnabledBackgroundCommands: Bool {
        schedulableCommands().contains { owner, command in
            commandMetadata.metadata(extension: owner.manifest.name, command: command.name)
                .backgroundEnabled
        }
    }

    private func restartBackgroundLoop() {
        backgroundTask?.cancel()
        backgroundTask = nil
        ensureBackgroundLoop()
    }

    private func backgroundLoop() async {
        try? await Task.sleep(for: .seconds(5))
        while !Task.isCancelled {
            guard isEnabled else { return }
            await runDueBackgroundCommands()
            if Task.isCancelled { return }
            // The last schedule going away stops the loop itself; enabling restarts it.
            guard hasEnabledBackgroundCommands else {
                backgroundTask = nil
                return
            }
            try? await Task.sleep(for: .seconds(nextBackgroundDelay()))
        }
    }

    private func schedulableCommands() -> [(InstalledExtension, ExtensionCommand)] {
        installed.flatMap { owner in
            owner.manifest.commands.compactMap { command in
                guard
                    ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval)
                else { return nil }
                return (owner, command)
            }
        }
    }

    /// Due commands within one window fire as a batch, so close ticks share a single wakeup.
    private func runDueBackgroundCommands() async {
        guard running == nil, backgroundSessionID == nil else { return }
        let now = Date()
        let due = schedulableCommands().filter { owner, command in
            let reference = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            let metadata = commandMetadata.metadata(
                extension: owner.manifest.name, command: command.name)
            guard metadata.backgroundEnabled, let interval = command.interval else { return false }
            return ExtensionRefreshPolicy.nextDue(
                lastRun: metadata.lastRun, now: now, interval: interval,
                consecutiveFailures: metadata.consecutiveFailures, entryID: reference.entryID)
                <= now.addingTimeInterval(ExtensionRefreshPolicy.coalescingWindow)
        }
        guard !due.isEmpty else { return }
        for (owner, command) in due {
            guard !Task.isCancelled, isEnabled, running == nil else { break }
            await runInBackground(owner, command: command)
        }
    }

    /// Capped, so an install or a toggle surfaces without anyone restarting the loop.
    private func nextBackgroundDelay() -> TimeInterval {
        guard running == nil else { return ExtensionRefreshPolicy.coalescingWindow }
        let now = Date()
        var delay = ExtensionRefreshPolicy.idleHeartbeat
        for (owner, command) in schedulableCommands() {
            let reference = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            let metadata = commandMetadata.metadata(
                extension: owner.manifest.name, command: command.name)
            guard metadata.backgroundEnabled, let interval = command.interval else { continue }
            let due = ExtensionRefreshPolicy.nextDue(
                lastRun: metadata.lastRun, now: now, interval: interval,
                consecutiveFailures: metadata.consecutiveFailures, entryID: reference.entryID)
            delay = min(delay, max(due.timeIntervalSince(now), 5))
        }
        return delay
    }

    /// A headless `no-view` run: the palette never moves and no feedback fires, only the subtitle can.
    private func runInBackground(_ owner: InstalledExtension, command: ExtensionCommand) async {
        guard backgroundSessionID == nil, running == nil, let interval = command.interval else {
            return
        }
        guard let bundle = owner.bundleURL(for: command) else { return }
        let reference = ExtensionCommandRef(
            extensionName: owner.manifest.name, commandName: command.name)
        let supportPath = ExtensionCatalog.supportPath(for: owner.manifest.name)
        try? FileManager.default.createDirectory(at: supportPath, withIntermediateDirectories: true)

        let session = UUID().uuidString
        backgroundSessionID = session
        backgroundRef = reference
        backgroundFailure = nil
        var succeeded = false
        defer {
            // Gone mid-run means uninstalled: recording would resurrect its storage file.
            if extensionNamed(reference.extensionName) != nil {
                commandMetadata.recordBackgroundResult(
                    extension: reference.extensionName, command: reference.commandName,
                    success: succeeded, error: succeeded ? nil : (backgroundFailure ?? String(
                        localized: "Timed out.",
                        bundle: .appLanguage)),
                    now: Date())
            }
            backgroundSessionID = nil
            backgroundRef = nil
            backgroundFailure = nil
            backgroundContinuation = nil
            publishLauncherEntries()
            storage.flush()
            commandMetadata.flush()
        }

        do {
            try await runtime.boot(config: .current(supportDirectory: supportPath))
        } catch {
            backgroundFailure = error.localizedDescription
            return
        }
        let code = await Task.detached(priority: .utility) {
            (try? String(contentsOf: bundle, encoding: .utf8)) ?? ""
        }.value
        guard !code.isEmpty else {
            backgroundFailure = LaunchError.notBuilt(command.title).localizedDescription
            return
        }
        let context = makeLaunchContext(
            owner: owner, command: command, arguments: [:], supportPath: supportPath,
            launchType: .background)
        await runtime.start(
            session: session, code: code, file: bundle, mode: command.mode, context: context)
        succeeded = await waitForBackgroundResult(
            timeout: ExtensionRefreshPolicy.timeout(interval: interval))
        // An abort already tore the session down; touching the runtime here would take the
        // manual run's fresh context with it.
        guard backgroundSessionID == session else { return }
        await runtime.stop(session: session)
        runtime.shutdown()
    }

    private func waitForBackgroundResult(timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask { [weak self] in await self?.backgroundSettled() ?? false }
            group.addTask { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                } catch {
                    // Cancelling the loop preempts the tick; only a real timeout is a failure.
                    await self?.resumeBackground(with: true)
                    return true
                }
                await self?.resumeBackground(with: false)
                return false
            }
            defer { group.cancelAll() }
            return await group.next() ?? false
        }
    }

    /// Suspends until the run settles, times out, or is preempted; `resumeBackground` is every exit.
    private func backgroundSettled() async -> Bool {
        await withCheckedContinuation { continuation in backgroundContinuation = continuation }
    }

    /// Ends the in-flight background run as a success so its schedule survives the preemption.
    private func abortBackgroundRun() async {
        guard let session = backgroundSessionID else { return }
        backgroundSessionID = nil
        backgroundRef = nil
        await runtime.stop(session: session)
        runtime.shutdown()
        resumeBackground(with: true)
    }

    /// Main-actor serial, so no two of those exits can resume the same continuation.
    private func resumeBackground(with result: Bool) {
        guard let continuation = backgroundContinuation else { return }
        backgroundContinuation = nil
        continuation.resume(returning: result)
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
        if session == backgroundSessionID {
            backgroundFailure = message
            resumeBackground(with: false)
            return
        }
        guard session == sessionID else { return }
        state = .failed(message)
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, navigationDepth depth: Int) {
        guard session == sessionID else { return }
        navigationDepth = depth
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didFinish: Void) {
        if session == backgroundSessionID {
            resumeBackground(with: true)
            return
        }
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

    var activeExtensionName: String? { backgroundRef?.extensionName ?? running?.extensionName }
    var activeLaunchType: ExtensionLaunchType {
        backgroundSessionID != nil ? .background : .userInitiated
    }
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

    /// The running command's row metadata; a missing key leaves the subtitle alone.
    func updateCommandMetadata(subtitle: String?) {
        guard let reference = backgroundRef ?? running else { return }
        commandMetadata.setSubtitle(
            subtitle, extension: reference.extensionName, command: reference.commandName)
        publishLauncherEntries()
    }

    func present(toast: ExtensionToast) -> Int {
        var stamped = toast
        stamped.id = nextToastID
        nextToastID += 1
        // A no-view command's toast has no palette to appear in, so show a HUD.
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
        panel.messageText = String(localized: "Open With", bundle: .appLanguage)
        panel.informativeText = target.lastPathComponent
        for candidate in candidates.prefix(4) {
            panel.addButton(withTitle: candidate.deletingPathExtension().lastPathComponent)
        }
        panel.addButton(withTitle: String(localized: "Cancel", bundle: .appLanguage))
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

    func authorizeOAuth(options: ExtensionOAuthAuthorizeOptions) async throws -> ExtensionOAuthAuthorizeResult
    {
        lastOAuthExtensionName = running?.extensionName
        return try await oauthSession.authorize(options: options)
    }

    func getOAuthTokens(providerId: String) -> String? {
        guard let extName = running?.extensionName ?? lastOAuthExtensionName else { return nil }
        return ExtensionOAuthKeychain.getTokens(extensionName: extName, providerId: providerId)
    }

    func setOAuthTokens(providerId: String, tokens: String) {
        guard let extName = running?.extensionName ?? lastOAuthExtensionName else { return }
        ExtensionOAuthKeychain.setTokens(tokens, extensionName: extName, providerId: providerId)
    }

    func removeOAuthTokens(providerId: String) {
        guard let extName = running?.extensionName ?? lastOAuthExtensionName else { return }
        ExtensionOAuthKeychain.removeTokens(extensionName: extName, providerId: providerId)
    }
}
