import SwiftUI

/// The root search: favorites, suggestions, then one section per entry kind, led by any card.
struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    /// Sampled by `openActions`, so Restart and Quit can't move while the menu is up.
    let running: Bool
    /// The join card's meeting, resolved by the coordinator; nil unless one is due.
    let meeting: MeetingEvent?
    let now: Date
    let openActions: () -> Void
    /// Opens the palette's own menu for an `options=` field, keyed by argument name.
    let openArgumentOptions: (String) -> Void
    /// Called when an action reorders the list, so the highlight scrolls back into view.
    let scrollToFollow: () -> Void

    /// The one ordered result list; an empty query pins favorites above the ranked matches.
    private let results: [AppEntry]
    private let calc: CalcResult?
    /// The colour the query itself spells, if it spells one; nil for every other query.
    private let color: ColorValue?
    /// Sections stand in for the ranked Results list, which a typed query collapses to.
    private let showSections: Bool
    /// Only the empty query pins favorites — a category shows its sections without one of its own.
    private let pinsFavorites: Bool
    /// How many of `results` are pinned favorites; zero unless the section shows.
    private let favoriteCount: Int
    /// How many follow the favorites as Suggestions; zero unless the field is empty.
    private let suggestionCount: Int
    /// The `Use "…" with` section, below every result; empty unless something is typed.
    private let fallbacks: [(fallback: Fallback, entry: AppEntry)]
    /// Populated only when an unmatched query receives a confident TypeSafe response.
    private let choices: [AppEntry]
    private let hasLocalAnswer: Bool
    /// Resolved in `init`: the palette indexes this several times per event, so it can't recompute.
    let rows: [Row]

    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore,
        currencyRates: CurrencyRateStore, core: AppCore, vm: PaletteState, running: Bool,
        meeting: MeetingEvent?, now: Date,
        openActions: @escaping () -> Void, openArgumentOptions: @escaping (String) -> Void,
        scrollToFollow: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.now = now
        self.openActions = openActions
        self.openArgumentOptions = openArgumentOptions
        self.scrollToFollow = scrollToFollow

        // Listed even when hidden from search: the shortcut that opened it still has to be answered.
        let pinned = vm.argumentEntryID.flatMap(core.customCommands.command(entryID:))
            .map(AppEntry.init).flatMap { $0.name == vm.query ? $0 : nil }
        let ordered =
            pinned.map { AppIndex.Results(entries: [$0]) }
            ?? appIndex.orderedResults(
                query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
        var results = ordered.entries
        // A typed web address leads: nothing the index holds answers it better.
        if pinned == nil, let browser = CommandCatalog.openInBrowser(for: vm.query),
            visibility.isVisible(browser)
        {
            results.insert(browser, at: 0)
        }
        // No card over a pinned row: its fields hang off the selection, which must start on it.
        let calc =
            pinned == nil
            ? CalcMemo.evaluate(vm.query, rates: currencyRates.rates, format: core.calcNumberFormat) : nil
        // After the calculator: `#FF5733` is never arithmetic, so the two can't both answer.
        let color = calc == nil && pinned == nil ? ColorValue.parse(vm.query) : nil
        let fallbacks = core.fallbackCoordinator.entries(for: vm.query)
        let pinsFavorites = vm.query.trimmingCharacters(in: .whitespaces).isEmpty
        // At most one of them leads, so the flat index keeps a single-row offset.
        let meeting = pinsFavorites ? meeting : nil
        let hasLocalAnswer = !results.isEmpty || calc != nil || color != nil || meeting != nil
        let choices = core.naturalCommandCoordinator.choices(
            for: vm.query, hasLocalAnswer: hasLocalAnswer)
        let entries = results.map(Row.entry) + fallbacks.map { Row.fallback($0.fallback, $0.entry) }
        let choiceRows = choices.map(Row.choice)
        self.meeting = meeting
        self.results = results
        self.calc = calc
        self.fallbacks = fallbacks
        self.choices = choices
        self.hasLocalAnswer = hasLocalAnswer
        self.color = color
        self.showSections = pinsFavorites || AppEntry.Kind.named(by: vm.query) != nil
        self.pinsFavorites = pinsFavorites
        self.favoriteCount = pinsFavorites ? ordered.favoriteCount : 0
        self.suggestionCount = pinsFavorites ? ordered.suggestionCount : 0
        if let calc {
            self.rows = choiceRows + [.calc(calc)] + entries
        } else if let color {
            self.rows = choiceRows + [.color(color)] + entries
        } else if let meeting {
            self.rows = choiceRows + [.meeting(meeting)] + entries
        } else {
            self.rows = choiceRows + entries
        }
    }

    /// The card is a row like any other, so the flat selection indexes `rows` with no offset.
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case meeting(MeetingEvent)
        case color(ColorValue)
        case choice(AppEntry)
        case entry(AppEntry)
        /// Prefixed, because the same command can also be a ranked hit above its own fallback row.
        case fallback(Fallback, AppEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .meeting: return "meeting-card"
            case .color: return "color-card"
            case .choice(let app): return "natural-choice-" + app.id
            case .entry(let app): return app.id
            case .fallback(let fallback, _): return "fallback-" + fallback.id
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
        case .color: return "Copy Color"
        case .meeting(let meeting):
            return meeting.link == nil ? "Open in Calendar" : "Join Meeting"
        case .choice: return "Review Command"
        case .entry(let app): return app.kind.descriptor.openVerb
        case .fallback(let fallback, _): return fallback.openVerb
        case nil: return "Open Application"
        }
    }

    private func row(at selection: Int) -> Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// What the controls are is the owning feature's business; this only forwards.
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    {
        guard let entry = entry(at: selection) else { return nil }
        // A quicklink asks for its values in root search too, so the fallback never leaves it.
        if entry.kind == .quicklink {
            return QuicklinkArgumentsAccessory.make(
                quicklink: quicklink(for: entry), core: core, vm: vm, focus: focus,
                placement: .afterQuery, onOpenOptions: openArgumentOptions,
                onSubmit: { activate(at: selection) })
        }
        if entry.kind == .customCommand {
            return CustomCommandArgumentsAccessory.make(
                command: core.customCommands.command(entryID: entry.id), vm: vm,
                metrics: core.settings.interfaceSize.metrics, focus: focus,
                onSubmit: { activate(at: selection) })
        }
        return ExtensionArgumentsAccessory.make(
            entry: entry, coordinator: core.extensionCoordinator,
            values: { name in headerFieldBinding(entry: entry, name: name) },
            focus: focus, metrics: core.settings.interfaceSize.metrics,
            onSubmit: { activate(at: selection) })
    }

    private func headerFieldBinding(entry: AppEntry, name: String) -> Binding<String> {
        let key = PaletteState.argumentKey(entry.id, name)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }

    /// The typed values for one row, stripped of blanks — what gets handed to the command.
    private func argumentValues(for entry: AppEntry) -> [String: String] {
        if entry.kind == .quicklink {
            guard let quicklink = quicklink(for: entry) else { return [:] }
            return QuicklinkArgumentsAccessory.values(for: quicklink, core: core, vm: vm)
        }
        if entry.kind == .customCommand {
            guard let command = core.customCommands.command(entryID: entry.id) else { return [:] }
            return CustomCommandArgumentsAccessory.values(for: command, vm: vm)
        }
        var values: [String: String] = [:]
        for argument in core.extensionCoordinator.commandArguments(for: entry) ?? [] {
            let typed = vm.commandArguments[PaletteState.argumentKey(entry.id, argument.name)] ?? ""
            if !typed.isEmpty { values[argument.name] = typed }
        }
        return values
    }

    private func quicklink(for entry: AppEntry) -> Quicklink? {
        Quicklink.id(fromEntryID: entry.id).flatMap(core.quicklinks.quicklink)
    }

    private func entry(at selection: Int) -> AppEntry? {
        guard case .entry(let app) = row(at: selection) else { return nil }
        return app
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc, .meeting, .color: return true
        case .choice, .entry, .fallback, nil: return false
        }
    }

    /// Whichever card leads, in the terms the list draws it in.
    private var leadCard: LauncherList.LeadCard? {
        if let calc { return .calc(calc) }
        if let color { return .color(color) }
        return meeting.map { .meeting($0, now: now) }
    }

    /// An error card is selectable but has no action: it must drive neither the pill nor ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    func hasActions(at selection: Int) -> Bool {
        guard case .choice = row(at: selection) else { return true }
        return false
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .color(let color):
            return ColorActionsMenu.content(color: color, core: core)
        case .meeting(let meeting):
            return MeetingActionsMenu.content(meeting: meeting, core: core)
        case .choice: return nil
        case .entry(let app):
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, core: core, running: running,
                favorites: favoriteActions(for: app, at: selection),
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    // Reset can move the item; keep the highlight on the item whose action ran.
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                },
                onHideFromSearch: { _ = hideFromSearch(at: selection) })
        case .fallback(let fallback, let app):
            return FallbackActionsMenu.content(
                fallback: fallback, entry: app, query: vm.query, core: core)
        case nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        // Error cards no-op — copyCalculatorResult only acts on value payloads.
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .color(let color):
            core.clipboardCoordinator.copyColor(color, as: ColorFormat.primary(for: color))
        case .meeting(let meeting): core.calendarCoordinator.activateMeeting(id: meeting.id)
        case .choice(let app): core.naturalCommandCoordinator.select(app.id)
        case .entry(let app):
            core.launcherCoordinator.launch(
                app, searchQuery: vm.query, arguments: argumentValues(for: app))
        case .fallback(let fallback, _):
            core.fallbackCoordinator.run(fallback, query: vm.query)
        case nil: break
        }
    }

    /// ⌘↵ — only an entry backed by a file on disk has somewhere to be revealed.
    func secondary(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    /// Offered only for an `.application` entry `RunningAppsMonitor` reports running.
    private func runningApplication(at selection: Int) -> AppEntry? {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return nil }
        return app
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .toggleFavorite: return toggleFavorite(at: selection)
        case .hideFromSearch: return hideFromSearch(at: selection)
        case .quit: return quit(at: selection)
        case .restart: return restart(at: selection)
        case .favoriteSlot(let index): return launchFavorite(at: index)
        default: return false
        }
    }

    /// ⌃⇧Q — the screen owns the chord, but only a running application has anything to quit.
    private func quit(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.quit(app)
        return true
    }

    /// ⌘R — mirrors the Restart Application row.
    private func restart(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.restart(app)
        return true
    }

    /// The highlight stays in Favorites: the top on add, the neighbour above on remove.
    private func toggleFavorite(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app) else { return false }
        let removed = favoriteIndex(of: app)
        favorites.toggle(app)
        // A typed query pins no favorites, so nothing moved and the highlight stays.
        guard pinsFavorites else { return true }
        selectFavorite(at: removed.map { $0 - 1 } ?? 0)
        return true
    }

    /// ⌘1–⌘9/⌘0 — launch a favorite by position, in either palette size.
    private func launchFavorite(at index: Int) -> Bool {
        guard let app = pinnedFavorites.dropFirst(index).first else { return false }
        core.launcherCoordinator.launch(app)
        return true
    }

    /// Empty while a query is typed, the only state in which the section is off screen.
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

    /// The ends drop the move they can't run; both rows call back here, never drifting.
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

    /// ⇧⌘H — the row leaves the list for good, so the highlight takes the place it vacated.
    private func hideFromSearch(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.canHideFromSearch,
            !CommandCatalog.isQueryDriven(app), let index = results.firstIndex(of: app)
        else { return false }
        visibility.setItemVisible(false, for: app)
        select(row: min(index, max(reorderedResults().entries.count - 1, 0)))
        return true
    }

    /// The list reorders under an action; keep the highlight and the scroll on the row that moved.
    private func follow(_ app: AppEntry) {
        guard let index = reorderedResults().entries.firstIndex(of: app) else { return }
        select(row: index)
    }

    /// Highlight a row of the Favorites section, clamped into what the section now holds.
    private func selectFavorite(at index: Int) {
        let count = reorderedResults().favoriteCount
        select(row: min(max(index, 0), max(count - 1, 0)))
    }

    /// Re-read the order the change just invalidated; this warms the key the next render reads.
    private func reorderedResults() -> AppIndex.Results {
        appIndex.orderedResults(
            query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
    }

    private func select(row index: Int) {
        vm.selection = index + (leadCard == nil ? 0 : 1)
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
        AnyView(
            content(selection: selection, scroll: scroll)
                .task(id: fallbackTrigger) {
                    core.naturalCommandCoordinator.considerFallback(
                        query: vm.query, hasLocalAnswer: hasLocalAnswer)
                })
    }

    private struct FallbackTrigger: Equatable {
        let query: String
        let hasLocalAnswer: Bool
        let enabled: Bool
        let hasKey: Bool
    }

    private var fallbackTrigger: FallbackTrigger {
        FallbackTrigger(
            query: vm.query, hasLocalAnswer: hasLocalAnswer,
            enabled: core.settings.naturalCommandsEnabled,
            hasKey: core.naturalCommandSettings.hasAPIKey)
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        LauncherList(
            results: results,
            selectedRowID: row(at: selection)?.id,
            favoriteCount: favoriteCount,
            suggestionCount: suggestionCount,
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
            onActivate: {
                core.launcherCoordinator.launch(
                    $0, searchQuery: vm.query, arguments: argumentValues(for: $0))
            },
            onActions: { app in
                if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                openActions()
            },
            onDropped: { core.paletteCoordinator.dragLanded() },
            choices: choiceSection,
            fallbacks: fallbackSection
        )
    }

    private var choiceSection: LauncherList.ChoiceSection? {
        guard !choices.isEmpty else { return nil }
        return LauncherList.ChoiceSection(
            entries: choices,
            onActivate: { activate(at: $0) })
    }

    /// Nil when nothing is typed, which is the one state the section has no input for.
    private var fallbackSection: LauncherList.FallbackSection? {
        guard !fallbacks.isEmpty else { return nil }
        return LauncherList.FallbackSection(
            title: Fallback.sectionTitle(query: vm.query),
            entries: fallbacks.map(\.entry),
            onActivate: { activate(at: fallbackRow(at: $0)) },
            onActions: {
                vm.selection = fallbackRow(at: $0)
                openActions()
            },
            onConfigure: core.fallbackCoordinator.showSettings)
    }

    /// Fallbacks are the tail of `rows`, so a click maps to its flat index without a search.
    private func fallbackRow(at index: Int) -> Int { rows.count - fallbacks.count + index }
}
