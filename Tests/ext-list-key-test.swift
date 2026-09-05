import SwiftUI

/// The rules a control that drops a list applies to a key press. Split from the view so the case
/// that broke in the app — ⌫ never reaching the query — is checked here rather than by hand.
enum ExtensionListKeyTests {
    static func run(check: (String, Bool, String?) -> Void) {
        print("\n# list keys, closed")
        check(
            "↓ opens the list",
            resolve(.downArrow, listOpen: false) == .openList, nil)
        check(
            "↵ submits the form rather than opening the list",
            resolve(.return, listOpen: false) == .submitForm, nil)
        check(
            "space opens the list",
            resolve(.space, characters: " ", listOpen: false) == .openList, nil)
        check(
            "← steps the value back",
            resolve(.leftArrow, listOpen: false) == .stepValue(-1), nil)
        check(
            "→ steps the value on",
            resolve(.rightArrow, listOpen: false) == .stepValue(1), nil)
        check(
            "↑ does nothing, so the form keeps it",
            resolve(.upArrow, listOpen: false) == .ignored, nil)
        check(
            "⎋ does nothing, so the screen keeps it",
            resolve(.escape, listOpen: false) == .ignored, nil)
        check(
            "⌫ does nothing, so the palette keeps it",
            resolve(.delete, characters: "\u{8}", listOpen: false) == .ignored, nil)
        check(
            "a letter does nothing until the list is open",
            resolve(KeyEquivalent("a"), characters: "a", listOpen: false) == .ignored, nil)

        print("\n# list keys, open")
        check("↑ moves up", resolve(.upArrow) == .moveUp, nil)
        check("↓ moves down", resolve(.downArrow) == .moveDown, nil)
        check("↵ commits", resolve(.return) == .commit, nil)
        check("⎋ dismisses", resolve(.escape) == .dismiss, nil)
        check(
            "a letter is typed into the query",
            resolve(KeyEquivalent("a"), characters: "a") == .append("a"), nil)
        check(
            "space is typed rather than reopening",
            resolve(.space, characters: " ") == .append(" "), nil)
        check(
            "the arrows belong to the list, not to the value",
            resolve(.leftArrow) == .ignored && resolve(.rightArrow) == .ignored, nil)

        print("\n# the bug this type exists for")
        // Measured from the running app: the ⌫ key arrives as U+007F, not as SwiftUI's `.delete`
        // (U+0008), so matching the named constant alone deleted nothing at all.
        let real = resolve(KeyEquivalent("\u{7F}"), characters: "\u{7F}")
        check("the ⌫ the app really sends deletes", real == .deleteBackward, describe(real))
        let named = resolve(.delete, characters: "\u{8}")
        check("and so does the named .delete", named == .deleteBackward, describe(named))
        let forward = resolve(.deleteForward, characters: "\u{7F}")
        check("⌦ deletes too", forward == .deleteBackward, describe(forward))
        check(
            "a deletion never reaches the query as text",
            real != .append("\u{7F}") && named != .append("\u{8}"), nil)

        print("\n# keys that belong to someone else")
        check(
            "⌘K is the actions panel's, not the list's",
            resolve(KeyEquivalent("k"), characters: "k", modifiers: .command) == .ignored, nil)
        check(
            "⌥↵ is the screen's",
            resolve(.return, modifiers: .option) == .ignored, nil)
        // A form is submitted from any control, so a closed picker must not swallow ↵.
        check(
            "↵ on a closed control reaches the form",
            resolve(.return, listOpen: false) == .submitForm, nil)
        check(
            "⌃N is the palette's arrow spelling",
            resolve(KeyEquivalent("n"), characters: "n", modifiers: .control) == .ignored, nil)
        check(
            "⇥ always leaves the control",
            resolve(.tab, characters: "\t") == .ignored, nil)
        check(
            "⇧ and a letter still types, since Shift only capitalises",
            resolve(KeyEquivalent("A"), characters: "A", modifiers: .shift) == .append("A"), nil)
        check(
            "a control character never becomes text",
            resolve(KeyEquivalent("\u{1}"), characters: "\u{1}") == .ignored, nil)
    }

    private static func describe(_ key: ExtensionListKey) -> String {
        String(describing: key)
    }

    private static func resolve(
        _ key: KeyEquivalent, characters: String = "", modifiers: EventModifiers = [],
        listOpen: Bool = true
    ) -> ExtensionListKey {
        ExtensionListKey.resolve(
            key: key, characters: characters, modifiers: modifiers, listOpen: listOpen)
    }
}
