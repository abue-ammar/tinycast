import AppKit

/// Owns the uninstall flow: the scan hand-off, the one confirmation funnel, the reference cleanup.
@MainActor
final class UninstallCoordinator {
    private let session: UninstallSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let appIndex: AppIndex
    private let runningApps: RunningAppsMonitor
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    /// Dialog and message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore

    init(
        session: UninstallSession,
        palette: PaletteState,
        paletteCoordinator: PaletteCoordinator,
        appIndex: AppIndex,
        runningApps: RunningAppsMonitor,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        core: AppCore
    ) {
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.appIndex = appIndex
        self.runningApps = runningApps
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.core = core
    }

    /// The palette is already up, so this swaps the sub-screen rather than re-showing it.
    func beginUninstall(_ app: AppEntry) {
        guard app.kind == .application else { return }
        // What stops a name or a shared bundle-ID namespace being misattributed.
        let others = appIndex.apps.filter { $0.kind == .application && $0.id != app.id }
        session.begin(
            app: app, otherAppNames: others.map(\.name),
            otherBundleIDs: others.compactMap(\.bundleID), isRunning: runningApps.isRunning(app))
        palette.prepare(mode: .uninstall)
    }

    /// The one funnel for the screen's ↵ and Actions row, so neither skips the confirmation.
    func performUninstall() {
        guard let app = session.app, let plan = session.plan, session.canConfirm else { return }
        let items = session.selectedCandidates
        guard !items.isEmpty else { return }
        Task {
            let running = plan.isTargetRunning || runningApps.isRunning(app)
            let size = MeasuredSize(bytes: items.reduce(0) { $0 + ($1.size?.bytes ?? 0) }).formatted
            let count = items.count == 1 ? "1 item" : "\(items.count) items"
            guard
                await core.confirm(
                    title: "Uninstall “\(app.name)”?",
                    message: "\(count) (\(size)) will be moved to the Trash, where you can put them "
                        + "back." + (running ? " \(app.name) will quit first." : ""),
                    symbol: "trash", confirmTitle: "Move to Trash")
            else { return }

            if running, let bundleID = app.bundleID { _ = AppLauncher.quit(bundleID: bundleID) }
            session.setTrashing(true)
            let report = await UninstallRunner.moveToTrash(items)
            session.setTrashing(false)

            if report.removedBundle {
                removeUninstalledReferences(app)
                await appIndex.refresh()
            }
            palette.prepare(mode: .launcher)
            await presentUninstallReport(report)
        }
    }

    /// Stays on the screen: losing a whole scan to copy one path is a poor trade.
    func copyUninstallPath(_ candidate: UninstallCandidate) {
        Paster.copyPlainText(candidate.path)
        core.showMessage("Copied path")
    }

    func showUninstallItemInFinder(_ candidate: UninstallCandidate) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(candidate.url)
    }

    func showUninstallItemInfo(_ candidate: UninstallCandidate) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            guard await !AppLauncher.showInfoInFinder(candidate.url) else { return }
            await core.showNotice(
                title: "Couldn’t Open Get Info",
                message: "Allow Tinycast to control Finder in System Settings › Privacy & Security "
                    + "› Automation, then try again.",
                symbol: "info.circle", tone: .danger)
        }
    }

    private func removeUninstalledReferences(_ app: AppEntry) {
        if let action = app.hotKeyAction {
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: [app.preferenceKey])
        visibility.removeItemKeys([app.preferenceKey])
        ranking.reset(itemKey: app.preferenceKey)
        aliases.removeKeys([app.preferenceKey])
    }

    private func presentUninstallReport(_ report: UninstallReport) async {
        guard report.hasFailures else {
            guard report.trashedCount > 0 else { return }
            let count = report.trashedCount == 1 ? "1 item" : "\(report.trashedCount) items"
            let freed = MeasuredSize(bytes: report.freedBytes).formatted
            core.showMessage("Moved \(count) to the Trash · \(freed)")
            return
        }
        let listed = report.failed.prefix(5).map { "\($0.name) — \($0.reason)" }
        let remaining = report.failed.count - listed.count
        await core.showNotice(
            title: report.trashedCount > 0 ? "Some Items Weren’t Moved" : "Nothing Was Moved",
            message: listed.joined(separator: "\n")
                + (remaining > 0 ? "\nand \(remaining) more." : ""),
            symbol: "trash", tone: .danger)
    }
}
