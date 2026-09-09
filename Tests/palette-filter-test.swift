import Foundation

/// ⌘P opens exactly one filter, and every mode that had no filter before still has none.
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

    static func resolve(
        collapsed: Bool = false, mode: PaletteMode, accessory: Bool = false
    ) -> PaletteFilterAction {
        PaletteFilterAction.resolve(
            collapsed: collapsed, mode: mode, commandHasAccessory: accessory)
    }

    static func main() {
        expect(
            resolve(mode: .clipboard), .clipboardFilter,
            "the clipboard's type filter is what ⌘P has always opened")
        expect(
            resolve(mode: .extensionCommand, accessory: true), .extensionAccessory,
            "a running command's own dropdown answers ⌘P on its own screen")

        // The regression this guards: a command's dropdown must not let the clipboard's filter
        // open over it, and must not swallow ⌘P on a command that declared none.
        expect(
            resolve(mode: .extensionCommand, accessory: false), .ignored,
            "a command with no dropdown leaves ⌘P alone rather than opening nothing")
        expect(
            resolve(mode: .clipboard, accessory: true), .clipboardFilter,
            "off an extension screen the flag cannot reach the clipboard's own filter")

        // Every other mode was untouched by ⌘P before and has to stay that way.
        for mode in [
            PaletteMode.launcher, .ai, .aiHistory, .emoji, .fileSearch, .calculatorHistory,
            .quicklinks, .snippets, .schedule, .uninstall, .customCommandArguments
        ] {
            expect(
                resolve(mode: mode), .ignored,
                "\(mode.rawValue) has no header filter, so ⌘P stays with the field")
            expect(
                resolve(mode: mode, accessory: true), .ignored,
                "\(mode.rawValue) opens no filter even if a stale accessory flag says so")
        }

        // Collapsed there is no header to hang a button off, so neither filter may open.
        for mode in [PaletteMode.clipboard, .extensionCommand, .launcher] {
            expect(
                resolve(collapsed: true, mode: mode, accessory: true), .ignored,
                "the compact bar draws no filter button, so ⌘P opens nothing on \(mode.rawValue)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
