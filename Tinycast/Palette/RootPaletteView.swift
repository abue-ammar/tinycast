import SwiftUI

struct RootPaletteView: View {
    @Environment(AppCore.self) private var core
    @Environment(PaletteState.self) private var vm
    @Environment(AppIndex.self) private var appIndex
    @Environment(ClipboardStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(VisibilityStore.self) private var visibility
    @Environment(CalculatorHistoryStore.self) private var calcHistory
    /// Observed so the card re-evaluates when a snapshot lands or consent changes.
    @Environment(CurrencyRateStore.self) private var currencyRates
    @Environment(EmojiIndex.self) private var emojiIndex
    @Environment(FrequentEmojiStore.self) private var frequentEmoji
    @Environment(FileSearchSession.self) private var fileSearch
    @Environment(UninstallSession.self) private var uninstall
    @Environment(QuicklinkStore.self) private var quicklinks
    @Environment(QuicklinkArgumentSession.self) private var quicklinkArguments
    @Environment(ExtensionManager.self) private var extensions
    @Environment(AppSettings.self) private var settings
    @FocusState private var searchFocused: Bool
    /// Focus inside the inline argument fields, kept apart from the search field's own — the palette's
    /// focus model hangs off one always-attached `TextField`. See docs/features/palette.md.
    @FocusState private var argumentFocused: String?
    @State private var showActions = false
    @State private var showAppMenu = false
    /// Sampled once by `openActions`, so the Quit row can't appear while the menu is up.
    @State private var selectionIsRunning = false
    /// Highlighted row of whichever menu is open; reset to the first row on open.
    @State private var menuSelection = 0
    /// The pending scroll request; modes are exclusive, so one piece of state serves all.
    @State private var scroll = ScrollIntent(kind: .top)

    /// Compact vs. full; the source of truth is on `AppCore`, so the two can't disagree.
    private var isCollapsed: Bool { core.paletteCoordinator.paletteIsCollapsed }

    /// The current mode's screen: its rows are the visible order the flat selection indexes.
    private var screen: any PaletteScreen {
        switch vm.mode {
        case .launcher:
            return LauncherScreen(
                appIndex: appIndex, favorites: favorites, visibility: visibility,
                currencyRates: currencyRates, core: core, vm: vm, running: selectionIsRunning,
                openActions: openActions)
        case .uninstall:
            return UninstallScreen(
                session: uninstall, core: core, vm: vm, openActions: openActions)
        case .quicklinkArguments:
            return QuicklinkArgumentsScreen(
                session: quicklinkArguments, core: core, vm: vm,
                scrollToTop: { scroll = ScrollIntent(kind: .top) })
        case .quicklinks:
            return QuicklinkListScreen(
                store: quicklinks, core: core, vm: vm, openActions: openActions)
        case .emoji:
            return EmojiScreen(
                index: emojiIndex, frequent: frequentEmoji, core: core, vm: vm,
                tone: settings.emojiSkinTone, openActions: openActions)
        case .fileSearch:
            return FileSearchScreen(
                session: fileSearch, core: core, vm: vm, openActions: openActions)
        case .clipboard:
            return ClipboardScreen(
                store: store, core: core, vm: vm, openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .calculatorHistory:
            return CalculatorHistoryScreen(
                history: calcHistory, currencyRates: currencyRates, core: core, vm: vm,
                openActions: openActions)
        case .extensionCommand:
            return ExtensionCommandScreen(
                screen: extensionScreen, extensions: extensions, core: core, vm: vm,
                openActions: openActions)
        }
    }

    /// The running command's rendered screen, flattened. `.empty` until the first commit lands.
    private var extensionScreen: ExtensionScreen {
        guard vm.mode == .extensionCommand, case .rendered(let tree) = extensions.state else {
            return .empty
        }
        return ExtensionScreen(tree: tree, query: vm.query)
    }

    /// Selection clamped into the results: one source for highlight, preview and activation.
    private func selection(count: Int) -> Int {
        count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    /// Takes a resolved screen — reaching `rows` costs a list build, so callers resolve it once.
    private func selection(in screen: any PaletteScreen) -> Int {
        selection(count: screen.rows.count)
    }

    private var menuOpen: Bool { showActions || showAppMenu }

    // MARK: - Popover menu content

    /// The Actions menu for the current selection, or nil when it has no actions.
    private var actionsContent: PopoverMenuContent? {
        let screen = screen
        return screen.actions(at: selection(in: screen))
    }

    /// The bottom-left app menu content (About / Settings).
    private var appMenuContent: PopoverMenuContent {
        PopoverMenuContent(items: [
            PopoverMenuItem(title: "About Tinycast", systemImage: "info.circle") {
                core.settingsCoordinator.showAbout()
            },
            PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                core.settingsCoordinator.showSettings()
            }
        ])
    }

    /// Whichever menu is open; the two are mutually exclusive, Actions taking precedence.
    private var menuContent: PopoverMenuContent? {
        if showActions { return actionsContent }
        if showAppMenu { return appMenuContent }
        return nil
    }

    var body: some View {
        // Resolve the screen once per render, so the flat index can't drift from the rows.
        let screen = screen
        let count = screen.rows.count
        let sel = selection(count: count)
        // The argument form has no rows to count, but ↵ still does something.
        let showActionGroup =
            (count > 0 || vm.mode == .quicklinkArguments) && screen.hasPrimaryAction(at: sel)

        // One header position, so focus survives the swap. See docs/features/palette.md.
        return Group {
            if isCollapsed {
                Color.clear
            } else {
                screen.body(selection: sel, scroll: scroll)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isCollapsed {
                bottomBar(
                    pillLabel: screen.primaryActionTitle, showActionGroup: showActionGroup)
            }
        }
        // The panel has no title bar, so this thin top margin is the only place left to grab it.
        .overlay(alignment: .top) { topDragStrip }
        .modifier(ExtensionToastOverlay(extensions: extensions, showing: vm.mode == .extensionCommand))
        // In-window overlays, so a menu stays clipped inside the panel.
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
        // The window's frame is the size source, so the glass and clip stay matched.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // Every show bumps focusToken: refocus search and drop any menu left open.
        .onChange(of: vm.focusToken) {
            searchFocused = true
            showActions = false
            showAppMenu = false
        }
        .onChange(of: vm.query) {
            vm.selection = 0
            scroll = ScrollIntent(kind: .top)
            if vm.mode == .fileSearch { fileSearch.search(vm.query) }
            // A command that took over the search text filters its own list.
            if vm.mode == .extensionCommand, let handler = extensionScreen.searchTextHandler {
                extensions.dispatch(handler: handler, arguments: [vm.query])
            }
        }
        .onChange(of: vm.mode) {
            vm.selection = 0
            showActions = false
            scroll = ScrollIntent(kind: .top)
            // Every way out of the Uninstall screen: back chevron, bare backspace, a fresh summon.
            if vm.mode != .uninstall { uninstall.cancel() }
            if vm.mode != .fileSearch { fileSearch.cancel() }
            // Leaving the screen any other way than Escape still ends the command's session.
            if vm.mode != .extensionCommand, extensions.running != nil {
                Task { await extensions.stop() }
            }
            // Same for a half-filled argument form: leaving the screen abandons the pending open.
            if vm.mode != .quicklinkArguments { core.quicklinkCoordinator.cancelQuicklinkArguments() }
        }
        // `prepare` may change nothing, so this intent still snaps the scroll to the origin.
        .onChange(of: vm.resetToken) {
            scroll = ScrollIntent(kind: .top)
        }
        // Opening either menu closes the other, so exactly one is open and highlighted.
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
        .onAppear { searchFocused = true }
        // Several paths flip `paletteIsCollapsed`, so resize the window to match.
        .onChange(of: core.paletteCoordinator.paletteIsCollapsed) {
            core.paletteCoordinator.syncPaletteSize()
        }
        // ⌘1–⌘5 launch the compact bar's favorite slots, or expand for the overflow.
        .onKeyPress(keys: ["1", "2", "3", "4", "5"], phases: .down) { press in
            guard isCollapsed, settings.showFavoritesInCompactMode,
                press.modifiers.contains(.command),
                let digit = press.key.character.wholeNumberValue,
                let launcher = screen as? LauncherScreen
            else { return .ignored }
            let slots = launcher.compactFavoriteSlots
            let index = digit - 1
            guard slots.indices.contains(index) else { return .ignored }
            switch slots[index] {
            case .app(let app): core.launcherCoordinator.launch(app)
            case .more: core.paletteCoordinator.expandFromCompact()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if isCollapsed {
                // The compact bar shows no selection, so Down reveals the list's first row.
                vm.selection = 0
                core.paletteCoordinator.expandFromCompact()
                return .handled
            }
            if menuOpen {
                moveMenu(1)
                return .handled
            }
            moveVertically(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isCollapsed { return .ignored }
            if menuOpen {
                moveMenu(-1)
                return .handled
            }
            moveVertically(-1)
            return .handled
        }
        // Horizontal arrows step the grid; elsewhere they stay with the caret.
        .onKeyPress(.leftArrow) {
            if menuOpen { return .handled }
            return moveHorizontally(-1) ? .handled : .ignored
        }
        .onKeyPress(.rightArrow) {
            if menuOpen { return .handled }
            return moveHorizontally(1) ? .handled : .ignored
        }
        // Plain ↵ activates an open menu's row; a modified ↵ always runs the selection's.
        .onKeyPress(keys: [.return], phases: .down) { press in
            let command = press.modifiers.contains(.command)
            let option = press.modifiers.contains(.option)
            if menuOpen, !command, !option {
                activateMenuItem(menuSelection)
                return .handled
            }
            guard command || option else { return .ignored }
            let screen = screen
            let selection = selection(in: screen)
            if command { return screen.secondary(at: selection) ? .handled : .ignored }
            return screen.pasteKeepingWindowOpen(at: selection) ? .handled : .ignored
        }
        .onKeyPress(.escape) {
            if showActions || showAppMenu {
                closeMenus()
                return .handled
            }
            // An extension pops its own navigation stack before the command is left.
            if vm.mode == .extensionCommand {
                core.extensionCoordinator.exitExtensionScreen()
                return .handled
            }
            core.paletteCoordinator.hidePalette()
            return .handled
        }
        .onKeyPress(.tab) {
            if !menuOpen { advanceTabFocus() }
            return .handled
        }
        .modifier(
            ExtensionShortcutKeys(
                screen: menuOpen ? nil : screen as? ExtensionCommandScreen, selection: sel)
        )
        // ⌘K toggles the actions panel for the current selection.
        .onKeyPress(keys: ["k"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            // The Actions menu has no anchor in the compact bar, so swallow ⌘K there.
            guard !isCollapsed else { return .handled }
            let screen = screen
            guard !screen.rows.isEmpty else { return .handled }
            // An error calc card is the selection but has no actions — don't open an empty panel.
            guard screen.hasPrimaryAction(at: selection(in: screen)) else { return .handled }
            toggleActions()
            return .handled
        }
        // Bare backspace is intercepted in `sendEvent`; the field editor eats it first.
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            if menuOpen { return .handled }
            guard press.modifiers.contains(.command) else { return .ignored }
            let screen = screen
            let selection = selection(in: screen)
            if let quicklinks = screen as? QuicklinkListScreen {
                return quicklinks.delete(at: selection) ? .handled : .ignored
            }
            if let clipboard = screen as? ClipboardScreen {
                clipboard.delete(at: selection)
                return .handled
            }
            if let history = screen as? CalculatorHistoryScreen {
                history.delete(at: selection)
                return .handled
            }
            return .ignored
        }
        // ⌃X / ⌃⇧X mirror the delete rows — both cases, Shift uppercasing — and close an open menu.
        .onKeyPress(keys: ["x", "X"], phases: .down) { press in
            guard press.modifiers.contains(.control) else { return .ignored }
            let screen = screen
            let selection = selection(in: screen)
            let all = press.modifiers.contains(.shift)
            switch screen {
            case let clipboard as ClipboardScreen:
                if all { clipboard.deleteAll() } else { clipboard.delete(at: selection) }
            case let history as CalculatorHistoryScreen:
                if all { history.deleteAll() } else { history.delete(at: selection) }
            default:
                return .ignored
            }
            if menuOpen { closeMenus() }
            return .handled
        }
        // ⌘P mirrors the Actions row, and works while that menu is open like the rest.
        .onKeyPress(keys: ["p"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            let screen = screen
            let selection = selection(in: screen)
            if let clipboard = screen as? ClipboardScreen {
                return clipboard.pin(at: selection) ? .handled : .ignored
            }
            if let quicklinks = screen as? QuicklinkListScreen {
                return quicklinks.pin(at: selection) ? .handled : .ignored
            }
            return .ignored
        }
        // Both cases, Shift uppercasing the key; the compact bar shows no target.
        .onKeyPress(keys: ["q", "Q"], phases: .down) { press in
            guard press.modifiers.contains(.control), press.modifiers.contains(.shift),
                !isCollapsed, let launcher = screen as? LauncherScreen
            else { return .ignored }
            return launcher.quit(at: selection(in: launcher)) ? .handled : .ignored
        }
    }

    /// A thin strip along the top edge for grabbing the window; the Appearance setting gates it.
    private var topDragStrip: some View {
        Color.clear
            .frame(height: Theme.Size.headerPadding)
            .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
    }

    /// A header sliver nothing occupies — safe to drag; the search field handles its own.
    private func headerGutter(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width)
            .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
    }

    private func beginDrag() { core.paletteCoordinator.beginPaletteDrag() }
    private func endDrag() { core.paletteCoordinator.endPaletteDrag() }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            // Matches the list rows and section headers' own indent below.
            headerGutter(width: Theme.Spacing.md * 2)
            // Sub-screens of the root search, so their header icon is a back chevron.
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
            headerGutter(width: Theme.Spacing.md)
            // One structural position, always: putting the field inside a branch tears down its
            // field editor when the branch flips, which drops first responder mid-navigation.
            // The width shrinks to the typed text so argument fields sit right after it, as in Raycast.
            searchField.frame(width: selectedCommandArguments.map(searchFieldWidth))
            if let arguments = selectedCommandArguments {
                CommandArgumentsRow(
                    arguments: arguments,
                    icon: (screen as? LauncherScreen)?.argumentIconPath(
                        at: selection(count: screen.rows.count)),
                    value: argumentBinding,
                    focused: $argumentFocused,
                    onSubmit: activateSelection)
                Spacer(minLength: 0)
            }
            // Compact pins favorites beside the field; expanded shows them as rows.
            if isCollapsed, settings.showFavoritesInCompactMode,
                let launcher = screen as? LauncherScreen
            {
                let slots = launcher.compactFavoriteSlots
                if !slots.isEmpty {
                    headerGutter(width: Theme.Spacing.md)
                    CompactFavoritesRow(
                        slots: slots,
                        onLaunch: { core.launcherCoordinator.launch($0) },
                        onOverflow: { core.paletteCoordinator.expandFromCompact() }
                    )
                }
            }
            headerGutter(width: Theme.Spacing.md * 2)
        }
        // Identical metrics in both states, so typing can't move the search bar.
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    /// Arguments the selected launcher row declares. Only the launcher shows them — inside a running
    /// command the search bar belongs to the extension.
    private var selectedCommandArguments: [ExtensionCommandArgument]? {
        guard vm.mode == .launcher, !isCollapsed, let launcher = screen as? LauncherScreen
        else { return nil }
        return launcher.commandArguments(at: selection(count: launcher.rows.count))
    }

    private func argumentBinding(_ name: String) -> Binding<String> {
        let key = PaletteState.argumentKey(selectedEntryID ?? "", name)
        return Binding(
            get: { vm.commandArguments[key] ?? "" },
            set: { vm.commandArguments[key] = $0 })
    }

    private var selectedEntryID: String? {
        guard let launcher = screen as? LauncherScreen else { return nil }
        let rows = launcher.rows
        let index = selection(count: rows.count)
        guard rows.indices.contains(index), case .entry(let app) = rows[index] else { return nil }
        return app.id
    }

    /// Width the search field shrinks to when argument fields are beside it: the typed text's own
    /// width, floored so the caret always has room and capped so the fields can't be pushed off-screen.
    private func searchFieldWidth(for arguments: [ExtensionCommandArgument]) -> CGFloat {
        let font = Theme.Typography.searchFieldNSFont
        let typed = (vm.query as NSString).size(withAttributes: [.font: font]).width
        let strip = CommandArgumentsRow.totalWidth(
            for: arguments,
            hasIcon: (screen as? LauncherScreen)?
                .argumentIconPath(at: selection(count: screen.rows.count)) != nil)
        let chrome = Theme.Size.headerIconSlot + Theme.Spacing.md * 4
        // +3pt so the caret sits after the last glyph rather than on top of it.
        return min(max(typed + 3, 18), max(Theme.Size.panelWidth - strip - chrome, 60))
    }

    /// In the argument form the field is that argument's input, so it names the argument.
    private var searchPrompt: String {
        // The field is only wide enough for the caret while argument fields are beside it.
        if selectedCommandArguments != nil { return "" }
        if vm.mode == .quicklinkArguments { return quicklinkArguments.prompt }
        // Inside a running command the search bar belongs to the extension.
        if vm.mode == .extensionCommand, let placeholder = extensionScreen.searchPlaceholder {
            return placeholder
        }
        return vm.mode.placeholder
    }

    /// The one search field — past its text it's a drag handle, matching Spotlight.
    private var searchField: some View {
        @Bindable var vm = vm
        return TextField("", text: $vm.query)
            .textFieldStyle(.plain)
            .font(Theme.Typography.searchField)
            .tint(.white)
            .focused($searchFocused)
            .onSubmit(activateSelection)
            // Fills the row's height, so there's no gap above it for topDragStrip to meet.
            .frame(maxHeight: .infinity)
            .background(alignment: .leading) {
                if vm.query.isEmpty {
                    Text(searchPrompt)
                        .font(Theme.Typography.searchField)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        // Never a click target: tapping the placeholder must still land the caret.
                        .allowsHitTesting(false)
                }
            }
            // The prompt used to carry this; without it the field would be unlabelled.
            .accessibilityLabel(Text(searchPrompt))
            // Never branches on query — that tore down the field editor mid-keystroke once.
            .overlay {
                if settings.paletteDraggable {
                    TextTrailingDragHandle(
                        text: vm.query, font: Theme.Typography.searchFieldNSFont,
                        onBegan: beginDrag, onEnded: endDrag)
                }
            }
            // The panel resolves the pointer against this rather than hit-testing for the field.
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                vm.searchFieldFrame = $0
            }
    }

    /// The Uninstall screen's primary action is destructive, so its pill isn't white.
    private var pillTint: Color {
        vm.mode == .uninstall ? Theme.Colors.destructive : .primary
    }

    private func bottomBar(pillLabel: String, showActionGroup: Bool) -> some View {
        // Floating controls, no bar; the edge dissolve ghosts the rows passing beneath.
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
                        .foregroundStyle(pillTint)
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

    /// The one path opening the Actions menu, sampling the state its rows depend on.
    private func openActions() {
        let launcher = screen as? LauncherScreen
        selectionIsRunning = launcher.map { $0.isRunning(at: selection(in: $0)) } ?? false
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

    /// Inset from the bottom corners, so the menu's own corner isn't clipped.
    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }

    // MARK: - Actions

    private func move(_ delta: Int, in screen: any PaletteScreen) {
        let count = screen.rows.count
        guard count > 0 else { return }
        vm.selection = min(max(selection(count: count) + delta, 0), count - 1)
        scroll = ScrollIntent(kind: .follow)
    }

    /// ↑/↓: the screen's own move where it has one, else a linear step through the rows.
    private func moveVertically(_ delta: Int) {
        // Moving off a command takes its argument fields with it, so hand focus back first.
        if argumentFocused != nil {
            argumentFocused = nil
            searchFocused = true
        }
        let screen = screen
        guard let next = screen.move(delta, axis: .vertical, from: selection(in: screen)) else {
            move(delta, in: screen)
            return
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
    }

    /// ←/→: consumed only by a horizontally navigating screen, else the caret keeps them.
    private func moveHorizontally(_ delta: Int) -> Bool {
        let screen = screen
        guard let next = screen.move(delta, axis: .horizontal, from: selection(in: screen)) else {
            return false
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return true
    }

    /// Move the open menu's highlight, clamped at the ends (no wrap — consistent with `move`).
    private func moveMenu(_ delta: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), count - 1)
    }

    /// The one activation path for a menu row: run its action, then close.
    private func activateMenuItem(_ index: Int) {
        guard let items = menuContent?.items, items.indices.contains(index) else { return }
        items[index].action()
        closeMenus()
    }

    /// Tab flips launcher↔clipboard; Calculator History exits rather than joining.
    private func toggleMode() {
        vm.mode = vm.mode == .launcher ? .clipboard : .launcher
    }

    /// Tab walks the inline argument fields first — search field → each argument → back — and only
    /// toggles the mode when the selection declares none.
    private func advanceTabFocus() {
        guard let arguments = selectedCommandArguments else { return toggleMode() }
        argumentFocused = CommandArgumentsRow.next(after: argumentFocused, in: arguments)
        searchFocused = argumentFocused == nil
    }

    /// Back out to a fresh root search, the same reset `prepare` does on show.
    private func exitToLauncher() {
        if vm.mode == .extensionCommand {
            core.extensionCoordinator.exitExtensionScreen()
            return
        }
        vm.prepare(mode: .launcher)
    }

    private func activateSelection() {
        // Nothing is visibly selected when collapsed, so launch via ⌘1–⌘5 or typing.
        guard !isCollapsed else { return }
        // A required argument left blank blocks the launch; focus the first one instead.
        if let blank = firstBlankRequiredArgument {
            argumentFocused = blank
            searchFocused = false
            return
        }
        let screen = screen
        screen.activate(at: selection(in: screen))
    }

    private var firstBlankRequiredArgument: String? {
        guard let arguments = selectedCommandArguments, let entryID = selectedEntryID else {
            return nil
        }
        return arguments.first {
            $0.required
                && (vm.commandArguments[PaletteState.argumentKey(entryID, $0.name)] ?? "").isEmpty
        }?.name
    }
}

/// The footer's menu circle; hover lives here, so a sweep never re-renders the body.
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

private struct ArmedHover: ViewModifier {
    @Environment(PaletteState.self) private var palette
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active: hovered = palette.hoverHighlightArmed
                case .ended: hovered = false
                }
            }
            // Disarming under a still pointer fires no hover phase, so the drop clears the row.
            .onChange(of: palette.hoverDisarmToken) { hovered = false }
    }
}

extension View {
    /// Row hover, lit only while the pointer moves; independent of the keyboard selection.
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        modifier(ArmedHover(hovered: hovered))
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

/// A compact-bar favorites slot: a launchable app, or the overflow that expands.
enum CompactFavoriteSlot {
    case app(AppEntry)
    case more

    // Stable identity, so a reorder moves icons with their app rather than by position.
    var id: String {
        switch self {
        case .app(let app): return app.id
        case .more: return "__tinycast.more__"
        }
    }
}

/// The compact bar's favorites strip: up to 5 buttons, ⌘1–⌘5 in each tooltip.
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

/// One compact favorite: bare icon, tooltip, action; no hover chrome, so it reads tight.
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

/// An extension action can declare its own shortcut, matched against the running command's panel
/// before the palette's own bindings see the keystroke. Its own modifier for the same reason as
/// `ExtensionToastOverlay`.
private struct ExtensionShortcutKeys: ViewModifier {
    let screen: ExtensionCommandScreen?
    let selection: Int

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            guard let screen, !press.modifiers.isEmpty else { return .ignored }
            return screen.dispatchShortcut(
                key: press.key, modifiers: press.modifiers, at: selection) ? .handled : .ignored
        }
    }
}

/// Toasts a running view command raised, stacked above the footer. Its own modifier only to keep
/// `RootPaletteView.body` inside what the type checker will solve.
private struct ExtensionToastOverlay: ViewModifier {
    let extensions: ExtensionManager
    let showing: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if showing, !extensions.toasts.isEmpty {
                ExtensionFeedbackOverlay(
                    toasts: extensions.toasts,
                    onToastAction: { extensions.runToastAction(token: $0) })
            }
        }
    }
}
