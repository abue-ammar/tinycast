import Foundation

/// Going back has to look like never having left: same screen, same query, same row.
@main
@MainActor
struct PaletteNavigationTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// A launcher with a search typed into it, which is what a back step has to bring back.
    static func searchingLauncher() -> PaletteState {
        let vm = PaletteState()
        vm.prepare(mode: .launcher)
        vm.query = "clipboard"
        vm.selection = 3
        return vm
    }

    static func main() {
        let vm = searchingLauncher()
        expect(!vm.canGoBack, "a prepared screen is a root with nothing behind it")

        vm.push(mode: .clipboard)
        expect(vm.mode == .clipboard && vm.query.isEmpty && vm.selection == 0,
            "a pushed screen opens as fresh as a prepared one")
        expect(vm.canGoBack, "the screen it was pushed over is still there to return to")

        expect(vm.pop(), "a pushed screen has a step back")
        expect(vm.mode == .launcher && vm.query == "clipboard" && vm.selection == 3,
            "the back step restores the screen, its query and its selection")
        expect(!vm.canGoBack, "the restored screen is the root again")
        expect(!vm.pop(), "a root has nowhere left to go")
        expect(vm.mode == .launcher && vm.query == "clipboard",
            "a refused back step leaves the screen untouched")

        // A list snapped to the top would throw away the very selection being restored.
        let tokens = searchingLauncher()
        tokens.push(mode: .emoji)
        let reset = tokens.resetToken
        let follow = tokens.followToken
        expect(tokens.pop(), "the emoji screen goes back to the launcher")
        expect(tokens.resetToken == reset, "a back step does not snap the restored list to the top")
        expect(tokens.followToken != follow, "it scrolls the restored row into view instead")

        let nested = searchingLauncher()
        nested.push(mode: .ai)
        nested.query = "why is the sky blue"
        nested.push(mode: .aiHistory)
        expect(nested.pop() && nested.mode == .ai && nested.query == "why is the sky blue",
            "history returns to the chat draft it was opened over")
        expect(nested.pop() && nested.mode == .launcher && nested.query == "clipboard",
            "and chat returns to the search that found it")

        // `replace` is for a screen swapping its own contents, which is not a step of its own.
        let replaced = searchingLauncher()
        replaced.push(mode: .ai)
        replaced.replace(mode: .ai)
        expect(replaced.canGoBack, "starting a new chat keeps whatever chat was opened over")
        expect(replaced.pop() && replaced.mode == .launcher,
            "so one back step still lands on the launcher")

        let summoned = searchingLauncher()
        summoned.push(mode: .clipboard)
        summoned.prepare(mode: .emoji)
        expect(!summoned.canGoBack, "a summon is a new root, not a step onto the old stack")

        let ringed = searchingLauncher()
        ringed.push(mode: .clipboard)
        ringed.resetNavigation()
        expect(!ringed.canGoBack && ringed.mode == .clipboard,
            "crossing the Tab ring drops the stack without disturbing the screen")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
