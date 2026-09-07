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

    static func main() {
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: true, argumentFocused: false, query: "notes", mode: .launcher),
            .closeMenu,
            "an open menu closes before anything else")
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: false, argumentFocused: false, query: "notes", mode: .launcher),
            .clearQuery,
            "a typed launcher query clears before the palette hides")
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: false, argumentFocused: false, query: "notes", mode: .extensionCommand),
            .clearQuery,
            "a typed extension query clears before the extension screen exits")
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: false, argumentFocused: false, query: "", mode: .extensionCommand),
            .exitExtensionScreen,
            "an empty extension query exits the extension screen")
        expect(
            PaletteEscapeAction.resolve(menuOpen: false, argumentFocused: false, query: "", mode: .launcher),
            .hidePalette,
            "an empty launcher query hides the palette")
        // The two modes where the field is not a search field: an argument answer and a chat draft.
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: false, argumentFocused: false, query: "blue", mode: .quicklinkArguments),
            .clearQuery,
            "a half-typed argument clears before the pending quicklink is abandoned")
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: false, argumentFocused: false, query: "", mode: .quicklinkArguments),
            .hidePalette,
            "an empty argument field hides the palette, which cancels the pending quicklink")
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: false, argumentFocused: false, query: "why is the sky", mode: .ai),
            .clearQuery,
            "an unsent chat draft clears before chat itself is left")
        expect(
            PaletteEscapeAction.resolve(menuOpen: false, argumentFocused: false, query: "", mode: .ai),
            .exitToLauncher,
            "an empty composer backs chat out to the launcher rather than hiding the palette")
        expect(
            PaletteEscapeAction.resolve(menuOpen: false, argumentFocused: false, query: "", mode: .clipboard),
            .hidePalette,
            "only chat backs out; an empty clipboard filter still hides the palette")
        expect(
            PaletteEscapeAction.resolve(menuOpen: true, argumentFocused: false, query: "", mode: .ai),
            .closeMenu,
            "a menu outranks the chat screen it is drawn over")
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: true, argumentFocused: false, query: "", mode: .extensionCommand),
            .closeMenu,
            "a menu outranks the extension screen it is drawn over")
        // An inline argument field is deeper than the query that found the command.
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: false, argumentFocused: true, query: "search", mode: .launcher),
            .leaveArgumentField,
            "an argument field hands focus back before the query that found it clears")
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: false, argumentFocused: true, query: "", mode: .launcher),
            .leaveArgumentField,
            "an empty query does not let the argument field skip its own step")
        expect(
            PaletteEscapeAction.resolve(
                menuOpen: true, argumentFocused: true, query: "search", mode: .launcher),
            .closeMenu,
            "a menu still outranks the argument field beneath it")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
