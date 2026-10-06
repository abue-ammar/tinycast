import AppKit
import Carbon.HIToolbox

@main
@MainActor
struct ShortcutEventTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(label)")
        }
    }

    static func main() {
        holdRelease()
        characterRelease()
        globeAndFunctionKeys()
        pauseAndTimeout()
        consumedCombosCancelModifierGestures()
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static let leftCommand = NSEvent.ModifierFlags.command.rawValue | 8
    static let rightCommand = NSEvent.ModifierFlags.command.rawValue | 16

    static func holdRelease() {
        let shortcut = KeyShortcut(carbonKeyCode: kVK_ANSI_G, carbonModifiers: cmdKey)
            .settingSide(.left, for: .command)
        var pressed = 0
        var released = 0
        let tap = ShortcutEventTap(entries: [
            .init(shortcut: shortcut, onKeyDown: { pressed += 1 }, onKeyUp: { released += 1 })
        ])
        expect(
            !tap.process(type: .keyDown, keyCode: kVK_ANSI_G, flagsRaw: UInt64(rightCommand)),
            "the opposite Command side leaves the event untouched")
        expect(pressed == 0, "the opposite side cannot start Dictation")
        expect(
            tap.process(type: .keyDown, keyCode: kVK_ANSI_G, flagsRaw: UInt64(leftCommand)),
            "the selected side consumes the key-down")
        expect(
            tap.process(type: .keyDown, keyCode: kVK_ANSI_G, flagsRaw: UInt64(leftCommand)),
            "auto-repeat stays consumed")
        expect(pressed == 1, "auto-repeat never restarts a hold")
        expect(
            tap.process(type: .keyUp, keyCode: kVK_ANSI_G, flagsRaw: 0),
            "key-up is consumed even when Command was released first")
        expect(released == 1, "the matching key-up finishes Dictation exactly once")
        expect(
            !tap.process(type: .keyUp, keyCode: kVK_ANSI_G, flagsRaw: 0),
            "an unmatched key-up is untouched")
    }

    static func characterRelease() {
        guard let character = KeyShortcut.character(for: kVK_ANSI_G, carbonModifiers: cmdKey) else {
            expect(false, "the ASCII-capable layout translates the character fixture")
            return
        }
        let shortcut = KeyShortcut(carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey)
            .usingKeyEquivalent(character)
        var pressed = 0
        var released = 0
        let tap = ShortcutEventTap(entries: [
            .init(shortcut: shortcut, onKeyDown: { pressed += 1 }, onKeyUp: { released += 1 })
        ])
        expect(
            tap.process(type: .keyDown, keyCode: kVK_ANSI_G, flagsRaw: UInt64(leftCommand)),
            "character mode follows the layout's Command table to a different physical key")
        expect(pressed == 1, "the character chord fires")
        expect(
            tap.process(type: .keyUp, keyCode: kVK_ANSI_G, flagsRaw: 0) && released == 1,
            "character mode tracks the actual pressed key for Dictation release")
    }

    static func globeAndFunctionKeys() {
        var pressed = 0
        let shortcut = KeyShortcut(carbonKeyCode: kVK_F5, carbonModifiers: cmdKey)
            .settingSide(.left, for: .command)
        let tap = ShortcutEventTap(entries: [
            .init(shortcut: shortcut, onKeyDown: { pressed += 1 })
        ])
        let flags = UInt64(leftCommand | NSEvent.ModifierFlags.function.rawValue)
        expect(
            tap.process(type: .keyDown, keyCode: kVK_F5, flagsRaw: flags),
            "F-key's synthetic fn flag is not a physical Globe press")
        _ = tap.process(type: .keyUp, keyCode: kVK_F5, flagsRaw: 0)
        _ = tap.process(type: .flagsChanged, keyCode: kVK_Function, flagsRaw: flags)
        expect(
            !tap.process(type: .keyDown, keyCode: kVK_F5, flagsRaw: flags),
            "a real extra Globe modifier prevents a Command-only chord")
        expect(pressed == 1, "the extra Globe press cannot fire another action")
    }

    static func pauseAndTimeout() {
        var pressed = 0
        var released = 0
        let shortcut = KeyShortcut(carbonKeyCode: kVK_ANSI_G, carbonModifiers: cmdKey)
            .settingSide(.left, for: .command)
        let tap = ShortcutEventTap(entries: [
            .init(shortcut: shortcut, onKeyDown: { pressed += 1 }, onKeyUp: { released += 1 })
        ])
        _ = tap.process(type: .keyDown, keyCode: kVK_ANSI_G, flagsRaw: UInt64(leftCommand))
        tap.isPaused = true
        expect(released == 1, "opening a recorder releases a detailed Dictation chord")
        expect(
            !tap.process(type: .keyDown, keyCode: kVK_ANSI_G, flagsRaw: UInt64(leftCommand)),
            "a paused engine leaves recording input untouched")
        tap.isPaused = false
        _ = tap.process(type: .keyDown, keyCode: kVK_ANSI_G, flagsRaw: UInt64(leftCommand))
        _ = tap.process(type: .tapDisabledByTimeout, keyCode: 0, flagsRaw: 0)
        expect(pressed == 2 && released == 2, "a disabled tap clears its hold without sticking")
        expect(
            !tap.process(type: .keyUp, keyCode: kVK_ANSI_G, flagsRaw: 0),
            "a cleared hold cannot deliver its release twice")
    }

    static func consumedCombosCancelModifierGestures() {
        let monitor = ModifierTapMonitor(bound: [.modifier(.leftCommand), .doubleTap(.command)])
        var triggers: [HotKeyBinding] = []
        monitor.onTrigger = { triggers.append($0) }
        let shortcut = KeyShortcut(carbonKeyCode: kVK_ANSI_G, carbonModifiers: cmdKey)
            .settingSide(.left, for: .command)
        let tap = ShortcutEventTap(entries: [
            .init(
                shortcut: shortcut,
                onKeyDown: {
                    monitor.process(isFlagsChanged: false, flagsRaw: 0, keyCode: shortcut.carbonKeyCode)
                })
        ])
        for _ in 0..<2 {
            monitor.process(isFlagsChanged: true, flagsRaw: UInt64(leftCommand), keyCode: kVK_Command)
            expect(
                tap.process(type: .keyDown, keyCode: kVK_ANSI_G, flagsRaw: UInt64(leftCommand)),
                "a detailed combo consumes its key-down before the listen-only monitor")
            monitor.process(isFlagsChanged: true, flagsRaw: 0, keyCode: kVK_Command)
            _ = tap.process(type: .keyUp, keyCode: kVK_ANSI_G, flagsRaw: 0)
        }
        expect(
            triggers.isEmpty,
            "a consumed combo cannot become a lone modifier tap or generic double tap")
        monitor.process(isFlagsChanged: true, flagsRaw: UInt64(rightCommand), keyCode: kVK_RightCommand)
        monitor.process(isFlagsChanged: true, flagsRaw: 0, keyCode: kVK_RightCommand)
        expect(triggers.isEmpty, "the opposite side still cannot trigger a sided modifier action")
    }

}
