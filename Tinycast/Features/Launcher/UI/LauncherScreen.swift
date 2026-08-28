import SwiftUI

/// The root search: favorites first, then one section per entry kind, led by the calculator card.
struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    /// Sampled by `openActions`, so the Restart and Quit rows can't appear or vanish while the
    /// menu is up.
    let running: Bool
    /// The join card's meeting, resolved by the coordinator; nil unless one is due.
    let meeting: MeetingEvent?
    let now: Date
    let openActions: () -> Void
    /// Called when an action reorders the list, so the highlight scrolls back into view.
    let scrollToFollow: () -> Void

    /// The one ordered result list; an empty query pins favorites above the ranked matches.
    private let results: [AppEntry]
    private let calc: CalcResult?
    /// Sections stand in for the ranked Results list, which a typed query collapses to.
    private let showSections: Bool
    /// Only the empty query pins favorites — a category shows its sections without one of its own.
    private let pinsFavorites: Bool
    /// How many of `results` are the pinned favorites; zero unless the Favorites section is showing.
    private let favoriteCount: Int
    /// Resolved in `init`: the palette indexes this several times per event, so it can't recompute.
    let rows: [Row]

    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore,
        currencyRates: CurrencyRateStore, core: AppCore, vm: PaletteState, running: Bool,
        meeting: MeetingEvent?, now: Date,
        openActions: @escaping () -> Void, scrollToFollow: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.now = now
        self.openActions = openActions
        self.scrollToFollow = scrollToFollow

        let results = appIndex.orderedResults(
            query: vm.query, visibility: visibility, favorites: favorites)
        let calc = CalcMemo.evaluate(vm.query, rates: currencyRates.rates)
        let entries = results.map(Row.entry)
        let pinsFavorites = vm.query.trimmingCharacters(in: .whitespaces).isEmpty
        // The calculator only answers a typed query and the card only an empty one, so at most one
        // of them ever leads, and the flat index keeps a single-row offset.
        let meeting = pinsFavorites ? meeting : nil
        self.meeting = meeting
        self.results = results
        self.calc = calc
        self.showSections = pinsFavorites || AppEntry.Kind.named(by: vm.query) != nil
        self.pinsFavorites = pinsFavorites
        self.favoriteCount = pinsFavorites ? results.prefix(while: favorites.isFavorite).count : 0
        if let calc {
            self.rows = [.calc(calc)] + entries
        } else if let meeting {
            self.rows = [.meeting(meeting)] + entries
        } else {
            self.rows = entries
        }
    }

    /// The card is a row like any other, so the flat selection indexes `rows` with no offset.
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case meeting(MeetingEvent)
        case entry(AppEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .meeting: return "meeting-card"
            case .entry(let app): return app.id
            }
        }
    }

    /// The pill carries no selection, so the screen applies the clamp the palette applies.
    private var clampedSelection: Int {
        let count = rows.count
        return count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    var primaryActionTitle: String {
        switch row(at: clampedSelection) {
        case .calc: return "Copy Answer"
        case .meeting(let meeting):
            return meeting.link == nil ? "Open in Calendar" : "Join Meeting"
        case .entry(let app): return app.kind.descriptor.openVerb
        case nil: return "Open Application"
        }
    }

    private func row(at selection: Int) -> Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// A launcher row may want controls beside the search field; what they are is the owning feature's
    /// business, so this only forwards the selection and hands back whatever it builds.
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    {
        guard let entry = entry(at: selection) else { return nil }
        return ExtensionArgumentsAccessory.make(
            entry: entry, coordinator: core.extensionCoordinator,
            values: { name in headerFieldBinding(entry: entry, name: name) },
            focus: focus, onSubmit: { activate(at: selection) })
    }

    private func headerFieldBinding(entry: AppEntry, name: String) -> Binding<String> {
        let key = PaletteState.argumentKey(entry.id, name)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }

    /// The typed values for one row, stripped of blanks — what gets handed to the command.
    private func argumentValues(for entry: AppEntry) -> [String: String] {
        var values: [String: String] = [:]
        for argument in core.extensionCoordinator.commandArguments(for: entry) ?? [] {
            let typed = vm.commandArguments[PaletteState.argumentKey(entry.id, argument.name)] ?? ""
            if !typed.isEmpty { values[argument.name] = typed }
        }
        return values
    }

    private func entry(at selection: Int) -> AppEntry? {
        guard case .entry(let app) = row(at: selection) else { return nil }
        return app
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc, .meeting: return true
        case .entry, nil: return false
        }
    }

    /// Whichever card leads, in the terms the list draws it in.
    private var leadCard: LauncherList.LeadCard? {
        if let calc { return .calc(calc) }
        return meeting.map { .meeting($0, now: now) }
    }

    /// An error card is selectable but has no action: it must drive neither the pill nor ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .meeting(let meeting):
            return MeetingActionsMenu.content(meeting: meeting, core: core)
        case .entry(let app):
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, core: core, running: running,
                favorites: favoriteActions(for: app, at: selection),
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    // Reset can move the item; keep the highlight on the item whose action ran.
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                })
        case nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        // Error cards no-op — copyCalculatorResult only acts on value payloads.
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .meeting(let meeting): core.calendarCoordinator.activateMeeting(id: meeting.id)
        case .entry(let app):
            core.launcherCoordinator.launch(
                app, searchQuery: vm.query, arguments: argumentValues(for: app))
        case nil: break
        }
    }

    /// ⌘↵ — only an entry backed by a file on disk has somewhere to be revealed.
    func secondary(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    /// The one guard both power chords share, so neither can drift from the rows it mirrors: they
    /// are offered only for an `.application` entry `RunningAppsMonitor` reports running.
    private func runningApplication(at selection: Int) -> AppEntry? {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return nil }
        return app
    }

    /// ⌃⇧Q — the screen owns the chord, but only a running application has anything to quit.
    func quit(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.quit(app)
        return true
    }

    /// ⌘R — mirrors the Restart Application row.
    func restart(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.restart(app)
        return true
    }

    /// ⇧⌘F — mirrors the Add/Remove Favorites row. The highlight stays in the Favorites section
    /// rather than chasing the entry: the top of it on add, the neighbour above the one that left.
    func toggleFavorite(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        let removed = favoriteIndex(of: app)
        favorites.toggle(app)
        // A typed query never pins favorites, so nothing moved and the highlight belongs where it is.
        guard pinsFavorites else { return true }
        selectFavorite(at: removed.map { $0 - 1 } ?? 0)
        return true
    }

    /// ⌘1–⌘9/⌘0 — launch a favorite by position, in either palette size.
    func launchFavorite(at index: Int) -> Bool {
        guard let app = pinnedFavorites.dropFirst(index).first else { return false }
        core.launcherCoordinator.launch(app)
        return true
    }

    /// The favorites the chords address and the compact strip draws from. Empty while a query is
    /// typed, which is also the only state in which the section isn't on screen.
    private var pinnedFavorites: ArraySlice<AppEntry> { results.prefix(favoriteCount) }

    /// ⌥⌘↑/↓ — swap with the neighbouring favorite; the ends of the section have nowhere to go.
    func moveFavorite(_ delta: Int, at selection: Int) -> Bool {
        guard let app = entry(at: selection), let index = favoriteIndex(of: app) else { return false }
        let target = index + delta
        guard target >= 0, target < favoriteCount else { return false }
        favorites.exchange(favorites.key(for: app), with: favorites.key(for: results[target]))
        follow(app)
        return true
    }

    /// The favorites rows the Actions menu offers for an entry; the ends drop the move they can't
    /// run, and both rows call straight back here so a row can't drift from its chord.
    private func favoriteActions(
        for app: AppEntry, at selection: Int
    )
        -> AppActionsMenu.FavoriteActions
    {
        let index = favoriteIndex(of: app)
        return AppActionsMenu.FavoriteActions(
            isFavorite: favorites.isFavorite(app),
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < favoriteCount - 1 } ?? false,
            toggle: { _ = toggleFavorite(at: selection) },
            move: { _ = moveFavorite($0, at: selection) })
    }

    /// Position inside the Favorites section, or nil when the entry isn't reorderable there.
    private func favoriteIndex(of app: AppEntry) -> Int? {
        guard let index = results.firstIndex(of: app), index < favoriteCount else { return nil }
        return index
    }

    /// The list reorders under an action; keep the highlight and the scroll on the row that moved.
    private func follow(_ app: AppEntry) {
        guard let index = reorderedResults().firstIndex(of: app) else { return }
        select(row: index)
    }

    /// Highlight a row of the Favorites section, clamped into what the section now holds.
    private func selectFavorite(at index: Int) {
        let count = reorderedResults().prefix(while: favorites.isFavorite).count
        select(row: min(max(index, 0), max(count - 1, 0)))
    }

    /// Re-read the order the change just invalidated; this warms the key the next render reads.
    private func reorderedResults() -> [AppEntry] {
        appIndex.orderedResults(query: vm.query, visibility: visibility, favorites: favorites)
    }

    private func select(row index: Int) {
        vm.selection = index + (calc == nil && meeting == nil ? 0 : 1)
        scrollToFollow()
    }

    /// The sample `openActions` takes; only an app row can ever carry the running-only actions.
    func isRunning(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        return core.runningApps.isRunning(app)
    }

    /// The compact bar's icons: the first five favorites. The "…" that follows them is not one.
    var compactFavorites: [AppEntry] { Array(pinnedFavorites.prefix(5)) }

    /// Whether the compact bar's "…" has anything to reveal.
    var hasUnshownFavorites: Bool { favoriteCount > compactFavorites.count }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        LauncherList(
            results: results,
            selectedID: entry(at: selection)?.id,
            favoriteCount: favoriteCount,
            showSections: showSections,
            scroll: scroll,
            card: leadCard,
            cardSelected: isCardSelected(selection),
            onActivateCard: {
                vm.selection = 0
                activate(at: 0)
            },
            onCardActions: {
                guard hasPrimaryAction(at: 0) else { return }
                vm.selection = 0
                openActions()
            },
            onActivate: { core.launcherCoordinator.launch($0, searchQuery: vm.query) },
            onActions: { app in
                if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                openActions()
            }
        )
    }
}
