import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var visibility: VisibilityStore
    @EnvironmentObject private var calcHistory: CalculatorHistoryStore
    /// Observed so the inline card re-evaluates the moment a fresh FX snapshot lands, or the user
    /// turns currency conversion on or off.
    @EnvironmentObject private var currencyRates: CurrencyRateStore
    @EnvironmentObject private var emojiIndex: EmojiIndex
    @EnvironmentObject private var frequentEmoji: FrequentEmojiStore
    /// Observed so a skin tone changed in Settings re-renders the grid glyphs immediately.
    @ObservedObject private var settings = AppCore.shared.settings
    @FocusState private var searchFocused: Bool
    @State private var showActions = false
    @State private var showAppMenu = false
    /// The selection's running state, sampled once by `openActions` — an app launching or quitting elsewhere must not add or drop the Quit row while the menu is up. `RunningAppsMonitor` is deliberately not observed here: only `LauncherList` needs live running state, and observing it would re-render the whole palette on every workspace launch/terminate.
    @State private var selectionIsRunning = false
    /// Highlighted row of whichever popover menu is open; reset to the first row on open, moved by ↑/↓ and hover, activated by ↵/click.
    @State private var menuSelection = 0
    /// Bumped only when the selection should pull the scroll view with it (keyboard nav, list resets); mouse selection targets a visible row, so it leaves this and the list put.
    @State private var scrollToken = UUID()
    /// The emoji grid's scroll request — the lazy grid needs distinct reset/follow scroll ops, unlike the 1-D lists that recenter fine on `scrollToken`.
    @State private var emojiScroll = EmojiScrollIntent(kind: .top)

    private var isQueryEmpty: Bool { vm.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Slim compact bar vs. full window — the single source of truth lives on `AppCore` so the window controller and this view can never disagree.
    private var isCollapsed: Bool { core.paletteIsCollapsed }

    /// Favorite slots shown in the compact bar: up to 5 launchable apps, or the first 4 plus an overflow "…" that expands the window. Evaluated only in the compact render and on the rare ⌘N keypress.
    private var compactFavoriteSlots: [CompactFavoriteSlot] {
        let favs = favorites.ordered(appIndex.matches("").filter(visibility.isVisible)).favorites
        if favs.count <= 5 { return favs.map(CompactFavoriteSlot.app) }
        return favs.prefix(4).map(CompactFavoriteSlot.app) + [.more]
    }

    /// Ordered launcher results (the single source of truth for list, selection and activation): empty query pins favorites to the top, otherwise plain ranked matches.
    private var appResults: [AppEntry] {
        // Visibility filtering stays downstream of `matches` so its one-deep memo cache is never keyed on hidden state; hidden favorites drop out here too.
        let base = appIndex.matches(vm.query).filter(visibility.isVisible)
        guard isQueryEmpty, !favorites.keys.isEmpty else { return base }
        let split = favorites.ordered(base)
        return split.favorites + split.rest
    }
    private var clipResults: [ClipboardItem] { store.search(vm.query) }
    private var histResults: [CalcHistoryEntry] { calcHistory.search(vm.query) }
    private var emojiSections: [EmojiGridSection] {
        EmojiGrid.sections(query: vm.query, index: emojiIndex, frequent: frequentEmoji)
    }
    /// Flat grid order across sections — what `vm.selection` indexes in emoji mode.
    private var emojiResults: [EmojiEntry] { emojiSections.flatMap(\.entries) }

    /// Inline calculator answer for the current query, live in both the launcher and Calculator History search; when present it occupies flat selection index 0 so rows shift by `calcCount`.
    private var calcResult: CalcResult? {
        vm.mode == .launcher || vm.mode == .calculatorHistory
            ? CalcMemo.evaluate(vm.query, currency: currencyRates.source) : nil
    }
    private var calcCount: Int { calcResult == nil ? 0 : 1 }

    private var resultCount: Int {
        switch vm.mode {
        case .launcher: return appResults.count + calcCount
        case .clipboard: return clipResults.count
        case .calculatorHistory: return histResults.count + calcCount
        case .emoji: return emojiResults.count
        }
    }
    /// Selection clamped into the current results — the single source of truth for highlight, preview and activation so the list and preview can never disagree.
    private var selection: Int { resultCount == 0 ? 0 : min(max(vm.selection, 0), resultCount - 1) }

    private var menuOpen: Bool { showActions || showAppMenu }

    // MARK: - Popover menu content
    //
    // These resolve the current selection for whichever menu is open. They are evaluated only inside the
    // menu overlays (menu visible) or on a keypress (rare), so re-running the unmemoized `appResults`
    // filter here is fine — the same idiom the other rare event handlers use.

    /// The inline calc card sits at flat index 0 when present; only value payloads have a Copy action.
    private var calcActionableResult: CalcResult? {
        guard calcCount > 0, selection == 0, let calc = calcResult, calc.isActionable else {
            return nil
        }
        return calc
    }
    private var selectedAppEntry: AppEntry? {
        let index = selection - calcCount
        return appResults.indices.contains(index) ? appResults[index] : nil
    }
    private var selectedClipItem: ClipboardItem? {
        clipResults.indices.contains(selection) ? clipResults[selection] : nil
    }
    private var selectedHistEntry: CalcHistoryEntry? {
        let index = selection - calcCount
        return histResults.indices.contains(index) ? histResults[index] : nil
    }
    private var selectedEmojiEntry: EmojiEntry? {
        emojiResults.indices.contains(selection) ? emojiResults[selection] : nil
    }

    /// The bottom-right Actions menu content for the current mode's selection, or nil when the selection has no actions.
    private var actionsContent: PopoverMenuContent? {
        switch vm.mode {
        case .launcher:
            if let calc = calcActionableResult {
                return CalcActionsMenu.content(result: calc, core: core)
            }
            if let app = selectedAppEntry {
                return AppActionsMenu.content(
                    app: app, searchQuery: vm.query, core: core, favorites: favorites,
                    running: selectionIsRunning,
                    onResetRanking: {
                        core.resetRanking(for: app)
                        // Reset can move the item; keep the highlight on the item whose action ran.
                        if let index = appResults.firstIndex(of: app) {
                            vm.selection = index + calcCount
                        }
                    })
            }
            return nil
        case .clipboard:
            if let clip = selectedClipItem {
                return ClipboardActionsMenu.content(
                    item: clip, core: core, store: store, target: vm.pasteTarget)
            }
            return nil
        case .calculatorHistory:
            if let calc = calcActionableResult {
                return CalcActionsMenu.content(result: calc, core: core)
            }
            if let hist = selectedHistEntry {
                return CalcHistoryActionsMenu.content(
                    entry: hist, core: core, calcHistory: calcHistory)
            }
            return nil
        case .emoji:
            if let emoji = selectedEmojiEntry {
                return EmojiActionsMenu.content(
                    entry: emoji, core: core, target: vm.pasteTarget)
            }
            return nil
        }
    }

    /// The bottom-left app menu content (About / Settings).
    private var appMenuContent: PopoverMenuContent {
        PopoverMenuContent(items: [
            PopoverMenuItem(title: "About Tinycast", systemImage: "info.circle") {
                core.showAbout()
            },
            PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                core.showSettings()
            },
        ])
    }

    /// Whichever menu is open (Actions takes precedence; the two are kept mutually exclusive) — the source for keyboard navigation and activation.
    private var menuContent: PopoverMenuContent? {
        if showActions { return actionsContent }
        if showAppMenu { return appMenuContent }
        return nil
    }

    var body: some View {
        // Filter once per render for the active mode only, so the matcher/search doesn't run several times per render (rare event handlers use the computed properties above).
        let apps = vm.mode == .launcher ? appResults : []
        let clips = vm.mode == .clipboard ? clipResults : []
        let hist = vm.mode == .calculatorHistory ? histResults : []
        let emojiSections = vm.mode == .emoji ? emojiSections : []
        let emojis = emojiSections.flatMap(\.entries)
        // Newest stored clip + the reorder token: the pair changes only when the store mutates, never when a query filters the list.
        let clipFollow = ClipFollowKey(id: store.items.first?.id, token: vm.followToken)
        // Every count/selection below derives from this one calc/offset pair — the flat selection index must always match the visible row order, calc card included.
        let calc = calcResult
        let offset = calc == nil ? 0 : 1
        // Only the active mode is non-empty.
        let count = apps.count + offset + clips.count + hist.count + emojis.count
        let sel = count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
        let calcSelected = calc != nil && sel == 0
        // An error card is selectable but has no action: it must not drive the Copy Answer pill, ⌘K menu, or Enter.
        let calcActionable = calcSelected && calc?.isActionable == true
        let showSections = vm.mode == .launcher && isQueryEmpty
        let favoriteCount =
            showSections ? apps.prefix(while: { favorites.isFavorite($0) }).count : 0
        let selectedApp = apps.indices.contains(sel - offset) ? apps[sel - offset] : nil
        // Derive the footer label from the already-resolved selection so `bottomBar` doesn't re-run `appResults` (its filter/sort aren't memoized). The primary/Actions group is hidden when there's nothing to act on: no results in any mode, or an error calc card (selectable but action-less).
        let pillLabel = actionPillLabel(selectedApp: selectedApp, calcActionable: calcActionable)
        let showActionGroup = count > 0 && !(calcSelected && !calcActionable)

        // The `header` (and its single search field) is always attached in the same position via safeAreaInset so its focus survives the compact↔expanded swap — only the results below it toggle. Collapsed shows the bar alone; expanded floats header + action bar over the list with edge-dissolve (see docs/ui.md).
        return Group {
            if isCollapsed {
                Color.clear
            } else {
                content(
                    apps: apps, clips: clips, hist: hist, emojiSections: emojiSections, calc: calc,
                    selection: sel, favoriteCount: favoriteCount, showSections: showSections
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isCollapsed {
                bottomBar(pillLabel: pillLabel, showActionGroup: showActionGroup)
            }
        }
        // Menus are in-window overlays anchored to a bottom corner, so they stay clipped inside the panel — never a system popover spilling outside the window.
        .overlay {
            if showAppMenu || showActions {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeMenus)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showAppMenu {
                let content = appMenuContent
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomLeading))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showActions, let content = actionsContent {
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        // The window's own frame (driven by `PaletteWindowController`) is the size source of truth; filling it keeps the glass background and corner clip matched to the current compact/expanded window height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // Every show bumps focusToken — refocus search and drop any menu left open from last time (e.g. dismissed by clicking away with a context menu up).
        .onChange(of: vm.focusToken) {
            searchFocused = true
            showActions = false
            showAppMenu = false
        }
        .onChange(of: vm.query) {
            vm.selection = 0
            scrollToken = UUID()
            emojiScroll = EmojiScrollIntent(kind: .top)
        }
        .onChange(of: vm.mode) {
            vm.selection = 0
            showActions = false
            scrollToken = UUID()
            emojiScroll = EmojiScrollIntent(kind: .top)
        }
        // Pop-to-root: `prepare` clears query/selection, but if both were already at their defaults the handlers above never fire — this token guarantees the scroll itself snaps back to the top.
        .onChange(of: vm.resetToken) {
            scrollToken = UUID()
            emojiScroll = EmojiScrollIntent(kind: .top)
        }
        // Opening either menu highlights its first row and closes the other, so exactly one menu is ever open and always has a highlight.
        .onChange(of: showActions) {
            if showActions {
                showAppMenu = false
                menuSelection = 0
            }
            vm.menuOpen = menuOpen
        }
        .onChange(of: showAppMenu) {
            if showAppMenu {
                showActions = false
                menuSelection = 0
            }
            vm.menuOpen = menuOpen
        }
        // Follow a row the store moved: a fresh capture (or promote-on-paste) lands at the head of its section, and pinning lifts a row into the Pinned section. With a query typed the highlight stays put; `AppCore` has already placed it for pin/paste.
        .onChange(of: clipFollow) { old, new in
            // A nil `old.id` is the first load landing, not a row that moved.
            guard vm.mode == .clipboard, old.id != nil else { return }
            if isQueryEmpty, old.id != new.id, let id = new.id,
                let index = clips.firstIndex(where: { $0.id == id })
            {
                vm.selection = index
            }
            scrollToken = UUID()
        }
        .onAppear { searchFocused = true }
        // Typing/clearing/overflow/settings all flip `paletteIsCollapsed`; resize the window to match.
        .onChange(of: core.paletteIsCollapsed) { core.syncPaletteSize() }
        // ⌘1–⌘5 launch the compact bar's favorite slots (or expand, for the "…" overflow slot).
        .onKeyPress(keys: ["1", "2", "3", "4", "5"], phases: .down) { press in
            guard isCollapsed, settings.showFavoritesInCompactMode,
                press.modifiers.contains(.command),
                let digit = press.key.character.wholeNumberValue
            else { return .ignored }
            let slots = compactFavoriteSlots
            let index = digit - 1
            guard slots.indices.contains(index) else { return .ignored }
            switch slots[index] {
            case .app(let app): core.launch(app)
            case .more: core.expandFromCompact()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if isCollapsed {
                // The compact bar has no visible selection; Down reveals the list at its first row
                // while the shared search field stays mounted and focused.
                vm.selection = 0
                core.expandFromCompact()
                return .handled
            }
            if menuOpen {
                moveMenu(1)
                return .handled
            }
            if vm.mode == .emoji { moveEmojiRow(1) } else { move(1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isCollapsed { return .ignored }
            if menuOpen {
                moveMenu(-1)
                return .handled
            }
            if vm.mode == .emoji { moveEmojiRow(-1) } else { move(-1) }
            return .handled
        }
        // Horizontal arrows step the emoji grid; everywhere else they stay with the field editor's caret. An open menu swallows them so the list behind never moves.
        .onKeyPress(.leftArrow) {
            if menuOpen { return .handled }
            guard vm.mode == .emoji else { return .ignored }
            move(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if menuOpen { return .handled }
            guard vm.mode == .emoji else { return .ignored }
            move(1)
            return .handled
        }
        // With a menu open, plain ↵ activates its highlighted row. A modified ↵ always runs the selection's own action regardless of menu state: ⌘↵ the secondary copy action (each menu advertises it), ⌥↵ paste-in-place; plain ↵ (no menu) falls through to the field's onSubmit.
        .onKeyPress(keys: [.return], phases: .down) { press in
            let command = press.modifiers.contains(.command)
            let option = press.modifiers.contains(.option)
            if menuOpen, !command, !option {
                activateMenuItem(menuSelection)
                return .handled
            }
            guard command || option else { return .ignored }
            switch vm.mode {
            case .emoji:
                guard emojiResults.indices.contains(selection) else { return .ignored }
                if command {
                    core.copyEmoji(emojiResults[selection])
                } else {
                    core.pasteEmojiKeepingWindowOpen(emojiResults[selection])
                }
            case .clipboard:
                guard command, clipResults.indices.contains(selection) else { return .ignored }
                core.copyToClipboard(clipResults[selection])
            case .calculatorHistory:
                // The inline calc card (index 0 when present) has no secondary action; only stored entries respond.
                let index = selection - calcCount
                guard command, histResults.indices.contains(index) else { return .ignored }
                core.copyHistoryExpression(histResults[index])
            case .launcher:
                // ⌘↵ quits the selected app when it's running (the Actions menu advertises it); nothing else in the launcher takes a modified ↵. The condition mirrors the menu row's exactly, so the key never swallows a press it won't act on.
                guard command, let app = selectedAppEntry, app.kind == .application,
                    core.runningApps.isRunning(app)
                else { return .ignored }
                core.quit(app)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if showActions || showAppMenu {
                closeMenus()
                return .handled
            }
            core.hidePalette()
            return .handled
        }
        .onKeyPress(.tab) {
            if menuOpen { return .handled }
            toggleMode()
            return .handled
        }
        .onKeyPress(keys: [","], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            core.showSettings()
            return .handled
        }
        // ⌘K toggles the actions panel for the current selection.
        .onKeyPress(keys: ["k"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            // The Actions menu has no anchor in the compact bar (no bottom bar); swallow ⌘K there.
            guard !isCollapsed else { return .handled }
            guard resultCount > 0 else { return .handled }
            // An error calc card is the selection but has no actions — don't open an empty panel.
            if calcCount > 0, selection == 0, calcResult?.isActionable != true { return .handled }
            toggleActions()
            return .handled
        }
        // Bare backspace (back out of a sub-screen when the search is empty) is intercepted by PalettePanel.sendEvent — the field editor consumes it before onKeyPress could fire.
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            if menuOpen { return .handled }
            guard press.modifiers.contains(.command) else { return .ignored }
            switch vm.mode {
            case .clipboard:
                deleteSelectedClip()
            case .calculatorHistory:
                deleteSelectedHistoryEntry()
            case .launcher, .emoji:
                return .ignored
            }
            return .handled
        }
        // ⌘P pins/unpins the selected clip — mirrors the Actions menu row, and works while that menu is open like the other advertised chords.
        .onKeyPress(keys: ["p"], phases: .down) { press in
            guard press.modifiers.contains(.command), vm.mode == .clipboard,
                clipResults.indices.contains(selection)
            else { return .ignored }
            core.togglePinnedClip(clipResults[selection])
            return .handled
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            // Clipboard and Calculator History are sub-screens of the root search, so their header icon is a back chevron instead of a mode glyph.
            if vm.mode != .launcher {
                Button(action: exitToLauncher) {
                    Image(systemName: "chevron.left")
                        .font(Theme.Typography.headerIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: Theme.Size.headerIconSlot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: vm.mode.systemImage)
                    .font(Theme.Typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Size.headerIconSlot)
            }
            searchField
            // Compact bar pins favorites to the right of the field; expanded shows them as list rows instead.
            if isCollapsed, settings.showFavoritesInCompactMode {
                let slots = compactFavoriteSlots
                if !slots.isEmpty {
                    CompactFavoritesRow(
                        slots: slots,
                        onLaunch: { core.launch($0) },
                        onOverflow: { core.expandFromCompact() }
                    )
                }
            }
        }
        // Align the search icon with the list rows and section headers below (list inset + row inset).
        .padding(.horizontal, Theme.Spacing.md * 2)
        // Fixed row height + top padding, identical in both states, so typing (which flips compact→expanded) can't move the search bar. Compact centers the row in symmetric slack; expanded floats the same row over the list.
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    /// The one search field, kept in a single tree position (the `header`) so its focus survives the compact↔expanded swap.
    private var searchField: some View {
        TextField(
            "", text: $vm.query,
            prompt: Text(vm.mode.placeholder).foregroundStyle(Theme.Colors.textTertiary)
        )
        .textFieldStyle(.plain)
        .font(Theme.Typography.searchField)
        .tint(.white)
        .focused($searchFocused)
        .onSubmit(activateSelection)
    }

    @ViewBuilder
    private func content(
        apps: [AppEntry], clips: [ClipboardItem], hist: [CalcHistoryEntry],
        emojiSections: [EmojiGridSection], calc: CalcResult?,
        selection: Int, favoriteCount: Int, showSections: Bool
    ) -> some View {
        switch vm.mode {
        case .launcher:
            let offset = calc == nil ? 0 : 1
            let calcSelected = calc != nil && selection == 0
            let appIndex = selection - offset
            let selectedID = apps.indices.contains(appIndex) ? apps[appIndex].id : nil
            LauncherList(
                results: apps,
                selectedID: calcSelected ? nil : selectedID,
                favoriteCount: favoriteCount,
                showSections: showSections,
                scrollToken: scrollToken,
                calc: calc,
                calcSelected: calcSelected,
                onActivateCalc: {
                    vm.selection = 0
                    activateSelection()
                },
                onCalcActions: {
                    guard let calc, case .value = calc.payload else { return }
                    vm.selection = 0
                    openActions()
                },
                onActivate: { core.launch($0, searchQuery: vm.query) },
                onActions: { app in
                    if let index = apps.firstIndex(of: app) { vm.selection = index + offset }
                    openActions()
                }
            )
        case .clipboard:
            // Empty history: center one message across the whole panel rather than wedging it into the narrow list column beside a blank preview.
            if clips.isEmpty {
                EmptyResults(text: "Clipboard history is empty")
            } else {
                let selected = clips.indices.contains(selection) ? clips[selection] : nil
                HStack(spacing: 0) {
                    ClipboardList(
                        results: clips,
                        selectedID: selected?.id,
                        scrollToken: scrollToken,
                        onSelect: { item in vm.selection = clips.firstIndex(of: item) ?? 0 },
                        onActivate: activateSelection,
                        onActions: { item in
                            if let index = clips.firstIndex(of: item) { vm.selection = index }
                            openActions()
                        }
                    )
                    .frame(width: Theme.Size.clipboardListWidth)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(width: 1)
                    ClipboardPreview(item: selected)
                }
            }
        case .calculatorHistory:
            if hist.isEmpty && calc == nil {
                EmptyResults(
                    text: isQueryEmpty ? "No calculations yet" : "No matching calculations")
            } else {
                let offset = calc == nil ? 0 : 1
                let calcSelected = calc != nil && selection == 0
                let histIndex = selection - offset
                let selected = hist.indices.contains(histIndex) ? hist[histIndex] : nil
                CalculatorHistoryList(
                    results: hist,
                    selectedID: calcSelected ? nil : selected?.id,
                    scrollToken: scrollToken,
                    calc: calc,
                    calcSelected: calcSelected,
                    onActivateCalc: {
                        vm.selection = 0
                        activateSelection()
                    },
                    onCalcActions: {
                        guard let calc, case .value = calc.payload else { return }
                        vm.selection = 0
                        openActions()
                    },
                    onSelect: { entry in
                        if let index = hist.firstIndex(of: entry) { vm.selection = index + offset }
                    },
                    onActivate: activateSelection,
                    onActions: { entry in
                        if let index = hist.firstIndex(of: entry) { vm.selection = index + offset }
                        openActions()
                    }
                )
            }
        case .emoji:
            if !emojiIndex.isLoaded {
                EmptyResults(text: "Loading emoji…")
            } else if emojiSections.isEmpty {
                EmptyResults(text: "No emoji found")
            } else {
                EmojiGridView(
                    sections: emojiSections,
                    selection: selection,
                    tone: settings.emojiSkinTone,
                    scroll: emojiScroll,
                    onSelect: { vm.selection = $0 },
                    onActivate: activateSelection,
                    onActions: { flat in
                        vm.selection = flat
                        openActions()
                    }
                )
            }
        case .aiChat:
            AIChatView()
        }
    }

    private func bottomBar(pillLabel: String, showActionGroup: Bool) -> some View {
        // No bar — just floating glass controls over the list; the edge dissolve ghosts rows passing beneath, so the buttons read clearly without a hard-edged strip.
        HStack(spacing: 0) {
            appMenuButton
            Spacer()
            if showActionGroup { actionGroup(pillLabel: pillLabel) }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    private var appMenuButton: some View {
        MenuCircleButton {
            withAnimation(Self.menuAnimation) { showAppMenu.toggle() }
        }
    }

    /// The footer control group: primary action and the Actions toggle sharing one glass capsule.
    private func actionGroup(pillLabel: String) -> some View {
        HStack(spacing: 2) {
            BarButton(action: activateSelection) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(pillLabel)
                        .font(Theme.Typography.bar)
                        .foregroundStyle(.primary)
                    KeyCapChip(text: "↵", style: .outline)
                }
            }
            BarButton(action: toggleActions) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Actions")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack(spacing: Theme.Spacing.xxs) {
                        KeyCapChip(text: "⌘", style: .outline)
                        KeyCapChip(text: "K", style: .outline)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    /// Pill label for the current selection, derived from the selection already resolved in `body` so it never re-runs the (unmemoized) `appResults` filter/sort.
    private func actionPillLabel(selectedApp: AppEntry?, calcActionable: Bool) -> String {
        switch vm.mode {
        case .clipboard, .emoji:
            return vm.pasteTarget?.pasteTitle ?? "Paste"
        case .calculatorHistory:
            return "Copy Answer"
        case .launcher:
            if calcActionable { return "Copy Answer" }
            switch selectedApp?.kind {
            case .systemSettings: return "Open System Setting"
            case .command: return "Open Command"
            default: return "Open Application"
            }
        }
    }

    /// The single path that opens the Actions menu: samples the state its rows depend on, then shows it. Callers set `vm.selection` first, so the sample matches the row the menu is for.
    private func openActions() {
        // Only the launcher's menu carries a Quit row, so the other modes skip the (unmemoized) `appResults` walk entirely.
        if vm.mode == .launcher, let app = selectedAppEntry {
            selectionIsRunning = core.runningApps.isRunning(app)
        } else {
            selectionIsRunning = false
        }
        withAnimation(Self.menuAnimation) { showActions = true }
    }

    private func toggleActions() {
        if showActions {
            withAnimation(Self.menuAnimation) { showActions = false }
        } else {
            openActions()
        }
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) {
            showActions = false
            showAppMenu = false
        }
    }

    /// Inset of the menu panels from the window's bottom corners, kept just inside the rounded corner so the menu's own corner isn't clipped.
    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }

    private func deleteSelectedClip() {
        guard clipResults.indices.contains(selection) else { return }
        store.remove(clipResults[selection])
    }

    private func deleteSelectedHistoryEntry() {
        let index = selection - calcCount  // the inline calc card can't be deleted
        guard histResults.indices.contains(index) else { return }
        calcHistory.remove(histResults[index])
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard resultCount > 0 else { return }
        vm.selection = min(max(selection + delta, 0), resultCount - 1)
        scrollToken = UUID()
        emojiScroll = EmojiScrollIntent(kind: .follow)
    }

    /// Move the open menu's highlight, clamped at the ends (no wrap — consistent with `move`).
    private func moveMenu(_ delta: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), count - 1)
    }

    /// The single activation path for a menu row, shared by a click and Return: run the row's action, then close.
    private func activateMenuItem(_ index: Int) {
        guard let items = menuContent?.items, items.indices.contains(index) else { return }
        items[index].action()
        closeMenus()
    }

    /// Vertical grid move: one visual row within a section, spilling into the neighbor while keeping the column.
    private func moveEmojiRow(_ delta: Int) {
        let geometry = EmojiGridGeometry(
            counts: emojiSections.map(\.entries.count), columns: EmojiGrid.columns)
        guard resultCount > 0 else { return }
        vm.selection = delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        emojiScroll = EmojiScrollIntent(kind: .follow)
    }

    /// Tab flips launcher↔clipboard; Calculator History (entered via its command) exits back to the launcher rather than joining the cycle.
    private func toggleMode() {
        vm.mode = vm.mode == .launcher ? .clipboard : .launcher
    }

    /// Back out to a fresh root search — `prepare` is the same reset used when the palette is shown (clears query/selection, bumps focusToken to refocus the field).
    private func exitToLauncher() {
        vm.prepare(mode: .launcher)
    }

    private func activateSelection() {
        // Nothing is visibly selected in the collapsed compact bar; launch only via ⌘1–⌘5 or by typing.
        guard !isCollapsed else { return }
        switch vm.mode {
        case .launcher:
            if let calcResult, selection == 0 {
                // Error cards no-op — copyCalculatorResult only acts on value payloads.
                core.copyCalculatorResult(calcResult)
                return
            }
            let index = selection - calcCount
            guard appResults.indices.contains(index) else { return }
            core.launch(appResults[index], searchQuery: vm.query)
        case .clipboard:
            guard clipResults.indices.contains(selection) else { return }
            core.paste(clipResults[selection])
        case .calculatorHistory:
            if let calcResult, selection == 0 {
                // A fresh calculation typed into the history search: copy + record like the launcher card (error cards no-op).
                core.copyCalculatorResult(calcResult)
                return
            }
            let index = selection - calcCount
            guard histResults.indices.contains(index) else { return }
            core.copyHistoryEntry(histResults[index])
        case .emoji:
            guard emojiResults.indices.contains(selection) else { return }
            core.pasteEmoji(emojiResults[selection])
        case .aiChat:
            // Enter sends the message
            Task {
                await core.aiStore.sendMessage(vm.query)
                vm.query = ""
            }
        }
    }
}

/// Change key for the clipboard list's follow-the-moved-row handler: the newest stored clip (a capture or promote puts a different row there) plus the token an action bumps when it reorders the list (pin/unpin). Deliberately read from the store, not the filtered results, so typing a query never reads as a row that moved.
private struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

/// The footer's glass menu circle; hover lives here so a mouse sweep never re-renders the palette body.
private struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: Theme.Size.menuButton, height: Theme.Size.menuButton)
            .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

/// Footer button: bare label at rest, a faint capsule fill on hover.
private struct BarButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 28)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

extension View {
    /// Faint mouse-hover highlight for a palette row, lit only while the pointer is physically moving (`hoverHighlightArmed`) so it never fires on open or when rows slide under a still pointer during keyboard nav. Independent of the keyboard selection, so both coexist.
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active: hovered.wrappedValue = AppCore.shared.palette.hoverHighlightArmed
            case .ended: hovered.wrappedValue = false
            }
        }
    }
}

struct EmptyResults: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A slot in the compact bar's favorites strip: a launchable app, or the "…" overflow that expands the window.
enum CompactFavoriteSlot {
    case app(AppEntry)
    case more

    // Stable identity so a slot keeps its icon tied to its app, not its position, when favorites reorder.
    var id: String {
        switch self {
        case .app(let app): return app.id
        case .more: return "__tinycast.more__"
        }
    }
}

/// The compact bar's favorites strip — up to 5 icon buttons, ⌘1–⌘5 mirrored in each tooltip.
private struct CompactFavoritesRow: View {
    let slots: [CompactFavoriteSlot]
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                switch slot {
                case .app(let app):
                    CompactFavoriteButton(help: "\(app.name)  ⌘\(index + 1)") {
                        onLaunch(app)
                    } content: {
                        AppIconView(app: app)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    }
                case .more:
                    CompactFavoriteButton(help: "Show all  ⌘\(index + 1)", action: onOverflow) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.Colors.controlSurface)
                                    .padding(Theme.Spacing.xxs)
                            )
                    }
                }
            }
        }
    }
}

/// A single compact favorite icon: bare icon, native tooltip, click action — no hover chrome, kept tight so the strip reads as one cluster.
private struct CompactFavoriteButton<Content: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
