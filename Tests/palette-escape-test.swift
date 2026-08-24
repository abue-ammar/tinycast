import Foundation

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
            PaletteEscapeAction.resolve(menuOpen: true, query: "notes", mode: .launcher),
            .closeMenu,
            "an open menu closes before anything else")
        expect(
            PaletteEscapeAction.resolve(menuOpen: false, query: "notes", mode: .launcher),
            .clearQuery,
            "a typed launcher query clears before the palette hides")
        expect(
            PaletteEscapeAction.resolve(menuOpen: false, query: "notes", mode: .extensionCommand),
            .clearQuery,
            "a typed extension query clears before the extension screen exits")
        expect(
            PaletteEscapeAction.resolve(menuOpen: false, query: "", mode: .extensionCommand),
            .exitExtensionScreen,
            "an empty extension query exits the extension screen")
        expect(
            PaletteEscapeAction.resolve(menuOpen: false, query: "", mode: .launcher),
            .hidePalette,
            "an empty launcher query hides the palette")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
