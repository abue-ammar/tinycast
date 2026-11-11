import AppKit
import SwiftUI

/// `UCKeyTranslate` answers a named key's keycode with a control character the ASCII test admits.
@main
@MainActor
struct ASCIILayoutTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool) {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    /// What `UCKeyTranslate` hands back for each keycode under ⌘, against SwiftUI's own spelling.
    static let namedKeys: [(name: String, key: KeyEquivalent, translated: Character)] = [
        ("↑", .upArrow, "\u{1e}"),
        ("↓", .downArrow, "\u{1f}"),
        ("←", .leftArrow, "\u{1c}"),
        ("→", .rightArrow, "\u{1d}"),
        ("⌦", .deleteForward, "\u{7f}"),
        ("⇞", .pageUp, "\u{b}"),
        ("⇟", .pageDown, "\u{c}"),
        ("↖", .home, "\u{1}"),
        ("↘", .end, "\u{4}")
    ]

    /// These four agree with SwiftUI already, and must keep resolving once the arrows are excluded.
    static let controlKeys: [(name: String, key: KeyEquivalent, translated: Character)] = [
        ("↩", .return, "\u{d}"),
        ("⌫", .delete, "\u{8}"),
        ("⇥", .tab, "\u{9}"),
        ("esc", .escape, "\u{1b}"),
        ("space", .space, " ")
    ]

    static func main() {
        print("# a named key is never recovered from the layout")
        for entry in namedKeys {
            check(
                "\(entry.name) keeps SwiftUI's key",
                ASCIIKeyboardLayout.recovered(entry.key, layoutCharacter: entry.translated)
                    == entry.key)
        }

        print("\n# a key whose control character is already SwiftUI's still resolves")
        for entry in controlKeys {
            check(
                "\(entry.name) resolves to itself",
                ASCIIKeyboardLayout.recovered(entry.key, layoutCharacter: entry.translated)
                    == entry.key)
        }

        print("\n# the recovery still does its job")
        check(
            "a non-QWERTY layout recovers the logical key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("t"), layoutCharacter: "k")
                == KeyEquivalent("k"))
        check(
            "a non-ASCII layout character falls back to SwiftUI's key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("k"), layoutCharacter: "ц")
                == KeyEquivalent("k"))
        check(
            "no layout character falls back to SwiftUI's key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("k"), layoutCharacter: nil)
                == KeyEquivalent("k"))
        check(
            "a shifted letter is still spelled lower case",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("C"), layoutCharacter: nil)
                == KeyEquivalent("c"))

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
