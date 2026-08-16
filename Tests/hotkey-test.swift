import AppKit
import Carbon.HIToolbox
import Foundation

/// Drives `DoubleTapDetector` on a virtual clock, so every window boundary is exact rather than timed.
@MainActor
private struct Keyboard {
    var detector = DoubleTapDetector()
    private(set) var fired: [DoubleTapModifier] = []

    mutating func press(
        _ modifiers: Set<DoubleTapModifier>, other: Bool = false, at time: TimeInterval
    ) {
        if let modifier = detector.handle(
            .modifiers(modifiers, hasOtherModifiers: other), at: time)
        {
            fired.append(modifier)
        }
    }

    mutating func release(other: Bool = false, at time: TimeInterval) {
        press([], other: other, at: time)
    }

    mutating func otherInput(at time: TimeInterval) {
        if let modifier = detector.handle(.otherInput, at: time) { fired.append(modifier) }
    }

    mutating func tap(
        _ modifier: DoubleTapModifier, at time: TimeInterval, hold: TimeInterval = 0.05
    ) {
        press([modifier], at: time)
        release(at: time + hold)
    }
}

@main
@MainActor
struct DoubleTapDetectorTests {
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

    static func expect(_ fired: [DoubleTapModifier], _ expected: [DoubleTapModifier], _ m: String) {
        expect(fired == expected, "\(m) — fired \(fired.map(\.rawValue)), want \(expected.map(\.rawValue))")
    }

    static func main() {
        modifierGlyphs()
        commandActions()
        hyperChord()
        hyperRetargeting()
        firing()
        timing()
        chords()
        interruptions()
        repeats()
        resetting()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Model

    static func modifierGlyphs() {
        expect(DoubleTapModifier.allCases.count == 4, "exactly four modifiers are eligible")
        expect(
            Set(DoubleTapModifier.allCases.map(\.glyph)) == ["⌃", "⌥", "⇧", "⌘"],
            "the glyphs are the four macOS modifier symbols")
        expect(
            DoubleTapModifier.allCases.allSatisfy { $0.keycaps == [$0.glyph, $0.glyph] },
            "a double-tap renders as its glyph twice")
        expect(
            DoubleTapModifier.allCases.map(\.rawValue)
                == ["control", "option", "shift", "command"],
            "raw values are the persisted spelling and stay in canonical ⌃⌥⇧⌘ order")
    }

    // MARK: - Built-in command mappings

    static func commandActions() {
        let expected: [(CommandID, HotKeyAction, String)] = [
            (.clipboardHistory, .toggleClipboard, "hotkey.toggleClipboard"),
            (.searchEmoji, .toggleEmoji, "hotkey.toggleEmoji"),
            (.searchFiles, .searchFiles, "hotkey.searchFiles"),
            (.showNotes, .showNotes, "hotkey.showNotes"),
            (.createNote, .createNote, "hotkey.createNote"),
            (.searchNotes, .searchNotes, "hotkey.searchNotes")
        ]
        let answers = CommandID.allCases.compactMap { id in id.hotKeyAction.map { (id, $0) } }
        expect(
            answers.count == expected.count,
            "exactly the bindable commands answer — got \(answers.map(\.0.name))")
        for (id, action, key) in expected {
            expect(
                id.hotKeyAction == action && action.defaultsKey == key,
                "\(id.name) maps to \(key)")
        }
        expect(
            Set(HotKeyAction.builtInActions)
                .isSuperset(of: Set(CommandID.allCases.compactMap(\.hotKeyAction))),
            "every bindable command appears among the built-in hotkey actions")
    }

    // MARK: - The Hyper chord

    /// A combo on the G key, spelled in Carbon like the on-disk shape.
    private static func combo(_ flags: NSEvent.ModifierFlags) -> KeyShortcut {
        KeyShortcut(
            carbonKeyCode: kVK_ANSI_G, carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
    }

    private static func caps(_ flags: NSEvent.ModifierFlags, includesShift: Bool?) -> [String] {
        KeyShortcut.collapsedModifierSymbols(
            from: flags,
            hyperChord: includesShift.map { KeyShortcut.hyperChord(includesShift: $0) })
    }

    static func hyperChord() {
        expect(
            KeyShortcut.hyperChord(includesShift: false) == [.control, .option, .command],
            "Hyper without Include Shift is exactly ⌃⌥⌘")
        expect(
            KeyShortcut.hyperChord(includesShift: true) == [.control, .option, .shift, .command],
            "Include Shift adds ⇧ and nothing else")

        for includesShift in [false, true] {
            let chord = KeyShortcut.hyperChord(includesShift: includesShift)
            expect(
                caps(chord, includesShift: includesShift) == ["✦"],
                "the chord itself collapses to a lone ✦ (shift \(includesShift))")
            expect(
                caps(chord.union(.capsLock), includesShift: includesShift) == ["✦"],
                "a stray non-shortcut flag doesn't defeat the collapse (shift \(includesShift))")
            expect(
                caps(chord, includesShift: nil) == KeyShortcut.modifierSymbols(from: chord),
                "with no Hyper key configured the chord renders literally (shift \(includesShift))")
        }

        // ⌃⌥⌘ is a subset of ⌃⌥⇧⌘, so only the shift-off chord can collapse under the wider set.
        expect(
            caps([.control, .option, .command], includesShift: true) == ["⌃", "⌥", "⌘"],
            "the narrower chord doesn't collapse while Include Shift is on")
        expect(
            caps([.control, .option, .shift, .command], includesShift: false) == ["✦", "⇧"],
            "an extra modifier trails ✦ in canonical order")
        expect(
            caps([.command, .shift], includesShift: false) == ["⇧", "⌘"],
            "an ordinary combo is untouched, and stays in ⌃⌥⇧⌘ order rather than press order")

        expect(
            KeyShortcut(
                keyCode: kVK_ANSI_G,
                modifierFlags: KeyShortcut.hyperChord(
                    includesShift: true))?.carbonModifiers
                == combo([.control, .option, .shift, .command]).carbonModifiers,
            "recording while Hyper is held captures exactly the chord")
    }

    static func hyperRetargeting() {
        let narrow = combo([.control, .option, .command])
        let wide = combo([.control, .option, .shift, .command])

        expect(narrow.retargetingHyper(includesShift: true) == wide, "⌃⌥⌘G follows ⇧ going on")
        expect(wide.retargetingHyper(includesShift: false) == narrow, "⌃⌥⇧⌘G follows ⇧ going off")
        expect(
            narrow.retargetingHyper(includesShift: true).retargetingHyper(includesShift: false)
                == narrow,
            "the chord round-trips across a flip and back")
        for includesShift in [false, true] {
            let target = includesShift ? wide : narrow
            expect(
                target.retargetingHyper(includesShift: includesShift) == target,
                "retargeting is idempotent, so an import can't corrupt a matching chord")
        }

        expect(
            narrow.retargetingHyper(includesShift: true).carbonKeyCode == kVK_ANSI_G,
            "only the modifiers move; the key is preserved")
        expect(
            combo([.control, .option, .command, .capsLock]).retargetingHyper(includesShift: true)
                == wide,
            "the masking initializer keeps a stray flag out of the retargeted chord")

        // Anything that isn't the other chord is left exactly as recorded.
        for flags in [[.command, .shift], [.option], [.control, .option], []]
            as [NSEvent
            .ModifierFlags]
        {
            let shortcut = combo(flags)
            for includesShift in [false, true] {
                expect(
                    shortcut.retargetingHyper(includesShift: includesShift) == shortcut,
                    "\(KeyShortcut.modifierSymbols(from: flags).joined()) is not a Hyper chord")
            }
        }
    }

    // MARK: - Firing

    static func firing() {
        for modifier in DoubleTapModifier.allCases {
            var keyboard = Keyboard()
            keyboard.tap(modifier, at: 0)
            expect(keyboard.fired, [], "\(modifier.rawValue): one tap alone doesn't fire")
            keyboard.tap(modifier, at: 0.15)
            expect(keyboard.fired, [modifier], "\(modifier.rawValue): a clean double-tap fires")
        }

        // Firing is on the second release, not the second press.
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.press([.command], at: 0.15)
        expect(keyboard.fired, [], "the second press alone doesn't fire")
        keyboard.release(at: 0.20)
        expect(keyboard.fired, [.command], "the second release fires")
    }

    // MARK: - Timing

    static func timing() {
        var slowFirst = Keyboard()
        slowFirst.tap(.command, at: 0, hold: DoubleTapDetector.maxHold + 0.01)
        slowFirst.tap(.command, at: 0.5)
        expect(slowFirst.fired, [], "a held first press isn't a tap")

        var slowSecond = Keyboard()
        slowSecond.tap(.command, at: 0)
        slowSecond.tap(.command, at: 0.10, hold: DoubleTapDetector.maxHold + 0.01)
        expect(slowSecond.fired, [], "a held second press isn't a tap")

        var lateGap = Keyboard()
        lateGap.tap(.command, at: 0, hold: 0.05)
        lateGap.tap(.command, at: 0.05 + DoubleTapDetector.maxGap + 0.01)
        expect(lateGap.fired, [], "a second tap after the gap doesn't fire")

        // Just inside both windows: the slowest double-tap that still counts.
        let epsilon = 0.001
        var atLimit = Keyboard()
        atLimit.tap(.command, at: 0, hold: DoubleTapDetector.maxHold - epsilon)
        atLimit.tap(
            .command, at: DoubleTapDetector.maxHold + DoubleTapDetector.maxGap - 2 * epsilon,
            hold: DoubleTapDetector.maxHold - epsilon)
        expect(atLimit.fired, [.command], "the slowest qualifying double-tap still fires")

        // A late second tap becomes the new first tap rather than being discarded.
        var rolling = Keyboard()
        rolling.tap(.command, at: 0)
        rolling.tap(.command, at: 1.0)
        expect(rolling.fired, [], "the late tap doesn't fire")
        rolling.tap(.command, at: 1.15)
        expect(rolling.fired, [.command], "but it seeds the next pair")
    }

    // MARK: - Chords

    static func chords() {
        var joined = Keyboard()
        joined.tap(.command, at: 0)
        joined.press([.command], at: 0.15)
        joined.press([.command, .shift], at: 0.17)
        joined.press([.command], at: 0.19)
        joined.release(at: 0.21)
        expect(joined.fired, [], "a chord unwinding back to one modifier isn't a tap")

        var chorded = Keyboard()
        chorded.press([.command, .shift], at: 0)
        chorded.release(at: 0.05)
        chorded.press([.command, .shift], at: 0.10)
        chorded.release(at: 0.15)
        expect(chorded.fired, [], "double-tapping a two-modifier chord doesn't fire")

        var mixed = Keyboard()
        mixed.tap(.command, at: 0)
        mixed.tap(.shift, at: 0.15)
        expect(mixed.fired, [], "two different modifiers aren't a double-tap")
        mixed.tap(.shift, at: 0.30)
        expect(mixed.fired, [.shift], "but the second one starts its own pair")

        var withFn = Keyboard()
        withFn.press([.command], other: true, at: 0)
        withFn.release(other: true, at: 0.05)
        withFn.press([.command], other: true, at: 0.10)
        withFn.release(other: true, at: 0.15)
        // Only momentary keys may map to `hasOtherModifiers`: a latched bit (Caps Lock's `maskAlphaShift`) would disqualify every press for as long as it stays set, exactly as fn does here.
        expect(withFn.fired, [], "fn held alongside disqualifies the press")

        // The poison clears once the extra modifier is gone.
        var recovered = Keyboard()
        recovered.press([.command], other: true, at: 0)
        recovered.release(at: 0.05)
        recovered.tap(.command, at: 0.10)
        recovered.tap(.command, at: 0.25)
        expect(recovered.fired, [.command], "a clean pair after the poisoned one still fires")
    }

    // MARK: - Interruptions

    static func interruptions() {
        var typed = Keyboard()
        typed.tap(.command, at: 0)
        typed.otherInput(at: 0.08)
        typed.tap(.command, at: 0.15)
        expect(typed.fired, [], "a key press between taps cancels the pair")

        var shortcut = Keyboard()
        shortcut.press([.command], at: 0)
        shortcut.otherInput(at: 0.02)
        shortcut.release(at: 0.05)
        shortcut.tap(.command, at: 0.10)
        expect(shortcut.fired, [], "⌘K then ⌘ isn't a double-tap")

        var clicked = Keyboard()
        clicked.tap(.option, at: 0)
        clicked.otherInput(at: 0.10)
        clicked.tap(.option, at: 0.14)
        expect(clicked.fired, [], "a click between taps cancels the pair")
    }

    // MARK: - Repeats

    static func repeats() {
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.tap(.command, at: 0.15)
        expect(keyboard.fired, [.command], "the pair fires")
        keyboard.tap(.command, at: 0.30)
        expect(keyboard.fired, [.command], "a triple-tap doesn't fire twice")
        keyboard.tap(.command, at: 0.45)
        expect(keyboard.fired, [.command, .command], "the next full pair fires again")
    }

    // MARK: - Reset

    static func resetting() {
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.detector.reset()
        keyboard.tap(.command, at: 0.15)
        expect(keyboard.fired, [], "reset drops the pending tap")

        // Reset also forgets held modifiers, so the next press still reads as a clean start.
        var stuck = Keyboard()
        stuck.press([.command], at: 0)
        stuck.detector.reset()
        stuck.tap(.command, at: 0.10)
        stuck.tap(.command, at: 0.25)
        expect(stuck.fired, [.command], "reset clears a half-held press")
    }
}
