import AppKit

/// Owns custom commands: the library, the one run funnel with its gate, and a deletion's cleanup.
@MainActor
final class CustomCommandCoordinator {
    private let store: CustomCommandStore
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

    init(
        store: CustomCommandStore,
        settings: AppSettings,
        appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
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

    /// The one funnel for palette and hotkey, so the confirmation can't be bypassed.
    func runCustomCommand(id: UUID) {
        // Also the feature switch: with it off a registered hotkey must run nothing.
        guard settings.customCommandsEnabled else { return }
        guard let command = store.command(id: id) else { return }
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
            let outcome = await ShellCommandRunner.run(
                command.command, loadingShellEnvironment: command.loadsShellEnvironment)
            guard outcome != .success else {
                // On finish, not start, so a slow command confirms late rather than early.
                if command.showsConfirmation {
                    core.showMessage("Ran \(command.name)")
                }
                return
            }
            await presentCustomCommandFailure(command: command, outcome: outcome)
        }
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

    private func presentCustomCommandFailure(
        command: CustomCommand, outcome: ShellCommandOutcome
    ) async {
        let message: String
        // `127` is "command not found", where a config-only alias lands.
        var suggestsShellEnvironment = false
        switch outcome {
        case .success:
            return
        case .launchFailure(let detail):
            message = "The shell could not be started.\n\n\(detail)"
        case .nonZeroExit(let status, let stderr):
            suggestsShellEnvironment = status == 127 && !command.loadsShellEnvironment
            message =
                "The command exited with status \(status)."
                + (stderr.map { "\n\n" + $0 } ?? "")
                + (suggestsShellEnvironment
                    ? "\n\nIf this is a shell alias or function, turn on Load Shell Environment for "
                        + "this command." : "")
        }
        guard
            await core.reportFailure(
                title: "“\(command.name)” Failed", message: message,
                symbol: CustomCommand.sfSymbol,
                recovery: suggestsShellEnvironment ? "Open Settings…" : nil)
        else { return }
        settingsCoordinator.showSettings(tab: .commands)
    }
}
