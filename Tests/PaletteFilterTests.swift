import Foundation

/// ⌘P targets only the current screen's header menu.
@main
@MainActor
struct PaletteFilterTests {
    static var failures = 0
    static var passes = 0

    static func expect(
        _ actual: PaletteFilterAction, _ expected: PaletteFilterAction, _ message: String
    ) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func resolve(collapsed: Bool = false, mode: PaletteMode) -> PaletteFilterAction {
        PaletteFilterAction.resolve(collapsed: collapsed, mode: mode)
    }

    static func main() {
        expect(
            resolve(mode: .clipboard), .clipboardFilter,
            "the clipboard's type filter is what ⌘P has always opened")
        expect(
            resolve(mode: .fileSearch), .fileSearchFilter,
            "file search has a header filter of its own")
        expect(
            resolve(mode: .emoji), .emojiCategory,
            "the emoji picker exposes its category selector through ⌘P")
        expect(
            resolve(mode: .dictionary), .dictionaryScope,
            "the dictionary screen switches between dictionary and thesaurus through ⌘P")
        expect(
            resolve(mode: .ai), .aiModel,
            "Quick AI opens its model selector through ⌘P")

        // Every other mode was untouched by ⌘P before and has to stay that way.
        for mode in [
            PaletteMode.launcher, .aiHistory, .calculatorHistory,
            .quicklinks, .snippets, .schedule, .uninstall
        ] {
            expect(
                resolve(mode: mode), .ignored,
                "\(mode.rawValue) has no header filter, so ⌘P stays with the field")
        }

        // Collapsed there is no header to hang a button off, so no filter may open.
        for mode in [PaletteMode.clipboard, .fileSearch, .emoji, .ai, .launcher] {
            expect(
                resolve(collapsed: true, mode: mode), .ignored,
                "the compact bar draws no filter button, so ⌘P opens nothing on \(mode.rawValue)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
