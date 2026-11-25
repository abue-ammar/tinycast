import Carbon.HIToolbox
import Foundation

/// One press takes exactly one step: never skip one the user can still see, never stall on one.
@main
@MainActor
struct PaletteEscapeTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteEscapeAction, _ expected: PaletteEscapeAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func expectChord(_ actual: Bool, _ expected: Bool, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func resolve(_ press: PaletteEscapePress) -> PaletteEscapeAction {
        PaletteEscapeAction.resolve(press)
    }

    static func main() {
        walkingBack()
        closingAndPoppingToRoot()
        layersAboveTheScreen()
        commandEscapeChord()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func walkingBack() {
        expect(
            resolve(PaletteEscapePress(query: "notes")), .clearQuery,
            "a typed root search clears before the palette closes")
        expect(resolve(PaletteEscapePress()), .close, "an empty root search closes the palette")
        expect(
            resolve(PaletteEscapePress(mode: .clipboard, query: "notes", canGoBack: true)), .clearQuery,
            "a typed query clears before the back step it would otherwise skip")
        expect(
            resolve(PaletteEscapePress(mode: .clipboard, canGoBack: true)), .goBack,
            "a screen opened from root search goes back to it")
        expect(
            resolve(PaletteEscapePress(mode: .clipboard)), .goBack,
            "a screen with nothing pushed under it still goes back, onto root search")
        expect(
            resolve(PaletteEscapePress(mode: .clipboard, isHotkeyRoot: true)), .closeAndPopToRoot,
            "a screen its own shortcut opened closes and resets at once")
        expect(
            resolve(PaletteEscapePress(mode: .clipboard, query: "notes", isHotkeyRoot: true)),
            .clearQuery, "a shortcut's screen still clears its typed query first")
        expect(
            resolve(PaletteEscapePress(mode: .extensionCommand, extensionCanGoBack: true)), .goBack,
            "an extension pops its own pushed view before the command is left")
        expect(
            resolve(
                PaletteEscapePress(
                    mode: .extensionCommand, isHotkeyRoot: true, extensionCanGoBack: true)),
            .goBack, "a shortcut's extension still pops its own view before closing")
        expect(
            resolve(PaletteEscapePress(mode: .extensionCommand, isHotkeyRoot: true)),
            .closeAndPopToRoot, "a shortcut's extension closes once its own stack is spent")
        expect(
            resolve(PaletteEscapePress(mode: .ai, query: "why is the sky", canGoBack: true)), .goBack,
            "a Quick AI draft is left behind rather than wiped")
        expect(
            resolve(PaletteEscapePress(mode: .ai, query: "why is the sky", isHotkeyRoot: true)),
            .closeAndPopToRoot, "Quick AI opened by its shortcut closes, draft and all")
        expect(
            resolve(PaletteEscapePress(mode: .quicklinkEditor, canGoBack: true)), .goBack,
            "an editor goes back to the screen that opened it")
        expect(
            resolve(PaletteEscapePress(mode: .quicklinkEditor, isHotkeyRoot: true)),
            .closeAndPopToRoot, "an editor its shortcut opened closes and resets")
    }

    static func closingAndPoppingToRoot() {
        let closing = EscapeKeyBehavior.closeAndPopToRoot
        expect(
            resolve(PaletteEscapePress(mode: .clipboard, query: "notes", canGoBack: true, behavior: closing)),
            .closeAndPopToRoot, "the first press closes and resets even with text typed")
        expect(
            resolve(PaletteEscapePress(query: "notes", behavior: closing)), .closeAndPopToRoot,
            "a typed root search closes and resets rather than clearing")
        expect(
            resolve(PaletteEscapePress(behavior: closing)), .close,
            "an empty root search just closes: there is nothing to reset")
        expect(
            resolve(PaletteEscapePress(mode: .extensionCommand, extensionCanGoBack: true, behavior: closing)),
            .closeAndPopToRoot, "an extension's own stack does not hold the close back")
    }

    static func layersAboveTheScreen() {
        for behavior in EscapeKeyBehavior.allCases {
            expect(
                resolve(PaletteEscapePress(query: "notes", menuQuery: "paste", behavior: behavior)),
                .clearMenuQuery, "an open menu clears its own search first")
            expect(
                resolve(
                    PaletteEscapePress(
                        mode: .ai, query: "notes", menuQuery: "", isArgumentFocused: true,
                        isAnswering: true, behavior: behavior)),
                .closeMenu, "an empty menu closes before anything beneath it")
            expect(
                resolve(
                    PaletteEscapePress(query: "search", isArgumentFocused: true, behavior: behavior)),
                .leaveArgumentField, "an argument field hands focus back before the query clears")
            expect(
                resolve(
                    PaletteEscapePress(
                        mode: .ai, query: "and then?", isAnswering: true, isHotkeyRoot: true,
                        behavior: behavior)),
                .stopAnswer, "an answer still arriving stops before Quick AI is left")
        }
    }

    // ⌘esc never reaches the responder chain, so the tap decides what counts as the chord.
    static func commandEscapeChord() {
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_Escape), flags: [.maskCommand]),
            true, "a bare ⌘esc is the root-search chord")
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_Escape), flags: []),
            false, "an unmodified Escape belongs to the palette's own handler")
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskAlternate]),
            false, "⌥⌘esc is Force Quit and must pass straight through")
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskShift]),
            false, "any further modifier spells somebody else's chord")
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_ANSI_A), flags: [.maskCommand]),
            false, "⌘A is not it")
        // Caps Lock and fn ride along on real hardware without changing which chord was struck.
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskAlphaShift, .maskSecondaryFn]),
            true, "the flags a real keyboard adds do not disqualify the chord")
    }
}
