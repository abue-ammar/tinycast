import Foundation

/// The three surfaces stay reachable one way, and chat is skipped when off.
@main
@MainActor
struct PaletteTabTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteTabAction, _ expected: PaletteTabAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func main() {
        expect(
            PaletteTabAction.resolve(mode: .launcher, aiEnabled: true),
            .freshScreen(.ai),
            "the launcher opens chat, and a search query is not seeded as a draft")
        expect(
            PaletteTabAction.resolve(mode: .ai, aiEnabled: true),
            .freshScreen(.clipboard),
            "chat hands on to the clipboard without carrying the unsent draft into the filter")
        expect(
            PaletteTabAction.resolve(mode: .clipboard, aiEnabled: true),
            .carryQuery(.launcher),
            "the clipboard closes the ring, and one search narrows both lists")

        // Off, chat has no launcher command and no hotkey; the ring must not strand a reader there.
        expect(
            PaletteTabAction.resolve(mode: .launcher, aiEnabled: false),
            .carryQuery(.clipboard),
            "turned off, chat is skipped and the launcher flips straight to the clipboard")
        expect(
            PaletteTabAction.resolve(mode: .clipboard, aiEnabled: false),
            .carryQuery(.launcher),
            "turned off, the clipboard still returns to the launcher")

        // A sub-screen is reached by a command or a hotkey, so Tab leaves rather than ringing on.
        for mode in [
            PaletteMode.aiHistory, .emoji, .fileSearch, .calculatorHistory, .quicklinks, .snippets
        ] {
            expect(
                PaletteTabAction.resolve(mode: mode, aiEnabled: true),
                .carryQuery(.launcher),
                "\(mode.rawValue) is a sub-screen, so Tab exits to the launcher")
        }

        expect(
            PaletteTabAction.resolve(mode: .extensionCommand, aiEnabled: true),
            .carryQuery(.launcher),
            "an extension command exits to the launcher rather than joining the ring")

        // Three presses from the launcher have to land back on it, or the ring is a dead end.
        var mode = PaletteMode.launcher
        var visited: [PaletteMode] = []
        for _ in 0..<3 {
            switch PaletteTabAction.resolve(mode: mode, aiEnabled: true) {
            case .carryQuery(let next), .freshScreen(let next): mode = next
            }
            visited.append(mode)
        }
        if visited == [.ai, .clipboard, .launcher] {
            passes += 1
        } else {
            failures += 1
            print("FAIL: three presses ring back to the launcher — got \(visited)")
        }

        var offMode = PaletteMode.launcher
        var offVisited: [PaletteMode] = []
        for _ in 0..<2 {
            switch PaletteTabAction.resolve(mode: offMode, aiEnabled: false) {
            case .carryQuery(let next), .freshScreen(let next): offMode = next
            }
            offVisited.append(offMode)
        }
        if offVisited == [.clipboard, .launcher] {
            passes += 1
        } else {
            failures += 1
            print("FAIL: turned off, two presses ring back to the launcher — got \(offVisited)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
