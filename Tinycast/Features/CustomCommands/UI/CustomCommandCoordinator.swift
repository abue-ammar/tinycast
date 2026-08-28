import AppKit

/// Owns custom commands: the library, the one run funnel with its gates, and a deletion's cleanup.
@MainActor
final class CustomCommandCoordinator {
    private let store: CustomCommandStore
    private let argumentSession: CustomCommandArgumentSession
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    /// Dialog and message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore
    /// Built on first use: most installs never turn output on, and it holds a window.
    private lazy var outputPresenter = CommandOutputPresenter(
        activation: activationPolicy,
        rerun: { [unowned self] in self.runCustomCommand(id: $0) },
        stop: { [unowned self] in self.stopOutputRun(id: $0) },
        openSettings: { [unowned self] in self.settingsCoordinator.showSettings(tab: .commands) })
    private let activationPolicy: ActivationPolicy
    /// The live streaming run, so Stop has something to signal. Superseding never touches it — only
    /// the button ends a command.
    private var liveRun: (id: UUID, stop: @Sendable () -> Void)?

    init(
        store: CustomCommandStore,
        argumentSession: CustomCommandArgumentSession,
        settings: AppSettings,
        appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        activationPolicy: ActivationPolicy,
        core: AppCore
    ) {
        self.store = store
        self.argumentSession = argumentSession
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.activationPolicy = activationPolicy
        self.core = core
    }

    // MARK: - Feature presence

    func applyCustomCommandsPresence() {
        let visible = settings.customCommandsEnabled && settings.customCommandsShowInLauncher
        appIndex.setCustomCommands(visible ? store.commands : [])
    }

    // MARK: - Library

    @discardableResult
    func addCustomCommand(_ draft: CustomCommand) throws -> CustomCommand {
        try store.add(draft)
    }

    func updateCustomCommand(_ draft: CustomCommand) throws {
        try store.update(draft)
    }

    func deleteCustomCommand(id: UUID) {
        guard let command = store.command(id: id) else { return }
        removeCustomCommandReferences(ids: [id], entryIDs: [command.entryID])
        store.remove(id: id)
    }

    @discardableResult
    func replaceCustomCommands(_ commands: [CustomCommand]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.commands.map { ($0.id, $0) })
        let count = store.replace(with: commands)
        let liveIDs = Set(store.commands.map(\.id))
        let removed = Set(previous.keys).subtracting(liveIDs)
        let removedEntryIDs = Set(removed.compactMap { previous[$0]?.entryID })
        removeCustomCommandReferences(ids: removed, entryIDs: removedEntryIDs)
        return count
    }

    // MARK: - Running

    /// The one funnel for palette and hotkey, so neither the argument form nor the confirmation
    /// can be bypassed.
    func runCustomCommand(id: UUID) {
        // Also the feature switch: with it off a registered hotkey must run nothing.
        guard settings.customCommandsEnabled else { return }
        guard let command = store.command(id: id) else { return }
        guard command.arguments.isEmpty else {
            argumentSession.begin(command: command)
            // Never a restored mode: this screen is always a fresh prompt, never a resumed one.
            paletteCoordinator.showPalette(mode: .customCommandArguments)
            return
        }
        perform(command, arguments: [])
    }

    /// ↵ in the argument form. Returns false while more arguments remain.
    @discardableResult
    func submitCustomCommandArgument(_ value: String) -> Bool {
        guard let filled = argumentSession.submit(value) else { return false }
        argumentSession.cancel()
        perform(filled.command, arguments: filled.values)
        return true
    }

    func cancelCustomCommandArguments() {
        argumentSession.cancel()
    }

    private func perform(_ command: CustomCommand, arguments: [String]) {
        guard settings.customCommandsEnabled else { return }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        Task {
            if command.requiresConfirmation {
                guard
                    // Neutral, not destructive: their own command just wants a second tap.
                    await core.confirm(
                        title: command.name,
                        message: "Are you sure you want to run this command?\n\n\(command.command)",
                        symbol: CustomCommand.sfSymbol, confirmTitle: "Run",
                        tone: .neutral, confirmRole: .standard)
                else { return }
            }
            guard !command.showsOutput else {
                await streamOutput(of: command, arguments: arguments)
                return
            }
            let result = await ShellCommandRunner.run(
                command.command, arguments: arguments,
                loadingShellEnvironment: command.loadsShellEnvironment)
            await report(command, result: result)
        }
    }

    /// Opens the window before the first byte, so a long command is visible while it works.
    private func streamOutput(of command: CustomCommand, arguments: [String]) async {
        let session = ShellCommandRunner.stream(
            command.command, arguments: arguments,
            loadingShellEnvironment: command.loadsShellEnvironment)
        let runID = outputPresenter.begin(
            commandID: command.id, name: command.name, commandText: command.command)
        liveRun = (runID, session.stop)
        defer { if liveRun?.id == runID { liveRun = nil } }

        for await event in session.events {
            switch event {
            case .output(let text):
                outputPresenter.append(text, to: runID)
            case .finished(let result):
                outputPresenter.finish(
                    CommandOutcome(
                        summary: summary(of: result),
                        hint: shellEnvironmentHint(command: command, result: result),
                        succeeded: result.succeeded, finishedAt: Date()),
                    for: runID)
            }
        }
    }

    private func stopOutputRun(id: UUID) {
        guard let liveRun, liveRun.id == id else { return }
        liveRun.stop()
    }

    private func removeCustomCommandReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.customCommand(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    // MARK: - Reporting

    /// Only the non-streaming path reaches here: a window that already says how the run ended must
    /// not also raise a dialog saying it again.
    private func report(_ command: CustomCommand, result: ShellCommandResult) async {
        guard !result.succeeded else {
            // On finish, not start, so a slow command confirms late rather than early.
            if command.showsConfirmation { core.showMessage("Ran \(command.name)") }
            return
        }
        let hint = shellEnvironmentHint(command: command, result: result)
        guard
            await core.reportFailure(
                title: "“\(command.name)” Failed",
                message: failureMessage(command: command, result: result),
                symbol: CustomCommand.sfSymbol, recovery: hint == nil ? nil : "Open Settings…")
        else { return }
        settingsCoordinator.showSettings(tab: .commands)
    }

    private func summary(of result: ShellCommandResult) -> String {
        switch result.termination {
        case .launchFailed: return "The shell could not be started."
        case .stopped: return "Stopped"
        case .exited(let status):
            return status == 0 ? "Finished successfully." : "The command exited with status \(status)."
        }
    }

    private func failureMessage(command: CustomCommand, result: ShellCommandResult) -> String {
        var parts = [summary(of: result)]
        if case .launchFailed(let detail) = result.termination { parts.append(detail) }
        if let standardError = result.standardError { parts.append(standardError) }
        if let hint = shellEnvironmentHint(command: command, result: result) { parts.append(hint) }
        return parts.joined(separator: "\n\n")
    }

    /// `127` is "command not found", where a config-only alias lands — but equally a plain typo, so
    /// this is gated on the status alone rather than on grepping stderr.
    private func shellEnvironmentHint(
        command: CustomCommand, result: ShellCommandResult
    ) -> String? {
        guard case .exited(status: 127) = result.termination, !command.loadsShellEnvironment else {
            return nil
        }
        return "If this is a shell alias or function, turn on Load Shell Environment for this command."
    }
}
