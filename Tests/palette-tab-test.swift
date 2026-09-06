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
            PaletteTabAction.resolve(mode: .launcher, aiEnabled: true, clipboardEnabled: true),
            .ask,
            "the launcher hands the typed text to chat as the question, not as a draft")
        expect(
            PaletteTabAction.resolve(mode: .ai, aiEnabled: true, clipboardEnabled: true),
            .freshScreen(.clipboard),
            "chat hands on to the clipboard without carrying the unsent draft into the filter")
        expect(
            PaletteTabAction.resolve(mode: .clipboard, aiEnabled: true, clipboardEnabled: true),
            .carryQuery(.launcher),
            "the clipboard closes the ring, and one search narrows both lists")

        // Off, chat has no launcher command and no hotkey; the ring must not strand a reader there.
        expect(
            PaletteTabAction.resolve(mode: .launcher, aiEnabled: false, clipboardEnabled: true),
            .carryQuery(.clipboard),
            "turned off, chat is skipped and the launcher flips straight to the clipboard")
        expect(
            PaletteTabAction.resolve(mode: .clipboard, aiEnabled: false, clipboardEnabled: true),
            .carryQuery(.launcher),
            "turned off, the clipboard still returns to the launcher")

        // A sub-screen is reached by a command or a hotkey, so Tab leaves rather than ringing on.
        for mode in [
            PaletteMode.aiHistory, .emoji, .fileSearch, .calculatorHistory, .quicklinks, .snippets
        ] {
            expect(
                PaletteTabAction.resolve(mode: mode, aiEnabled: true, clipboardEnabled: true),
                .carryQuery(.launcher),
                "\(mode.rawValue) is a sub-screen, so Tab exits to the launcher")
        }

        expect(
            PaletteTabAction.resolve(
                mode: .extensionCommand, aiEnabled: true, clipboardEnabled: true),
            .carryQuery(.launcher),
            "an extension command exits to the launcher rather than joining the ring")

        // Both stops off, so Tab has nowhere to ring on to and must leave the launcher standing.
        expect(
            PaletteTabAction.resolve(
                mode: .launcher, aiEnabled: false, clipboardEnabled: false),
            .carryQuery(.launcher),
            "with the clipboard off too, the launcher rings back onto itself")
        expect(
            PaletteTabAction.resolve(mode: .ai, aiEnabled: true, clipboardEnabled: false),
            .carryQuery(.launcher),
            "turned off, the clipboard is skipped and chat returns to the launcher")

        // Three presses from the launcher have to land back on it, or the ring is a dead end.
        var mode = PaletteMode.launcher
        var visited: [PaletteMode] = []
        for _ in 0..<3 {
            switch PaletteTabAction.resolve(mode: mode, aiEnabled: true, clipboardEnabled: true) {
            case .carryQuery(let next), .freshScreen(let next): mode = next
            // Asking opens chat, so the ring still steps onto it.
            case .ask: mode = .ai
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
            switch PaletteTabAction.resolve(
                mode: offMode, aiEnabled: false, clipboardEnabled: true)
            {
            case .carryQuery(let next), .freshScreen(let next): offMode = next
            case .ask: offMode = .ai
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
