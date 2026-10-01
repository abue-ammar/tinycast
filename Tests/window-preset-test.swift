// Standalone contract tests for the window shortcut presets and what applying one changes.
import Carbon.HIToolbox
import Foundation

@main
@MainActor
struct WindowPresetTests {
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

    static func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
        .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
    }

    static func main() {
        testTables()
        testEmptyCurrent()
        testAlreadyApplied()
        testOverwrite()
        testDisplaced()
        testUnrelated()
        testMatching()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func testTables() {
        for preset in WindowShortcutPreset.allCases {
            let bindings = preset.bindings
            expect(!bindings.isEmpty, "\(preset.title) binds something")
            expect(
                Set(bindings.values).count == bindings.count,
                "\(preset.title) never gives one key to two commands")
            for (id, binding) in bindings {
                let modifiers = binding.shortcut?.carbonModifiers ?? 0
                expect(
                    modifiers & (cmdKey | optionKey | controlKey) != 0,
                    "\(preset.title) \(id) has a modifier the recorder would accept")
            }
        }
        expect(
            WindowShortcutPreset.rectangle.bindings[.leftHalf]
                == combo(kVK_LeftArrow, controlKey | optionKey),
            "Rectangle's Left Half is ⌃⌥←")
        expect(
            WindowShortcutPreset.spectacle.bindings[.restore] == combo(kVK_ANSI_Z, optionKey | cmdKey),
            "Spectacle's undo is ⌥⌘Z")
    }

    static func testEmptyCurrent() {
        let plan = WindowShortcutPresetPlan(preset: .rectangle, current: [:])
        expect(plan.assignments == WindowShortcutPreset.rectangle.bindings, "unset: every entry assigns")
        expect(plan.displaced.isEmpty, "unset: nothing displaced")
        expect(plan.overwritten.isEmpty, "unset: no confirmation")
    }

    static func testAlreadyApplied() {
        let plan = WindowShortcutPresetPlan(
            preset: .spectacle, current: WindowShortcutPreset.spectacle.bindings)
        expect(plan.assignments.isEmpty, "applied twice: nothing to assign")
        expect(plan.overwritten.isEmpty, "applied twice: no confirmation")
    }

    static func testOverwrite() {
        let preset = WindowShortcutPreset.rectangle.bindings
        let own = combo(kVK_ANSI_L, controlKey | optionKey | cmdKey)
        let current: [WindowCommand.ID: HotKeyBinding] = [
            .leftHalf: own, .rightHalf: preset[.rightHalf]!
        ]
        let plan = WindowShortcutPresetPlan(preset: .rectangle, current: current)
        expect(plan.assignments[.leftHalf] == preset[.leftHalf], "a user key is replaced")
        expect(plan.assignments[.rightHalf] == nil, "a matching key is left alone")
        expect(plan.overwritten == [.leftHalf], "only the differing user key needs confirming")
    }

    static func testDisplaced() {
        let preset = WindowShortcutPreset.spectacle.bindings
        expect(preset[.moveLeft] == nil, "fixture: Spectacle leaves Move Left unbound")
        let current: [WindowCommand.ID: HotKeyBinding] = [.moveLeft: preset[.leftHalf]!]
        let plan = WindowShortcutPresetPlan(preset: .spectacle, current: current)
        expect(plan.displaced == [.moveLeft], "a command holding a preset key is displaced")
        expect(plan.overwritten == [.moveLeft], "a displaced command needs confirming")
    }

    static func testUnrelated() {
        let current: [WindowCommand.ID: HotKeyBinding] = [
            .moveLeft: combo(kVK_ANSI_H, controlKey | optionKey | cmdKey)
        ]
        let plan = WindowShortcutPresetPlan(preset: .spectacle, current: current)
        expect(plan.displaced.isEmpty, "an unrelated key is not displaced")
        expect(plan.overwritten.isEmpty, "an unrelated key needs no confirmation")
        expect(plan.assignments[.moveLeft] == nil, "a command outside the preset is untouched")
    }

    static func testMatching() {
        let rectangle = WindowShortcutPreset.rectangle.bindings
        expect(WindowShortcutPreset.matching([:]) == nil, "nothing bound matches no preset")
        expect(WindowShortcutPreset.matching(rectangle) == .rectangle, "a full apply matches")
        var extra = rectangle
        extra[.moveLeft] = combo(kVK_ANSI_H, controlKey | optionKey | cmdKey)
        expect(WindowShortcutPreset.matching(extra) == .rectangle, "a command outside still matches")
        var edited = rectangle
        edited[.leftHalf] = combo(kVK_ANSI_L, controlKey | optionKey | cmdKey)
        expect(WindowShortcutPreset.matching(edited) == nil, "one changed key breaks the match")
        var cleared = rectangle
        cleared[.leftHalf] = nil
        expect(WindowShortcutPreset.matching(cleared) == nil, "one cleared key breaks the match")
    }
}
