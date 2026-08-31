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
    @Environment(CalendarStore.self) private var calendarStore
    /// Observed so the join card's countdown redraws on the minute boundary.
    @Environment(MeetingClock.self) private var meetingClock
    @Environment(UninstallSession.self) private var uninstall
    @Environment(QuicklinkStore.self) private var quicklinks
    @Environment(QuicklinkArgumentSession.self) private var quicklinkArguments
    @Environment(CustomCommandArgumentSession.self) private var customCommandArguments
    @Environment(SnippetsStore.self) private var snippets
    @Environment(ExtensionManager.self) private var extensions
    @Environment(AppSettings.self) private var settings
    @FocusState private var searchFocused: Bool
    /// Kept apart from the search field's own focus. See docs/features/palette.md.
    @FocusState private var argumentFocused: String?
    /// Which in-window menu is open; at most one, so the state cannot disagree with itself.
    @State private var openMenu: OpenMenu?
    /// Sampled once by `openActions`, so the running-only rows can't appear while the menu is up.
    @State private var selectionIsRunning = false
    /// Highlighted row of whichever menu is open; each open path sets where it starts.
    @State private var menuSelection = 0
    @State private var menuPanel = MenuPanelController()
    /// The palette's own window, reported by `WindowReader`; the menu hangs off its frame.
    @State private var hostWindow: NSWindow?
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
                meeting: core.calendarCoordinator.cardedMeeting, now: meetingClock.now,
                openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .uninstall:
            return UninstallScreen(
                session: uninstall, core: core, vm: vm, openActions: openActions)
        case .quicklinkArguments:
            return QuicklinkArgumentsScreen(
                session: quicklinkArguments, core: core, vm: vm,
                scrollToTop: { scroll = ScrollIntent(kind: .top) })
        case .customCommandArguments:
            return CustomCommandArgumentsScreen(
                session: customCommandArguments, core: core, vm: vm)
        case .quicklinks:
            return QuicklinkListScreen(
                store: quicklinks, core: core, vm: vm, openActions: openActions)
        case .snippets:
            return SnippetsScreen(
                store: snippets, core: core, vm: vm, openActions: openActions)
        case .emoji:
            return EmojiScreen(
                index: emojiIndex, frequent: frequentEmoji, core: core, vm: vm,
                tone: settings.emojiSkinTone, openActions: openActions)
        case .fileSearch:
            return FileSearchScreen(
                session: fileSearch, core: core, vm: vm, openActions: openActions)
        case .schedule:
            return ScheduleScreen(
                store: calendarStore, clock: meetingClock, core: core, vm: vm,
                openActions: openActions)
        case .clipboard:
            return ClipboardScreen(
                store: store, core: core, vm: vm, openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .ai:
            return AIScreen(
                vm: vm, chat: core.aiChat, settings: core.aiSettings,
                coordinator: core.aiChatCoordinator)
        case .aiHistory:
            return ChatHistoryScreen(
                history: core.chatHistory, chat: core.aiChat, coordinator: core.aiChatCoordinator,
                vm: vm, openActions: openActions)
        case .calculatorHistory:
            return CalculatorHistoryScreen(
                history: calcHistory, currencyRates: currencyRates, core: core, vm: vm,
                openActions: openActions)
        case .extensionCommand:
            return ExtensionCommandScreen(
                screen: extensionScreen, extensions: extensions, vm: vm, openActions: openActions)
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

    private var menuOpen: Bool { openMenu != nil }

    // MARK: - Popover menu content

    /// The clipboard type filter's rows; activating one is the only way the filter changes.
    private var clipboardFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: ClipboardFilter.allCases.map { filter in
                PopoverMenuItem(title: filter.title, systemImage: filter.systemImage) {
                    vm.clipboardFilter = filter
                }
            })
    }

    /// Every model configured for chat; selecting one updates the app-wide default route.
    private var aiModelContent: PopoverMenuContent {
        let options = core.aiChatCoordinator.modelOptions
        guard !options.isEmpty else {
            return PopoverMenuContent(items: [
                PopoverMenuItem(title: "Configure AI", systemImage: "slider.horizontal.3") {
                    core.aiChatCoordinator.showSettings()
                }
            ])
        }
        return PopoverMenuContent(
            items: options.map { option in
                PopoverMenuItem(title: option.menuTitle, icon: option.menuIcon) {
                    core.aiChatCoordinator.selectModel(option)
                }
            })
    }

    /// The bottom-left app menu content (About / Support / Settings).
    private var appMenuContent: PopoverMenuContent {
        PopoverMenuContent(items: [
            PopoverMenuItem(title: "About Tinycast", systemImage: "info.circle") {
                core.settingsCoordinator.showAbout()
            },
            PopoverMenuItem(title: "Support Tinycast", systemImage: "heart") {
                core.supportCoordinator.showSupport()
            },
            PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                core.settingsCoordinator.showSettings()
            }
        ])
    }

    /// The one source every menu path addresses rows through, so none can disagree.
    private var menuContent: PaletteMenuContent? {
        switch openMenu {
        case .actions:
            let screen = screen
            return screen.menuContent(
                at: selection(in: screen), menuSelection: $menuSelection,
                onActivate: activateMenuItem)
        case .app:
            return PaletteMenuContent(
                popover: appMenuContent, selection: $menuSelection, onActivate: activateMenuItem)
        case .clipboardFilter:
            return PaletteMenuContent(
                popover: clipboardFilterContent, selection: $menuSelection,
                width: headerMenuWidth, onActivate: activateMenuItem)
        case .aiModel:
            return PaletteMenuContent(
                popover: aiModelContent, selection: $menuSelection,
                width: headerMenuWidth, onActivate: activateMenuItem)
        case nil: return nil
        }
    }

    var body: some View {
        // Resolve the screen once per render, so the flat index can't drift from the rows.
        let screen = screen
        let count = screen.rows.count
        let sel = selection(count: count)
        // The argument forms have no rows to count, but ↵ still does something.
        let showActionGroup =
            (count > 0 || vm.mode.isArgumentForm) && screen.hasPrimaryAction(at: sel)

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
        // Never conditionally mounted: unmounting strands SwiftUI's hover target and eats clicks.
        .overlay {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                // Not a tap: a drifting press must still dismiss, the way a native menu's does.
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in closeMenus() })
                .allowsHitTesting(menuOpen)
        }
        // The menu lives in its own window; this only reports the one to hang it from.
        .background(WindowReader { hostWindow = $0 })
        // The window's frame is the size source, so the glass and clip stay matched.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // Every show bumps focusToken: refocus search and drop any menu left open.
        .onChange(of: vm.focusToken) {
            searchFocused = true
            openMenu = nil
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
        // A narrower list means the old index points at a different row, or at none.
        .onChange(of: vm.clipboardFilter) {
            vm.selection = 0
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: vm.mode) {
            vm.selection = 0
            vm.clipboardFilter = .all
            openMenu = nil
            scroll = ScrollIntent(kind: .top)
            // Every way out of the Uninstall screen: back chevron, bare backspace, a fresh summon.
            if vm.mode != .uninstall { uninstall.cancel() }
            if vm.mode != .fileSearch { fileSearch.cancel() }
            // Leaving the screen any other way than Escape still ends the command's session.
            if vm.mode != .extensionCommand, extensions.running != nil, !extensions.isAuthorizing {
                Task { await extensions.stop() }
            }
            // Same for a half-filled argument form: leaving the screen abandons the pending run.
            if vm.mode != .quicklinkArguments { core.quicklinkCoordinator.cancelQuicklinkArguments() }
            if vm.mode != .customCommandArguments {
                core.customCommandCoordinator.cancelCustomCommandArguments()
            }
        }
        // `prepare` may change nothing, so this intent still snaps the scroll to the origin.
        .onChange(of: vm.resetToken) {
            scroll = ScrollIntent(kind: .top)
        }
        // ⌘. arrives as a token rather than a key press. See `PaletteState.pinChordToken`.
        .onChange(of: vm.pinChordToken) { pinSelection() }
        // ⌘1…⌘0 arrives as a slot index from AppKit keyCode matching.
        .onChange(of: vm.favoriteSlotToken) { activateFavoriteSlotShortcut() }
        // One optional makes "exactly one menu" structural; this only mirrors it for the panel.
        .onChange(of: openMenu) {
            vm.menuOpen = menuOpen
            syncMenuPanel(presenting: true)
        }
        // The hosted tree is its own hierarchy, so the highlight has to be pushed into it.
        .onChange(of: menuSelection) { syncMenuPanel(presenting: false) }
        .onDisappear { menuPanel.hide() }
        .onAppear { searchFocused = true }
        // Several paths flip `paletteIsCollapsed`, so resize the window to match.
        .onChange(of: core.paletteCoordinator.paletteIsCollapsed) {
            core.paletteCoordinator.syncPaletteSize()
        }
        // Repeat included: holding the key keeps stepping, as the bare-key form does.
        .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { press in
            if let reorder = moveFavorite(1, modifiers: press.modifiers) { return reorder }
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
        .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { press in
            if let reorder = moveFavorite(-1, modifiers: press.modifiers) { return reorder }
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
        // Plain ↵ runs an open menu's row, else the selection; a modified ↵ always the selection's.
        .onKeyPress(keys: [.return], phases: .down) { press in
            let command = press.modifiers.contains(.command)
            let option = press.modifiers.contains(.option)
            if menuOpen, !command, !option {
                activateMenuItem(menuSelection)
                return .handled
            }
            guard command || option else {
                // Claimed before the field editor commits: ending editing reselects a carried query.
                guard searchFocused, !vm.isComposing else { return .ignored }
                activateSelection()
                return .handled
            }
            let screen = screen
            let selection = selection(in: screen)
            if command { return screen.secondary(at: selection) ? .handled : .ignored }
            return screen.pasteKeepingWindowOpen(at: selection) ? .handled : .ignored
        }
        .onKeyPress(.escape) {
            switch PaletteEscapeAction.resolve(menuOpen: menuOpen, query: vm.query, mode: vm.mode) {
            case .closeMenu:
                closeMenus()
            case .clearQuery:
                vm.query = ""
            case .exitExtensionScreen:
                core.extensionCoordinator.exitExtensionScreen()
            case .exitToLauncher:
                exitToLauncher()
            case .hidePalette:
                core.paletteCoordinator.hidePalette()
            }
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
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command),
                ASCIIKeyboardLayout.matches(press.key, character: "k")
            else { return .ignored }
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
            if let history = screen as? ChatHistoryScreen {
                history.delete(at: selection)
                return .handled
            }
            return .ignored
        }
        // ⌃X / ⌃⇧X mirror the delete rows — both cases, Shift uppercasing — and close an open menu.
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.control),
                ASCIIKeyboardLayout.matches(press.key, character: "x")
            else { return .ignored }
            let screen = screen
            let selection = selection(in: screen)
            let all = press.modifiers.contains(.shift)
            switch screen {
            case let clipboard as ClipboardScreen:
                if all { clipboard.deleteAll() } else { clipboard.delete(at: selection) }
            case let history as CalculatorHistoryScreen:
                if all { history.deleteAll() } else { history.delete(at: selection) }
            case let history as ChatHistoryScreen:
                if all { history.deleteAll() } else { history.delete(at: selection) }
            default:
                return .ignored
            }
            if menuOpen { closeMenus() }
            return .handled
        }
        // Never gated on the rows: an over-narrow filter empties them, and this is the way out.
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command),
                ASCIIKeyboardLayout.matches(press.key, character: "p")
            else { return .ignored }
            guard !isCollapsed, vm.mode == .clipboard else { return .ignored }
            toggleClipboardFilter()
            return .handled
        }
        // ⇧⌘F mirrors the Add/Remove Favorites row, closing an open menu the way that row does.
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command), press.modifiers.contains(.shift),
                ASCIIKeyboardLayout.matches(press.key, character: "f"),
                !isCollapsed, let launcher = screen as? LauncherScreen
            else { return .ignored }
            guard launcher.toggleFavorite(at: selection(in: launcher)) else { return .ignored }
            if menuOpen { closeMenus() }
            return .handled
        }
        // Both cases, Shift uppercasing the key; the compact bar shows no target.
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.control), press.modifiers.contains(.shift),
                ASCIIKeyboardLayout.matches(press.key, character: "q"),
                !isCollapsed, let launcher = screen as? LauncherScreen
            else { return .ignored }
            return launcher.quit(at: selection(in: launcher)) ? .handled : .ignored
        }
        // ⌘R mirrors the Restart Application row, on the same guard and the same compact-bar skip.
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command),
                ASCIIKeyboardLayout.matches(press.key, character: "r"), !isCollapsed,
                let launcher = screen as? LauncherScreen
            else { return .ignored }
            return launcher.restart(at: selection(in: launcher)) ? .handled : .ignored
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
                Button(action: navigateBack) {
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
            // One structural position: a field inside a branch loses first responder when it flips.
            searchField.frame(width: headerAccessory.map(searchFieldWidth))
            if let accessory = headerAccessory {
                accessory.view
                Spacer(minLength: 0)
            }
            if tabOpensChat {
                headerGutter(width: Theme.Spacing.md)
                aiChatTabHint
            }
            // Keyed off the mode, which says which screen is up; the field just flexes narrower.
            if !isCollapsed, vm.mode == .clipboard {
                headerGutter(width: Theme.Spacing.md)
                ClipboardFilterButton(
                    filter: vm.clipboardFilter, isOpen: openMenu == .clipboardFilter,
                    action: toggleClipboardFilter)
            }
            if !isCollapsed, vm.mode == .ai {
                headerGutter(width: Theme.Spacing.md)
                AIModelButton(
                    title: core.aiChatCoordinator.selectedModelTitle,
                    icon: core.aiChatCoordinator.selectedModelIcon,
                    isOpen: openMenu == .aiModel,
                    action: toggleAIModel)
            }
            // Compact pins favorites beside the field; expanded shows them as rows.
            if isCollapsed, settings.showFavoritesInCompactMode,
                let launcher = screen as? LauncherScreen
            {
                let favorites = launcher.compactFavorites
                if !favorites.isEmpty {
                    headerGutter(width: Theme.Spacing.md)
                    CompactFavoritesRow(
                        favorites: favorites,
                        showsOverflow: launcher.hasUnshownFavorites,
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

    /// Only the expanded launcher offers them: a sub-screen owns its own search bar.
    private var headerAccessory: PaletteHeaderAccessory? {
        guard vm.mode == .launcher || vm.mode == .ai, !isCollapsed else { return nil }
        let screen = screen
        return screen.headerAccessory(at: selection(in: screen), focus: $argumentFocused)
    }

    /// Nothing else advertises Tab, so the launcher says where it goes.
    private var aiChatTabHint: some View {
        BarButton(chrome: .rounded, action: cycleMode) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("AI Chat")
                    .font(Theme.Typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
                KeyCapChip(text: "⇥", style: .outline)
            }
        }
        .help("Ask AI Chat what you typed  ⇥")
    }

    /// Resolved through `PaletteTabAction`, so the hint cannot promise the wrong destination.
    private var tabOpensChat: Bool {
        guard !isCollapsed, headerAccessory?.fieldNames.isEmpty ?? true else { return false }
        return PaletteTabAction.resolve(mode: vm.mode, aiEnabled: settings.aiEnabled) == .ask
    }

    /// The typed text's width, floored for the caret and capped so the strip stays on screen.
    private func searchFieldWidth(for accessory: PaletteHeaderAccessory) -> CGFloat {
        let font = Theme.Typography.searchFieldNSFont
        let typed = (vm.query as NSString).size(withAttributes: [.font: font]).width
        let chrome = Theme.Size.headerIconSlot + Theme.Spacing.md * 4
        // +3pt so the caret sits after the last glyph rather than on top of it.
        return min(
            max(typed + 3, 18), max(Theme.Size.panelWidth - accessory.width - chrome, 60))
    }

    /// In the argument form the field is that argument's input, so it names the argument.
    private var searchPrompt: String {
        // The field is only wide enough for the caret while argument fields are beside it.
        if headerAccessory != nil, vm.mode != .ai { return "" }
        if vm.mode == .quicklinkArguments { return quicklinkArguments.prompt }
        if vm.mode == .customCommandArguments {
            return customCommandArguments.prompt ?? vm.mode.placeholder
        }
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
            .tint(Theme.Colors.textPrimary)
            .focused($searchFocused)
            // Fills the row's height, so there's no gap above it for topDragStrip to meet.
            .frame(maxHeight: .infinity)
            .background(alignment: .leading) {
                // An IME's marked text leaves `query` empty, so the placeholder would overlap it.
                if vm.query.isEmpty, !vm.isComposing {
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
            if openMenu == .app { closeMenus() } else { open(.app, highlighting: 0) }
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
        open(.actions, highlighting: 0)
    }

    private func toggleActions() {
        if openMenu == .actions {
            closeMenus()
        } else {
            openActions()
        }
    }

    /// Opens on the active filter, so the current value is the highlighted row like a pop-up's.
    private func toggleClipboardFilter() {
        if openMenu == .clipboardFilter {
            closeMenus()
            return
        }
        let active = ClipboardFilter.allCases.firstIndex(of: vm.clipboardFilter) ?? 0
        open(.clipboardFilter, highlighting: active)
    }

    /// Opens on the selected model, mirroring the clipboard filter's active-row behavior.
    private func toggleAIModel() {
        if openMenu == .aiModel {
            closeMenus()
            return
        }
        core.aiChatCoordinator.prepareModelSwitcher()
        let options = core.aiChatCoordinator.modelOptions
        let selected = core.aiSettings.defaultModel
        let active =
            selected.flatMap { selected in
                options.firstIndex(where: { $0.matches(selected) })
            } ?? 0
        open(.aiModel, highlighting: active)
    }

    private var headerMenuWidth: CGFloat {
        openMenu == .aiModel ? Theme.Size.menuWidth : Theme.Size.clipboardFilterMenuWidth
    }

    /// Every open path lands here, so the highlight is always stated rather than left behind.
    private func open(_ menu: OpenMenu, highlighting row: Int) {
        menuSelection = row
        openMenu = menu
    }

    private func closeMenus() {
        openMenu = nil
    }

    /// Drives the menu's window from the two pieces of state that decide what it shows.
    private func syncMenuPanel(presenting: Bool) {
        guard let content = menuContent, let corner = menuCorner else {
            menuPanel.hide()
            return
        }
        let view = AnyView(content.view())
        if presenting, let hostWindow {
            menuPanel.show(view, corner: corner, parent: hostWindow, core: core)
        } else {
            menuPanel.update(view, corner: corner, core: core)
        }
    }

    private var menuCorner: MenuPanelController.Corner? {
        switch openMenu {
        case .app: .bottomLeading
        case .actions: .bottomTrailing
        case .clipboardFilter, .aiModel: .belowHeaderTrailing
        case nil: nil
        }
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

    /// Claimed whole on the launcher, so a press at an end cannot fall through to the caret.
    private func moveFavorite(_ delta: Int, modifiers: EventModifiers) -> KeyPress.Result? {
        guard modifiers.contains(.command), modifiers.contains(.option), !isCollapsed,
            let launcher = screen as? LauncherScreen
        else { return nil }
        if launcher.moveFavorite(delta, at: selection(in: launcher)), menuOpen { closeMenus() }
        return .handled
    }

    /// Move the open menu's highlight, clamped at the ends (no wrap — consistent with `move`).
    private func moveMenu(_ delta: Int) {
        guard let content = menuContent, content.rowCount > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), content.rowCount - 1)
    }

    /// The one activation path for a menu row: run its action, then close.
    private func activateMenuItem(_ index: Int) {
        guard let content = menuContent, (0..<content.rowCount).contains(index) else { return }
        content.activate(index)
        closeMenus()
        // A mouse click on a row takes the caret with it; menus close back into the field.
        if argumentFocused == nil { searchFocused = true }
    }

    /// ⌘. — mirrors the Actions row, and works while that menu is open like the rest.
    private func pinSelection() {
        let screen = screen
        let selection = selection(in: screen)
        if let clipboard = screen as? ClipboardScreen {
            _ = clipboard.pin(at: selection)
        } else if let quicklinks = screen as? QuicklinkListScreen {
            _ = quicklinks.pin(at: selection)
        }
    }

    /// Dispatches the Cmd+number slot action to the active screen.
    private func activateFavoriteSlotShortcut() {
        guard let index = vm.favoriteSlotIndex else { return }
        if let launcher = screen as? LauncherScreen {
            _ = launcher.launchFavorite(at: index)
            return
        }
        if let clipboard = screen as? ClipboardScreen {
            _ = clipboard.activatePinned(at: index)
        }
    }

    /// Crossing chat's edge opens a fresh screen, so a draft never lands in a list.
    private func cycleMode() {
        switch PaletteTabAction.resolve(mode: vm.mode, aiEnabled: settings.aiEnabled) {
        case .carryQuery(let mode): vm.mode = mode
        case .freshScreen(let mode): vm.prepare(mode: mode)
        case .ask: core.aiChatCoordinator.ask(vm.query)
        }
    }

    /// Tab walks the inline argument fields first, then rings on when there are none.
    private func advanceTabFocus() {
        guard let accessory = headerAccessory, !accessory.fieldNames.isEmpty else {
            return cycleMode()
        }
        argumentFocused = accessory.fieldAfter(argumentFocused)
        searchFocused = argumentFocused == nil
    }

    private func navigateBack() {
        if vm.mode == .aiHistory {
            vm.prepare(mode: .ai)
        } else {
            exitToLauncher()
        }
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
        // An unfilled field blocks the launch; focus it instead of acting on a half-typed row.
        if let incomplete = headerAccessory?.firstIncompleteField {
            argumentFocused = incomplete
            searchFocused = false
            return
        }
        let screen = screen
        screen.activate(at: selection(in: screen))
    }

}

/// The palette's in-window menus. One optional of these is the whole "only one is open" invariant.
private enum OpenMenu {
    case actions
    case app
    case clipboardFilter
    case aiModel
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

/// Overflow is a button rather than a slot, so no favorite loses its digit to it.
private struct CompactFavoritesRow: View {
    let favorites: [AppEntry]
    let showsOverflow: Bool
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // Identified by the app, so a reorder moves an icon with its app, not by position.
            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, app in
                CompactFavoriteButton(help: help(for: app, at: index)) {
                    onLaunch(app)
                } content: {
                    AppIconView(app: app)
                        .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                }
            }
            if showsOverflow {
                CompactFavoriteButton(help: "Show all  ↓", action: onOverflow) {
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

    private func help(for app: AppEntry, at index: Int) -> String {
        guard let digit = FavoriteSlots.digit(at: index) else { return app.name }
        return "\(app.name)  ⌘\(digit)"
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
