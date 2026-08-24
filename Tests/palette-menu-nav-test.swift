import Carbon.HIToolbox
import Foundation

@main
@MainActor
struct PaletteMenuNavigationTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        expect(MenuNavigation.handles(kVK_UpArrow), "up arrow is a menu-nav key")
        expect(MenuNavigation.handles(kVK_DownArrow), "down arrow is a menu-nav key")
        expect(MenuNavigation.handles(kVK_Return), "return is a menu-nav key")
        expect(MenuNavigation.handles(kVK_ANSI_KeypadEnter), "keypad enter is a menu-nav key")
        expect(MenuNavigation.handles(kVK_Escape), "escape is a menu-nav key")
        expect(MenuNavigation.handles(kVK_Tab), "tab is a menu-nav key")
        expect(MenuNavigation.handles(kVK_ANSI_J), "J is a menu-nav key")
        expect(MenuNavigation.handles(kVK_ANSI_K), "K is a menu-nav key")

        expect(!MenuNavigation.handles(kVK_ANSI_A), "plain typing stays frozen while a menu is open")
        expect(!MenuNavigation.handles(kVK_ANSI_M), "an unrelated letter is not a menu-nav key")
        expect(!MenuNavigation.handles(kVK_ANSI_X), "another unrelated letter is not a menu-nav key")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
