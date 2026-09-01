import AppKit

/// Owns the library and one serial execution funnel for action chains.
@MainActor
final class ActionChainCoordinator {
    private let store: ActionChainStore
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private unowned let core: AppCore
    private var isRunning = false

    init(
        store: ActionChainStore, appIndex: AppIndex, hotKeys: HotKeyManager,
        favorites: FavoritesStore, visibility: VisibilityStore, ranking: LauncherRankingStore,
        core: AppCore
    ) {
        self.store = store
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.core = core
    }

    func applyActionChainsPresence() { appIndex.setActionChains(store.chains) }

    func runActionChain(id: UUID) {
        guard let chain = store.chain(id: id), !isRunning else { return }
        isRunning = true
        let target = core.paletteCoordinator.targetApp
        if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        Task {
            defer { isRunning = false }
            let result = await ActionChainRunner.run(chain) { [weak self] step in
                guard let self else { throw ActionChainFailure.unavailable }
                try await self.perform(step, target: target)
            }
            guard case .failed(let step) = result else { return }
            await core.showNotice(
                title: "“\(chain.name)” Stopped", message: "\(step.title) is no longer available.",
                symbol: ActionChain.sfSymbol, tone: .danger)
        }
    }

    @discardableResult
    func addActionChain(_ draft: ActionChain) throws -> ActionChain { try store.add(draft) }

    func updateActionChain(_ draft: ActionChain) throws { try store.update(draft) }

    @discardableResult
    func replaceActionChains(_ chains: [ActionChain]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.chains.map { ($0.id, $0) })
        let count = store.replace(with: chains)
        let removed = Set(previous.keys).subtracting(store.chains.map(\.id))
        removeActionChainReferences(
            ids: removed, entryIDs: Set(removed.compactMap { previous[$0]?.entryID }))
        return count
    }

    func deleteActionChain(id: UUID) {
        guard let chain = store.chain(id: id) else { return }
        store.remove(id: id)
        removeActionChainReferences(ids: [id], entryIDs: [chain.entryID])
    }

    private func removeActionChainReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.actionChain(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        for entryID in entryIDs { ranking.reset(itemKey: entryID) }
    }

    private func perform(_ step: ActionChainStep, target: NSRunningApplication?) async throws {
        switch step {
        case .application(let bundleID):
            guard
                let app = appIndex.apps.first(where: {
                    $0.kind == .application && $0.bundleID == bundleID
                })
            else { throw ActionChainFailure.unavailable }
            AppLauncher.launch(app.url)
        case .systemAction(let rawID):
            guard let id = SystemAction.ID(rawValue: rawID),
                SystemActionCatalog.action(id: id).confirmation == .none
            else { throw ActionChainFailure.unavailable }
            _ = try await SystemActionRunner.run(
                id, previousApp: target)
        case .windowCommand(let rawID):
            guard let id = WindowCommand.ID(rawValue: rawID),
                core.settings.windowManagementEnabled
                    && SpaceDirection(id) == nil
            else { throw ActionChainFailure.unavailable }
            guard
                core.windowMover.perform(
                    id, target: target, gap: CGFloat(core.settings.windowGap),
                    cycleOnRepeat: core.settings.windowCycleOnRepeat)
            else { throw ActionChainFailure.unavailable }
        case .customCommand(let id):
            guard let command = core.customCommands.command(id: id), command.isEnabled,
                command.arguments.isEmpty, !command.requiresConfirmation
            else { throw ActionChainFailure.unavailable }
            let result = await ShellCommandRunner.run(
                command.command, loadingShellEnvironment: command.loadsShellEnvironment,
                workingDirectory: command.workingDirectory)
            guard result.succeeded else { throw ActionChainFailure.unavailable }
        case .quicklink(let id):
            guard let quicklink = core.quicklinks.quicklink(id: id), quicklink.isEnabled,
                !QuicklinkDestination.containsPlaceholder(quicklink.link)
            else { throw ActionChainFailure.unavailable }
            try await QuicklinkLauncher.open(
                quicklink.link, openWithBundleID: quicklink.openWithBundleID,
                inNewWindow: core.settings.quicklinkOpensNewWindow)
        }
    }
}

extension ActionChainStep {
    var title: String {
        switch self {
        case .application: return "Application"
        case .systemAction: return "System action"
        case .windowCommand: return "Window command"
        case .customCommand: return "Custom command"
        case .quicklink: return "Quicklink"
        }
    }
}
