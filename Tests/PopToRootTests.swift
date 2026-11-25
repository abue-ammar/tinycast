import Foundation

/// Only `RenderNode.arguments(from:)` reaches for the runtime, and this harness never runs JS.
enum ExtensionRuntime {
    static func jsonArray(from json: String) -> [Any] { [] }
}

/// A closed palette keeps its screen exactly as long as the close and the setting say, no longer.
@main
@MainActor
struct PopToRootTests {
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

    static func delay(_ close: PaletteClose, timeout: TimeInterval) -> TimeInterval? {
        PopToRootPolicy.delay(after: close, timeout: timeout)
    }

    static func main() {
        closesWaitTheTimeout()
        extensionOptionsAreRead()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func closesWaitTheTimeout() {
        expect(delay(.dismissed, timeout: 90) == 90, "a dismissed screen waits the full timeout")
        expect(delay(.afterAction, timeout: 90) == 15, "after an action it waits at most 15 seconds")
        expect(delay(.afterAction, timeout: 5) == 5, "a timeout shorter than that is kept as it is")
        expect(delay(.dismissed, timeout: 0) == 0, "Immediately resets at once, root search too")
        expect(delay(.afterAction, timeout: 0) == 0, "and after an action as well")
        expect(delay(.poppingToRoot, timeout: 90) == 0, "a popping close resets at once")
        expect(delay(.keepingScreen, timeout: 0) == nil, "a kept screen has no reset scheduled")
    }

    static func extensionOptionsAreRead() {
        let none = ExtensionWindowClose(options: [:])
        expect(none == .standard, "no options close the way the user's own setting says")
        let immediate = ExtensionWindowClose(
            options: ["popToRootType": .string("immediate"), "clearRootSearch": .bool(true)])
        expect(
            immediate.popToRoot == .immediate && immediate.clearsRootSearch,
            "both options are read by their API names")
        let suspended = ExtensionWindowClose(options: ["popToRootType": .string("suspended")])
        expect(suspended.popToRoot == .suspended, "a suspended close is read as one")
        let unknown = ExtensionWindowClose(options: ["popToRootType": .string("later")])
        expect(unknown.popToRoot == .default, "an unknown type falls back to the default")
    }
}
