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

    /// The default behaviour, where Escape is the back key.
    static func back(
        menuOpen: Bool = false, argumentFocused: Bool = false, query: String = "",
        mode: PaletteMode, canGoBack: Bool = false
    ) -> PaletteEscapeAction {
        PaletteEscapeAction.resolve(
            menuOpen: menuOpen, argumentFocused: argumentFocused, query: query, mode: mode,
            canGoBack: canGoBack, behavior: .popBackOrClose)
    }

    /// The opt-in behaviour, where Escape always closes and Backspace carries the back step.
    static func close(
        menuOpen: Bool = false, argumentFocused: Bool = false, query: String = "",
        mode: PaletteMode, canGoBack: Bool = false
    ) -> PaletteEscapeAction {
        PaletteEscapeAction.resolve(
            menuOpen: menuOpen, argumentFocused: argumentFocused, query: query, mode: mode,
            canGoBack: canGoBack, behavior: .closeAndPopToRoot)
    }

    /// Every screen Escape can land on, so a new mode cannot quietly skip the table below.
    static let screens: [PaletteMode] = [
        .launcher, .clipboard, .ai, .aiHistory, .uninstall, .extensionCommand,
        .customCommandArguments
    ]

    static func main() {
        // The inner handlers outrank navigation, under either setting.
        for mode in screens {
            expect(back(menuOpen: true, mode: mode), .closeMenu, "a menu outranks \(mode)")
            expect(close(menuOpen: true, mode: mode), .closeMenu, "a menu outranks \(mode) when closing")
            expect(
                back(menuOpen: true, query: "typed", mode: mode, canGoBack: true), .closeMenu,
                "a menu outranks even a typed query on \(mode)")
        }

        // An inline argument field is deeper than the query that found the command.
        expect(
            back(argumentFocused: true, query: "search", mode: .launcher), .leaveArgumentField,
            "an argument field hands focus back before the query that found it clears")
        expect(
            back(argumentFocused: true, mode: .launcher), .leaveArgumentField,
            "an empty query does not let the argument field skip its own step")
        expect(
            close(argumentFocused: true, mode: .launcher, canGoBack: true), .leaveArgumentField,
            "the argument field is an inner handler, so closing never outranks it")
        expect(
            back(menuOpen: true, argumentFocused: true, query: "search", mode: .launcher), .closeMenu,
            "a menu still outranks the argument field beneath it")

        // A typed field clears first, whatever is underneath and whichever setting is on.
        for mode in screens {
            for canGoBack in [false, true] {
                expect(
                    back(query: "typed", mode: mode, canGoBack: canGoBack), .clearQuery,
                    "a typed query on \(mode) clears before the screen is left")
                expect(
                    close(query: "typed", mode: mode, canGoBack: canGoBack), .clearQuery,
                    "a typed query on \(mode) clears before the palette closes")
            }
        }

        // Pop back or close: an empty field pops one screen, or closes at the bottom.
        for mode in screens where mode != .extensionCommand {
            expect(
                back(mode: mode, canGoBack: false), .hidePalette,
                "\(mode) reached by its own hotkey has nothing under it, so Escape closes")
            expect(
                back(mode: mode, canGoBack: true), .goBack,
                "\(mode) reached from another screen goes back to it")
        }

        // An extension leaves through its own coordinator, which pops its inner stack first.
        expect(
            back(mode: .extensionCommand, canGoBack: false), .exitExtensionScreen,
            "an extension screen exits through the extension, not the palette's stack")
        expect(
            back(mode: .extensionCommand, canGoBack: true), .exitExtensionScreen,
            "a row-opened extension still exits through the extension, which then pops the stack")

        // Close and pop to root: Escape stops navigating entirely, extensions included.
        for mode in screens {
            for canGoBack in [false, true] {
                expect(
                    close(mode: mode, canGoBack: canGoBack), .hidePalette,
                    "\(mode) closes rather than going back when Escape is set to close")
            }
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
