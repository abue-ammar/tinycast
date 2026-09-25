import Foundation

/// Every row chord resolves to exactly the shortcut the old per-chord handlers answered.
@main
@MainActor
struct PaletteShortcutTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteShortcut?, _ expected: PaletteShortcut?, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            let got = String(describing: actual)
            print("FAIL: \(message) — got \(got), want \(String(describing: expected))")
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func resolve(
        _ key: Character?, command: Bool = false, shift: Bool = false, option: Bool = false,
        control: Bool = false, delete: Bool = false
    ) -> PaletteShortcut? {
        PaletteShortcut.resolve(
            command: command, shift: shift, option: option, control: control, isDeleteKey: delete,
            matches: { $0 == key })
    }

    static func main() {
        expect(resolve(nil, command: true, delete: true), .commandDelete, "⌘⌫ deletes the row")
        expect(resolve(nil, delete: true), nil, "a bare backspace stays with the field")
        expect(resolve(nil, control: true, delete: true), nil, "⌃⌫ is no row chord")

        expect(resolve("c", command: true, shift: true), .copyFile, "⇧⌘C copies the file")
        expect(resolve("c", command: true, option: true), .copyName, "⌥⌘C copies the name")
        expect(resolve("c", command: true, control: true), .copyPath, "⌃⌘C copies the path")
        expect(resolve("c", command: true), nil, "bare ⌘C stays with the search field")
        expect(
            resolve("c", command: true, shift: true, option: true, control: true), .copyFile,
            "Shift is read first when several second modifiers are held")
        expect(
            resolve("c", command: true, option: true, control: true), .copyName,
            "Option is read before Control")

        expect(resolve("v", command: true, shift: true), .pasteFile, "⇧⌘V pastes the file")
        expect(resolve("v", command: true), nil, "bare ⌘V stays with the search field")
        expect(resolve("t", command: true, shift: true), .copyText, "⇧⌘T copies an image's text")
        expect(resolve("t", command: true), nil, "bare ⌘T stays with the search field")
        expect(
            resolve("t", command: true, shift: true, option: true), .copyText,
            "an extra Option still reads ⇧⌘T")
        expect(resolve("y", command: true), .quickLook, "⌘Y toggles Quick Look")
        expect(resolve("y", command: true, shift: true), .quickLook, "an extra Shift still reads ⌘Y")

        expect(resolve("x", control: true), .delete, "⌃X deletes the row")
        expect(resolve("x", shift: true, control: true), .deleteAll, "⌃⇧X deletes everything")
        expect(resolve("x", command: true, control: true), .delete, "an extra ⌘ still reads ⌃X")
        expect(resolve("x", command: true), nil, "⌘X stays with the search field")

        expect(resolve("f", command: true, shift: true), .toggleFavorite, "⇧⌘F toggles a favorite")
        expect(
            resolve("f", command: true, shift: true, control: true), .toggleFavorite,
            "an extra Control still reads ⇧⌘F")
        expect(resolve("f", command: true), nil, "⌘F is not the favorite chord")
        expect(resolve("h", command: true, shift: true), .hideFromSearch, "⇧⌘H hides the row")
        expect(resolve("h", command: true), nil, "⌘H is not the hide chord")
        expect(resolve("q", shift: true, control: true), .quit, "⌃⇧Q quits the app")
        expect(resolve("q", control: true), nil, "⌃Q is not the quit chord")
        expect(resolve("r", command: true), .restart, "⌘R restarts the app")
        expect(resolve("r", command: true, shift: true), .restart, "an extra Shift still reads ⌘R")

        expect(resolve("j", command: true), .continueInChat, "⌘J continues Quick AI in AI Chat")
        expect(resolve("n", command: true), .newItem, "⌘N starts a new one")
        expect(resolve("n", command: true, shift: true), nil, "⇧⌘N is not the new-item chord")
        expect(resolve(",", command: true, option: true), .settings, "⌥⌘, opens the screen's settings")
        expect(resolve(",", command: true), nil, "⌘, stays the app's own Settings")

        expect(resolve("k", command: true), nil, "⌘K belongs to the Actions menu")
        expect(resolve("p", command: true), nil, "⌘P belongs to the header filter")
        expect(resolve("a"), nil, "typing is never a chord")

        let expanded: [PaletteShortcut] = [
            .copyFile, .copyName, .copyPath, .copyText, .pasteFile, .quickLook, .toggleFavorite,
            .hideFromSearch, .quit, .restart
        ]
        let anywhere: [PaletteShortcut] = [
            .commandDelete, .delete, .deleteAll, .pin, .favoriteSlot(0), .continueInChat, .newItem,
            .settings
        ]
        for shortcut in expanded {
            expect(shortcut.requiresExpanded, "\(shortcut) is skipped in the compact bar")
        }
        for shortcut in anywhere {
            expect(!shortcut.requiresExpanded, "\(shortcut) also acts in the compact bar")
        }

        let closing: [PaletteShortcut] = [
            .delete, .deleteAll, .copyFile, .copyName, .copyPath, .copyText, .quickLook,
            .toggleFavorite, .hideFromSearch, .newItem, .settings
        ]
        let leaving: [PaletteShortcut] = [
            .commandDelete, .pasteFile, .quit, .restart, .pin, .favoriteSlot(0), .continueInChat
        ]
        for shortcut in closing {
            expect(shortcut.closesMenu, "\(shortcut) closes an open menu")
        }
        for shortcut in leaving {
            expect(!shortcut.closesMenu, "\(shortcut) leaves an open menu as it is")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
