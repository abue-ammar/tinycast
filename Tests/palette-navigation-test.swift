import CoreGraphics
import Foundation

/// Going back must land on the screen the user last saw, with what they had typed still there.
@main
@MainActor
struct PaletteNavigationTests {
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

    /// A launcher part-way through a search: what every push below is expected to restore.
    static func searching() -> PaletteState {
        let state = PaletteState()
        state.prepare(mode: .launcher)
        state.query = "clipboard"
        state.selection = 3
        return state
    }

    static func main() {
        var stack = PaletteNavigationStack()
        expect(!stack.canGoBack, "a fresh stack has nothing under it")
        expect(stack.pop() == nil, "popping an empty stack yields no frame")

        let frame = PaletteFrame(
            mode: .launcher, query: "clipboard", selection: 3, clipboardFilter: .all)
        stack.push(frame)
        expect(stack.canGoBack, "a pushed frame is a screen to go back to")
        expect(stack.pop() == frame, "a popped frame is the one that was pushed")
        expect(!stack.canGoBack, "the last pop empties the stack")

        stack.push(frame)
        stack.push(PaletteFrame(mode: .ai, query: "", selection: 0, clipboardFilter: .all))
        stack.reset()
        expect(!stack.canGoBack, "reset drops every frame, however deep")

        // A summon is a root: Escape on it closes rather than going back.
        let root = searching()
        expect(!root.canGoBack, "a prepared screen is the bottom of the stack")
        expect(!root.pop(), "popping the root reports there was nowhere to go")

        // The round-trip the whole feature exists for: launcher → clipboard → back.
        let state = searching()
        state.push(mode: .clipboard)
        expect(state.mode == .clipboard, "a push lands on the new screen")
        expect(state.query.isEmpty, "a pushed screen starts with an empty field")
        expect(state.selection == 0, "a pushed screen starts at its first row")
        expect(state.canGoBack, "the screen underneath is still there")

        state.clipboardFilter = .image
        let followed = state.followToken
        expect(state.pop(), "going back from a pushed screen succeeds")
        expect(state.mode == .launcher, "back lands on the screen that was pushed over")
        expect(state.query == "clipboard", "back restores the query that was typed")
        expect(state.selection == 3, "back restores the row that was selected")
        expect(state.clipboardFilter == .all, "back restores the filter the screen had")
        expect(state.followToken != followed, "back scrolls the restored row into view")
        expect(!state.canGoBack, "the stack is empty once the last screen is restored")

        // Depth: each push is its own frame, and each pop undoes exactly one.
        let deep = searching()
        deep.push(mode: .ai)
        deep.query = "why is the sky blue"
        deep.push(mode: .aiHistory)
        expect(deep.pop(), "history goes back to the chat it was opened from")
        expect(deep.mode == .ai, "the chat is the screen under history")
        expect(deep.query == "why is the sky blue", "the unsent draft survives the round trip")
        expect(deep.pop(), "the chat goes back to the launcher under it")
        expect(deep.mode == .launcher && deep.query == "clipboard", "the launcher comes back whole")
        expect(!deep.pop(), "the launcher is the root, so the next Escape closes instead")

        // Replacing a screen is lateral: one extension command fired over another must not stack,
        // or Escape would restore a frame whose command has already been stopped.
        let lateral = searching()
        lateral.push(mode: .extensionCommand)
        lateral.replace(mode: .extensionCommand)
        expect(lateral.mode == .extensionCommand, "replace lands on the new screen")
        expect(lateral.canGoBack, "replace keeps whatever was underneath")
        expect(lateral.pop(), "one pop is enough to leave a replaced screen")
        expect(lateral.mode == .launcher, "the screen under the replaced one is the original")
        expect(!lateral.canGoBack, "replacing never added a second frame")

        // Pop to root from any depth, which is what ⌘⎋ and the timeout both do.
        let reset = searching()
        reset.push(mode: .ai)
        reset.push(mode: .aiHistory)
        reset.prepare(mode: .launcher)
        expect(!reset.canGoBack, "becoming the root drops every screen underneath")
        expect(reset.query.isEmpty, "the root search starts empty")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
