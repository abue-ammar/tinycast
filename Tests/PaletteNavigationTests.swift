import CoreGraphics
import Foundation

/// Going back has to look like never having left: same screen, same query, same row.
@main
@MainActor
struct PaletteNavigationTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func searchingLauncher() -> PaletteState {
        let vm = PaletteState()
        vm.prepare(mode: .launcher)
        vm.query = "clipboard"
        vm.selection = 3
        return vm
    }

    static func main() {
        openingDisarmed()
        deliberateMovementArms()
        scrollingDisarms()
        driftDoesNotRearm()
        theDisarmTokenClearsLitRows()

        let vm = searchingLauncher()
        expect(!vm.canGoBack, "a prepared screen is a root with nothing behind it")

        vm.push(mode: .clipboard)
        expect(
            vm.mode == .clipboard && vm.query.isEmpty && vm.selection == 0,
            "a pushed screen opens as fresh as a prepared one")
        expect(vm.canGoBack, "the screen it was pushed over is still there to return to")

        vm.emojiCategoryFilter = .pinned
        vm.emojiGridColumnsOverride = .six

        expect(vm.pop(), "a pushed screen has a step back")
        expect(
            vm.mode == .launcher && vm.query == "clipboard" && vm.selection == 3,
            "the back step restores the screen, its query and its selection")
        expect(!vm.canGoBack, "the restored screen is the root again")
        expect(!vm.pop(), "a root has nowhere left to go")
        expect(
            vm.mode == .launcher && vm.query == "clipboard",
            "a refused back step leaves the screen untouched")

        let freshEmoji = searchingLauncher()
        freshEmoji.emojiCategoryFilter = .category(.flags)
        freshEmoji.emojiGridColumnsOverride = .ten
        freshEmoji.prepare(mode: .emoji)
        expect(
            freshEmoji.emojiCategoryFilter == .all && freshEmoji.emojiGridColumnsOverride == nil,
            "a fresh emoji screen restores all categories and the configured grid default")

        // A list snapped to the top would throw away the very selection being restored.
        let tokens = searchingLauncher()
        tokens.push(mode: .emoji)
        let reset = tokens.resetToken
        let follow = tokens.followToken
        expect(tokens.pop(), "the emoji screen goes back to the launcher")
        expect(tokens.resetToken == reset, "a back step does not snap the restored list to the top")
        expect(tokens.followToken != follow, "it scrolls the restored row into view instead")

        let nested = searchingLauncher()
        nested.push(mode: .ai)
        nested.query = "why is the sky blue"
        nested.push(mode: .aiHistory)
        expect(
            nested.pop() && nested.mode == .ai && nested.query == "why is the sky blue",
            "history returns to the chat draft it was opened over")
        expect(
            nested.pop() && nested.mode == .launcher && nested.query == "clipboard",
            "and chat returns to the search that found it")

        // `replace` is for a screen swapping its own contents, which is not a step of its own.
        let replaced = searchingLauncher()
        replaced.push(mode: .ai)
        replaced.replace(mode: .ai)
        expect(replaced.canGoBack, "starting a new chat keeps whatever chat was opened over")
        expect(
            replaced.pop() && replaced.mode == .launcher,
            "so one back step still lands on the launcher")

        let editing = searchingLauncher()
        editing.push(mode: .snippets)
        editing.query = "sign-off"
        editing.selection = 2
        editing.push(mode: .snippetEditor)
        expect(editing.query.isEmpty, "the snippet editor does not inherit the browser query")
        editing.noteEditingField(true)
        expect(
            editing.pop() && editing.mode == .snippets && editing.query == "sign-off"
                && editing.selection == 2 && editing.restoredSelection == 2 && !editing.isEditingField,
            "leaving a snippet editor restores its browser and releases the form keyboard")
        editing.query = "new search"
        expect(editing.restoredSelection == nil, "typing a new query releases the restored selection")
        expect(
            editing.pop() && editing.mode == .launcher && editing.query == "clipboard",
            "the snippet browser still returns to the launcher search")
        editing.prepare(mode: .snippets)
        expect(editing.restoredSelection == nil, "a fresh summon releases the restored selection")
        expect(vm.restoredSelection == nil, "other screens keep their existing navigation behaviour")

        let clipboard = PaletteState()
        clipboard.prepare(mode: .clipboard)
        clipboard.query = "draft"
        clipboard.clipboardFilter = .text
        clipboard.query = ""
        clipboard.clipboardFilter = .all
        clipboard.selection = 2
        clipboard.preserveSelection()
        clipboard.clipboardFilter = .all
        expect(
            clipboard.selection == 2 && clipboard.restoredSelection == 2,
            "a programmatic query and filter change keeps its chosen row through the observers")
        clipboard.clipboardFilter = .link
        expect(clipboard.restoredSelection == nil, "a new type filter releases the preserved selection")
        clipboard.selection = 1
        clipboard.preserveSelection()
        clipboard.query = "another"
        expect(clipboard.restoredSelection == nil, "a new query releases the preserved selection")

        let quicklink = searchingLauncher()
        quicklink.push(mode: .quicklinks)
        quicklink.query = "GitHub"
        quicklink.selection = 1
        quicklink.push(mode: .quicklinkEditor)
        expect(
            quicklink.mode.isNativeEditor && quicklink.query.isEmpty,
            "the quicklink editor owns its keyboard without inheriting the browser query")
        expect(
            quicklink.pop() && quicklink.mode == .quicklinks
                && quicklink.query == "GitHub" && quicklink.restoredSelection == 1,
            "leaving a quicklink editor restores its browser query and row")
        quicklink.pushCarryingQuery(mode: .launcher)
        expect(quicklink.restoredSelection == nil, "a ring hop does not carry the restored row along")
        expect(
            !PaletteMode.extensionCommand.isNativeEditor && !PaletteMode.quicklinks.isNativeEditor,
            "native editor keyboard routing excludes extensions and browsers")

        let event = searchingLauncher()
        event.query = "Create Event"
        event.push(mode: .eventEditor)
        event.noteEditingField(true)
        expect(
            event.mode.isNativeEditor && event.query.isEmpty,
            "the event editor owns its keyboard without inheriting the launcher query")
        expect(
            event.pop() && event.mode == .launcher
                && event.query == "Create Event" && event.restoredSelection == 3 && !event.isEditingField,
            "leaving an event editor restores the launcher query and selected row")
        event.prepare(mode: .eventEditor)
        expect(!event.canGoBack, "an event editor summoned by a hotkey starts without a previous screen")

        let command = searchingLauncher()
        command.query = "Create Custom Command"
        command.push(mode: .customCommandEditor)
        command.noteEditingField(true)
        expect(
            command.mode.isNativeEditor && command.query.isEmpty,
            "the command editor owns its keyboard without inheriting the launcher query")
        expect(
            command.pop() && command.mode == .launcher
                && command.query == "Create Custom Command" && command.restoredSelection == 3
                && !command.isEditingField,
            "leaving a command editor restores the launcher query and selected row")
        command.prepare(mode: .customCommandEditor)
        expect(!command.canGoBack, "a command editor summoned directly starts without a previous screen")

        let commands = searchingLauncher()
        commands.push(mode: .customCommands)
        commands.query = "Screens"
        commands.selection = 2
        commands.push(mode: .customCommandEditor)
        commands.noteEditingField(true)
        expect(
            commands.pop() && commands.mode == .customCommands
                && commands.query == "Screens" && commands.restoredSelection == 2
                && !commands.isEditingField,
            "closing a command editor restores its browser query and selection")
        expect(commands.pop() && commands.mode == .launcher, "the command browser returns to root search")

        for mode: PaletteMode in [.snippetEditor, .quicklinkEditor, .eventEditor, .customCommandEditor] {
            let switched = searchingLauncher()
            switched.push(mode: mode)
            switched.push(mode: .clipboard)
            expect(
                switched.pop() && switched.mode == .launcher && switched.query == "clipboard"
                    && !switched.canGoBack,
                "switching away from \(mode) never restores an editor without its session")
            switched.push(mode: mode)
            switched.push(mode: .quicklinkEditor)
            expect(
                switched.pop() && switched.mode == .launcher && !switched.canGoBack,
                "switching between editors preserves only the original browser")
            switched.prepare(mode: mode)
            switched.push(mode: .clipboard)
            expect(!switched.canGoBack, "a directly summoned editor leaves no dead back frame")
        }

        let summoned = searchingLauncher()
        summoned.push(mode: .clipboard)
        summoned.prepare(mode: .emoji)
        expect(!summoned.canGoBack, "a summon is a new root, not a step onto the old stack")

        let ringed = searchingLauncher()
        ringed.push(mode: .clipboard)
        ringed.resetNavigation()
        expect(
            !ringed.canGoBack && ringed.mode == .clipboard,
            "closing the Tab ring drops the stack without disturbing the screen")

        let hopped = searchingLauncher()
        hopped.pushCarryingQuery(mode: .clipboard)
        expect(
            hopped.mode == .clipboard && hopped.query == "clipboard" && hopped.selection == 3,
            "a ring hop carries the query and the row it was on")
        expect(
            hopped.pop() && hopped.mode == .launcher && hopped.query == "clipboard",
            "and the screen it crossed from is the step back")

        let chatted = searchingLauncher()
        chatted.push(mode: .ai)
        chatted.query = "why is the sky blue"
        chatted.push(mode: .clipboard)
        expect(
            chatted.pop() && chatted.mode == .ai && chatted.query == "why is the sky blue",
            "Tab out of chat leaves the draft to come back to")
        expect(
            chatted.pop() && chatted.mode == .launcher,
            "and a second step back reaches the launcher the ring started on")

        let pasted = searchingLauncher()
        pasted.query = "\nfirst pasted row,\r\nsecond pasted row\u{2028}third\n"
        expect(
            pasted.collapseQueryLineBreaks() && pasted.query == "first pasted row, second pasted row third",
            "a multi-line paste collapses to one line with no edge breaks")
        expect(
            !pasted.collapseQueryLineBreaks() && pasted.query == "first pasted row, second pasted row third",
            "a single-line query is left alone")

        rootSearchSitsUnderEveryScreen()
        backRestoresTheWholeScreen()
        aShortcutsScreenIsItsOwnRoot()
        rootSearchSurvivesWhatAsked()
        emptyingTheQueryCollapsesTheBar()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func rootSearchSitsUnderEveryScreen() {
        let deepLinked = searchingLauncher()
        deepLinked.prepare(mode: .clipboard)
        deepLinked.query = "invoice"
        deepLinked.goBack()
        expect(
            deepLinked.mode == .launcher && deepLinked.query.isEmpty && !deepLinked.canGoBack,
            "going back from a screen with nothing under it lands on an empty root search")

        let root = searchingLauncher()
        root.goBack()
        expect(
            root.mode == .launcher && root.query == "clipboard",
            "going back on root search itself changes nothing")

        let pushed = searchingLauncher()
        pushed.push(mode: .emoji)
        pushed.goBack()
        expect(
            pushed.mode == .launcher && pushed.query == "clipboard" && pushed.selection == 3,
            "going back over a pushed screen restores the search under it")
    }

    static func backRestoresTheWholeScreen() {
        let clipboard = searchingLauncher()
        clipboard.push(mode: .clipboard)
        clipboard.clipboardFilter = .text
        clipboard.push(mode: .meetingDetails)
        expect(
            clipboard.pop() && clipboard.mode == .clipboard && clipboard.clipboardFilter == .text,
            "back restores the type filter the screen was left with")

        let emoji = searchingLauncher()
        emoji.push(mode: .emoji)
        emoji.emojiCategoryFilter = .category(.flags)
        emoji.emojiGridColumnsOverride = .ten
        emoji.push(mode: .ai)
        expect(
            emoji.pop() && emoji.emojiCategoryFilter == .category(.flags)
                && emoji.emojiGridColumnsOverride == .ten,
            "back restores the emoji category and grid density")

        let files = searchingLauncher()
        files.push(mode: .fileSearch)
        files.fileSearchFilter = .folders
        files.push(mode: .clipboard)
        expect(
            files.clipboardFilter == .all && files.fileSearchFilter == .all,
            "a pushed screen still opens with every filter cleared")
        expect(files.pop() && files.fileSearchFilter == .folders, "back restores the file filter")

        let ringed = searchingLauncher()
        ringed.push(mode: .clipboard)
        ringed.clipboardFilter = .image
        ringed.pushCarryingQuery(mode: .launcher)
        expect(ringed.clipboardFilter == .all, "a ring hop does not carry a filter along")

        let browsed = searchingLauncher()
        browsed.push(mode: .clipboard)
        browsed.selection = 4
        browsed.push(mode: .ai)
        expect(
            browsed.pop() && browsed.selection == 4 && browsed.restoredSelection == nil,
            "only leaving an editor pins the restored row through the observers")
    }

    static func aShortcutsScreenIsItsOwnRoot() {
        let hotkey = searchingLauncher()
        hotkey.push(mode: .ai)
        hotkey.prepareFromHotkey(mode: .clipboard)
        expect(
            hotkey.isHotkeyRoot && !hotkey.canGoBack,
            "a shortcut's screen starts its own stack, whatever was open before")
        hotkey.push(mode: .emoji)
        expect(!hotkey.isHotkeyRoot, "a screen pushed over it is not the shortcut's own")
        expect(hotkey.pop() && hotkey.isHotkeyRoot, "back on the shortcut's screen, it is again")
        hotkey.goBack()
        expect(
            hotkey.mode == .launcher && !hotkey.isHotkeyRoot,
            "going back from it reaches root search, which no shortcut opened")

        let summoned = PaletteState()
        summoned.prepareFromHotkey(mode: .clipboard)
        summoned.prepare(mode: .clipboard)
        expect(!summoned.isHotkeyRoot, "an ordinary summon clears the shortcut's claim")

        let ringed = PaletteState()
        ringed.prepareFromHotkey(mode: .clipboard)
        ringed.resetNavigation()
        expect(!ringed.isHotkeyRoot, "closing the Tab ring clears it too")
    }

    static func rootSearchSurvivesWhatAsked() {
        let kept = searchingLauncher()
        kept.push(mode: .extensionCommand)
        kept.popToRootKeepingSearch()
        expect(
            kept.mode == .launcher && kept.query == "clipboard" && !kept.canGoBack,
            "popping to root can keep the text root search held")

        let underneath = searchingLauncher()
        underneath.push(mode: .extensionCommand)
        underneath.clearRootSearch()
        expect(underneath.mode == .extensionCommand, "clearing root search leaves the screen on top")
        expect(
            underneath.pop() && underneath.query.isEmpty && underneath.selection == 0,
            "and the root search under it comes back empty, scrolled to the top")

        let onScreen = searchingLauncher()
        onScreen.clearRootSearch()
        expect(onScreen.query.isEmpty && onScreen.selection == 0, "root search on screen clears in place")
    }

    static func emptyingTheQueryCollapsesTheBar() {
        let compact = searchingLauncher()
        compact.forceExpanded = true
        compact.query = "c"
        expect(compact.forceExpanded, "typing keeps an expanded bar expanded")
        compact.query = ""
        expect(!compact.forceExpanded, "an emptied query falls back to the compact bar")
    }

    static let rest = CGPoint(x: 400, y: 300)

    /// A palette shown with the pointer already resting over a row: disarmed, anchored there.
    static func shown() -> PaletteState {
        let state = PaletteState()
        state.disarmHoverHighlight(pointerAt: rest)
        return state
    }

    static func armed() -> PaletteState {
        let state = shown()
        state.notePointerMoved(to: CGPoint(x: rest.x + 40, y: rest.y))
        return state
    }

    static func openingDisarmed() {
        let state = shown()
        expect(!state.hoverHighlightArmed, "a palette just shown is disarmed")
        state.notePointerMoved(to: rest)
        expect(!state.hoverHighlightArmed, "a mouse-moved event that has not moved arms nothing")
        let state2 = armed()
        state2.prepare(mode: .clipboard)
        expect(!state2.hoverHighlightArmed, "switching mode disarms the highlight again")
    }

    static func deliberateMovementArms() {
        expect(armed().hoverHighlightArmed, "a pointer moved across the panel arms the highlight")

        let diagonal = shown()
        diagonal.notePointerMoved(to: CGPoint(x: rest.x + 3, y: rest.y + 3))
        expect(diagonal.hoverHighlightArmed, "movement is measured as a distance, not per axis")

        let creeping = shown()
        for step in 1...4 {
            creeping.notePointerMoved(to: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
        }
        expect(creeping.hoverHighlightArmed, "and it accumulates: the anchor holds while it moves")
    }

    static func scrollingDisarms() {
        let scrolled = armed()
        scrolled.disarmHoverHighlight(pointerAt: rest)
        expect(!scrolled.hoverHighlightArmed, "a scroll drops the highlight")

        let stillScrolling = armed()
        // Re-anchor each scroll event so pointer drift cannot accumulate into a deliberate move.
        for step in 1...20 {
            stillScrolling.disarmHoverHighlight(
                pointerAt: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
            stillScrolling.notePointerMoved(to: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
        }
        expect(
            !stillScrolling.hoverHighlightArmed,
            "a wheel nudging the mouse a point per click stays disarmed for the whole gesture")
    }

    static func driftDoesNotRearm() {
        let state = armed()
        state.disarmHoverHighlight(pointerAt: rest)
        // The mouse-moved AppKit delivers as the gesture ends carries the pointer it already had.
        state.notePointerMoved(to: rest)
        expect(!state.hoverHighlightArmed, "the gesture's own trailing mouse-moved re-arms nothing")
        state.notePointerMoved(to: CGPoint(x: rest.x + 2, y: rest.y + 1))
        expect(!state.hoverHighlightArmed, "nor does a hand resting on the mouse jogging it a point")
        state.notePointerMoved(to: CGPoint(x: rest.x + 12, y: rest.y))
        expect(state.hoverHighlightArmed, "a real move afterwards brings the highlight back")
    }

    static func theDisarmTokenClearsLitRows() {
        let state = armed()
        let token = state.hoverDisarmToken
        state.disarmHoverHighlight(pointerAt: rest)
        expect(state.hoverDisarmToken != token, "disarming bumps the token that clears lit rows")

        let quiet = state.hoverDisarmToken
        state.disarmHoverHighlight(pointerAt: rest)
        state.notePointerMoved(to: rest)
        expect(
            state.hoverDisarmToken == quiet,
            "an already-disarmed palette bumps nothing, so a scroll re-renders no rows")

        state.notePointerMoved(to: CGPoint(x: rest.x + 40, y: rest.y))
        expect(
            state.hoverDisarmToken == quiet, "and arming is silent: pointer movement never rebuilds")
    }
}
