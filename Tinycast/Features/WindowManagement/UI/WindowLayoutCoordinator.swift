import AppKit

/// Owns layouts: the library, the one run funnel with its gate, capture, and a deletion's cleanup.
@MainActor
final class WindowLayoutCoordinator {
    private let store: WindowLayoutStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    /// Dialog and message-HUD presentation, and the editor handoff. Never state this type owns.
    private unowned let core: AppCore
    /// One run at a time: a held shortcut must not stack two passes over the same windows.
    private var run: Task<Void, Never>?

    init(
        store: WindowLayoutStore, settings: AppSettings, appIndex: AppIndex,
        hotKeys: HotKeyManager, favorites: FavoritesStore, visibility: VisibilityStore,
        ranking: LauncherRankingStore, aliases: AliasStore,
        paletteCoordinator: PaletteCoordinator, settingsCoordinator: SettingsCoordinator,
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
    }

    // MARK: - Feature presence

    func applyWindowLayoutsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowLayoutsShowInLauncher
        appIndex.setWindowLayouts(visible ? store.layouts : [])
        appIndex.setCommandsVisible([.createWindowLayout, .captureWindowLayout], visible)
    }

    // MARK: - Running

    /// The one funnel for a palette row, a global shortcut and the pane's Apply alike.
    func runWindowLayout(id: UUID) {
        guard settings.windowManagementEnabled, let layout = store.layout(id: id) else { return }
        // Never restoreFocus: a layout activates the apps it places, and handing focus back
        // first pulls a different app forward mid-pass.
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        let gap = CGFloat(settings.windowGap)
        run?.cancel()
        run = Task { [weak self] in
            let outcome = await WindowLayoutRunner.run(layout, gap: gap)
            await self?.report(outcome, for: layout)
        }
    }

    func prepareForTermination() {
        run?.cancel()
        run = nil
    }

    // MARK: - Library

    @discardableResult
    func addWindowLayout(
        _ draft: WindowLayout
    ) throws(WindowLayoutValidationError) -> WindowLayout {
        try store.add(draft)
    }

    func updateWindowLayout(_ draft: WindowLayout) throws(WindowLayoutValidationError) {
        try store.update(draft)
    }

    func duplicateWindowLayout(id: UUID) {
        do {
            _ = try store.duplicate(id: id)
        } catch {
            Task { await report(failure: error) }
        }
    }

    func deleteWindowLayout(id: UUID) {
        guard let layout = store.remove(id: id) else { return }
        // Unwound only once the row is gone, so a kept record never loses its shortcut.
        removeWindowLayoutReferences(ids: [layout.id], entryIDs: [layout.entryID])
    }

    @discardableResult
    func replaceWindowLayouts(_ incoming: [WindowLayout]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.layouts.map { ($0.id, $0) })
        let count = store.replace(with: incoming)
        let live = Set(store.layouts.map(\.id))
        let removed = Set(previous.keys).subtracting(live)
        removeWindowLayoutReferences(
            ids: removed, entryIDs: Set(removed.compactMap { previous[$0]?.entryID }))
        return count
    }

    // MARK: - Editing

    /// Opens the Window Management pane with the editor showing `layout`; nil is a new one.
    func editWindowLayout(_ layout: WindowLayout?) {
        core.pendingWindowLayoutEdit = WindowLayoutEditRequest(layout: layout)
        settingsCoordinator.showSettings(tab: .windowManagement)
    }

    /// Capture never saves silently: the draft lands in the editor so it can be seen and named.
    func captureWindowLayout() {
        let entries = WindowLayoutRunner.captureCurrentWindows()
        guard !entries.isEmpty else {
            core.showMessage("No windows to capture", tone: .neutral)
            return
        }
        // Gapless by construction, so a later change to `windowGap` can't move every window.
        let draft = WindowLayout(
            name: Self.uniqueCaptureName(among: store.layouts), usesPreferredGap: false,
            entries: entries)
        core.pendingWindowLayoutEdit = WindowLayoutEditRequest(layout: draft, isCapture: true)
        settingsCoordinator.showSettings(tab: .windowManagement)
    }

    // MARK: - Reporting

    private func report(_ outcome: WindowLayoutRunner.Outcome, for layout: WindowLayout) async {
        if outcome.isBlockedOnPermission {
            let openSettings = await core.reportFailure(
                title: "Tinycast Needs Accessibility Access",
                message: "Arranging windows uses the same permission as pasting.",
                symbol: layout.symbol, recovery: "Open Settings")
            if openSettings { Permissions.openAccessibilitySettings() }
            return
        }
        // Placing windows is its own feedback, so a clean run says nothing at all.
        guard let detail = detail(for: outcome) else { return }
        guard outcome.didAnything else {
            await core.showNotice(
                title: "Couldn't Run “\(layout.name)”", message: detail, symbol: layout.symbol,
                tone: .danger)
            return
        }
        core.showMessage("\(layout.name) — \(detail)", tone: .neutral)
    }

    /// What went wrong, or nil when everything the layout asked for happened.
    private func detail(for outcome: WindowLayoutRunner.Outcome) -> String? {
        var parts: [String] = []
        if let skipped = WindowLayoutPlan(placements: [], skipped: outcome.skipped).skippedSummary {
            parts.append(skipped)
        }
        if !outcome.neverAppeared.isEmpty {
            let count = outcome.neverAppeared.count
            parts.append(count == 1 ? "1 app didn't open" : "\(count) apps didn't open")
        }
        let failed = outcome.openFailures.count
        if failed > 0 {
            parts.append(failed == 1 ? "1 app couldn't open" : "\(failed) apps couldn't open")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func report(failure: WindowLayoutValidationError) async {
        await core.showNotice(
            title: "Couldn't Save the Layout",
            message: failure.errorDescription ?? "The layout could not be saved.",
            symbol: WindowLayout.sfSymbol, tone: .danger)
    }

    private func removeWindowLayoutReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.windowLayout(id: id)
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

    /// "Captured Layout", then " 2", so the editor opens on a name that will validate.
    private static func uniqueCaptureName(among existing: [WindowLayout]) -> String {
        let taken = Set(existing.map { $0.name.lowercased() })
        let base = "Captured Layout"
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }
}
