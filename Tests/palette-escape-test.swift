import Carbon.HIToolbox
import Foundation

/// One press may never skip a step the user can still see and throw work away.
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

    /// The shipped default, so a case only spells out what it is actually about.
    static func resolve(
        quickLookOpen: Bool = false, menuOpen: Bool = false, argumentFocused: Bool = false,
        query: String = "", mode: PaletteMode = .launcher, canGoBack: Bool = false,
        behavior: EscapeKeyBehavior = .navigateBackOrClose
    ) -> PaletteEscapeAction {
        PaletteEscapeAction.resolve(
            quickLookOpen: quickLookOpen, menuOpen: menuOpen, argumentFocused: argumentFocused,
            query: query, mode: mode, canGoBack: canGoBack, behavior: behavior)
    }

    static func main() {
        expect(
            resolve(quickLookOpen: true, menuOpen: true, query: "notes", mode: .fileSearch),
            .closeQuickLook,
            "the Quick Look overlay covers the screen, so it closes before the menu under it")
        expect(
            resolve(menuOpen: true, query: "notes"),
            .closeMenu,
            "an open menu closes before anything else")
        expect(
            resolve(query: "notes"),
            .clearQuery,
            "a typed launcher query clears before the palette hides")
        expect(
            resolve(query: "notes", mode: .extensionCommand),
            .clearQuery,
            "a typed extension query clears before the extension screen exits")
        expect(
            resolve(mode: .extensionCommand),
            .exitExtensionScreen,
            "an empty extension query exits the extension screen, which owns its own stack")
        expect(
            resolve(),
            .hidePalette,
            "an empty launcher query hides the palette")
        // The two surfaces where the field is not a search field: an argument answer, a chat draft.
        expect(
            resolve(query: "blue", mode: .customCommandArguments),
            .clearQuery,
            "a half-typed argument clears before the pending command is abandoned")
        expect(
            resolve(mode: .customCommandArguments),
            .hidePalette,
            "an empty argument field hides the palette, which cancels the pending command")
        expect(
            resolve(query: "why is the sky", mode: .ai),
            .clearQuery,
            "an unsent chat draft clears before chat itself is left")

        // Provenance, not the mode, decides whether there is anywhere to go back to.
        expect(
            resolve(mode: .clipboard, canGoBack: true),
            .goBack,
            "a clipboard screen opened from the root search returns to it")
        expect(
            resolve(mode: .clipboard),
            .hidePalette,
            "the same screen summoned by its own hotkey is a root, so it hides")
        expect(
            resolve(mode: .ai, canGoBack: true),
            .goBack,
            "chat is no different: reached from the root, it goes back to it")
        expect(
            resolve(mode: .ai),
            .hidePalette,
            "chat summoned by its own hotkey hides rather than falling back to the launcher")
        expect(
            resolve(query: "notes", mode: .clipboard, canGoBack: true),
            .clearQuery,
            "a typed query still clears before the back step it would otherwise skip")

        // Close and pop to root: one press ends the session, whatever it was opened over.
        expect(
            resolve(mode: .clipboard, canGoBack: true, behavior: .closeAndPopToRoot),
            .hidePalette,
            "close-and-pop-to-root hides even where a back step exists")
        expect(
            resolve(mode: .extensionCommand, canGoBack: true, behavior: .closeAndPopToRoot),
            .hidePalette,
            "close-and-pop-to-root outranks an extension's own stack too")
        expect(
            resolve(query: "notes", behavior: .closeAndPopToRoot),
            .clearQuery,
            "clearing the query is the first press under either behavior")
        expect(
            resolve(menuOpen: true, canGoBack: true, behavior: .closeAndPopToRoot),
            .closeMenu,
            "a menu outranks the behavior setting beneath it")

        expect(
            resolve(menuOpen: true, mode: .ai),
            .closeMenu,
            "a menu outranks the chat screen it is drawn over")
        expect(
            resolve(menuOpen: true, mode: .extensionCommand),
            .closeMenu,
            "a menu outranks the extension screen it is drawn over")
        // An inline argument field is deeper than the query that found the command.
        expect(
            resolve(argumentFocused: true, query: "search"),
            .leaveArgumentField,
            "an argument field hands focus back before the query that found it clears")
        expect(
            resolve(argumentFocused: true, canGoBack: true),
            .leaveArgumentField,
            "an empty query does not let the argument field skip its own step")
        expect(
            resolve(menuOpen: true, argumentFocused: true, query: "search"),
            .closeMenu,
            "a menu still outranks the argument field beneath it")

        // ⌘⎋ never reaches the responder chain, so what counts as the chord is decided in the tap.
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_Escape), flags: [.maskCommand]),
            true, "a bare ⌘⎋ is the root-search chord")
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_Escape), flags: []),
            false, "an unmodified Escape belongs to the palette's own handler")
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskAlternate]),
            false, "⌥⌘⎋ is Force Quit and must pass straight through")
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

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
