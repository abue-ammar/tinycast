import Carbon.HIToolbox
import CoreGraphics
import Foundation

@main
@MainActor
struct HyperKeyEngineTests {
    static var failures = 0

    static let shift = CGEventFlags.maskShift.rawValue
    static let command = CGEventFlags.maskCommand.rawValue
    static let option = CGEventFlags.maskAlternate.rawValue

    static func check(_ name: String, _ condition: Bool) {
        if !condition { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        for key in HyperKeyPhysicalKey.allCases where key != .none {
            for includesShift in [false, true] {
                for compatible in [false, true] {
                    guard let route = key.route(secureInputCompatible: compatible) else { continue }
                    chord(route, includesShift: includesShift)
                }
            }
        }
        modifierHolds()
        shiftSides()
        unusedPresses()
        quickPressPolicy()
        interruption()
        print("Hyper Key engine: \(failures) failures")
        if failures != 0 { exit(1) }
    }

    static func chord(_ route: HyperKeyRoute, includesShift: Bool) {
        var engine = HyperKeyEngine(route: route, includesShift: includesShift)
        let context = "\(route.key) via \(route.tapKeyCode) shift=\(includesShift)"
        let held = route.modifier?.deviceMask ?? 0
        let downFlags = route.modifier == nil ? CGEventFlags.maskSecondaryFn.rawValue : held
        let type: CGEventType = route.modifier == nil ? .keyDown : .flagsChanged
        let down = engine.handle(type: type, keyCode: route.tapKeyCode, flags: downFlags, at: 0)
        if case .rewrite(let flags, let code, let changed) = down.decision {
            let expected =
                CGEventFlags([.maskCommand, .maskControl, .maskAlternate]).rawValue
                | (includesShift ? shift : 0)
            check("\(context) emits the chord", flags & 0x1F0000 == expected)
            check("\(context) uses Command transitions", code == Int64(kVK_Command) && changed)
            check("\(context) strips Caps/Fn residue", flags & 0x810000 == 0)
            if [.rightControl, .rightOption, .rightShift, .rightCommand].contains(route.modifier) {
                check("\(context) strips its own device bit", flags & held == 0)
            }
        } else {
            check("\(context) down rewrites", false)
        }
        let combo = engine.handle(type: .keyDown, keyCode: kVK_ANSI_G, flags: held, at: 0.05)
        if case .rewrite(let flags, _, _) = combo.decision {
            check("\(context) applies modifiers to keys", flags & command != 0)
        } else {
            check("\(context) combo rewrites", false)
        }
        let upType: CGEventType = route.modifier == nil ? .keyUp : .flagsChanged
        let up = engine.handle(type: upType, keyCode: route.tapKeyCode, flags: 0, at: 0.1)
        check("\(context) combo has no quick action", up.effect == nil)
        check(
            "\(context) releases modifiers",
            up.decision == .rewrite(flags: 0, keyCode: Int64(kVK_Command), asFlagsChanged: true))
        check("\(context) release resets hold", !engine.isActive)
        check(
            "\(context) ordinary typing passes",
            engine.handle(type: .keyDown, keyCode: kVK_ANSI_G, flags: 0, at: 0.2).decision == .pass)
    }

    static func modifierHolds() {
        let route = HyperKeyPhysicalKey.rightCommand.route(secureInputCompatible: false)!
        let rightCommand: UInt64 = 0x10
        var engine = HyperKeyEngine(route: route)
        check(
            "a key carrying the device bit is a chord even without a seen press",
            engine.handle(type: .keyDown, keyCode: kVK_ANSI_G, flags: command | rightCommand, at: 0)
                .decision != .pass)
        _ = engine.handle(
            type: .flagsChanged, keyCode: kVK_RightCommand, flags: command | rightCommand, at: 1)
        let leftCommand = engine.handle(
            type: .flagsChanged, keyCode: kVK_Command, flags: command | 0x8 | rightCommand, at: 1.1)
        if case .rewrite(let flags, _, _) = leftCommand.decision {
            check("the other Command keeps the chord without the Hyper key's bit", flags & rightCommand == 0)
        } else {
            check("the other Command rewrites", false)
        }
        check(
            "a key without the device bit ends a missed release",
            engine.handle(type: .keyDown, keyCode: kVK_ANSI_G, flags: 0, at: 2).decision == .pass
                && !engine.isActive)
        _ = engine.handle(
            type: .flagsChanged, keyCode: kVK_RightCommand, flags: command | rightCommand, at: 3)
        let release = engine.handle(
            type: .flagsChanged, keyCode: kVK_RightCommand, flags: option | 0x20, at: 3.1)
        check(
            "release keeps a modifier that is still held",
            release.decision
                == .rewrite(flags: option | 0x20, keyCode: Int64(kVK_Command), asFlagsChanged: true))
    }

    static func shiftSides() {
        let route = HyperKeyPhysicalKey.leftShift.route(secureInputCompatible: false)!
        let leftShift: UInt64 = 0x2
        let rightShift: UInt64 = 0x4
        var engine = HyperKeyEngine(route: route, includesShift: false)
        _ = engine.handle(type: .flagsChanged, keyCode: kVK_Shift, flags: shift | leftShift, at: 0)
        let alone = engine.handle(type: .keyDown, keyCode: kVK_ANSI_K, flags: shift | leftShift, at: 0.1)
        if case .rewrite(let flags, _, _) = alone.decision {
            check("a Shift Hyper key without Include Shift drops ⇧", flags & (shift | leftShift) == 0)
        } else {
            check("a Shift Hyper key rewrites", false)
        }
        let both = engine.handle(
            type: .keyDown, keyCode: kVK_ANSI_K, flags: shift | leftShift | rightShift, at: 0.2)
        if case .rewrite(let flags, _, _) = both.decision {
            check("the other Shift keeps ⇧", flags & shift != 0 && flags & rightShift != 0)
            check("the other Shift drops the Hyper key's bit", flags & leftShift == 0)
        } else {
            check("the other Shift rewrites", false)
        }
    }

    static func unusedPresses() {
        let route = HyperKeyPhysicalKey.capsLock.route(secureInputCompatible: false)!
        for duration in [0.01, 0.1, 0.8] {
            var engine = HyperKeyEngine(route: route)
            _ = engine.handle(type: .keyDown, keyCode: route.tapKeyCode, flags: 0, at: 0)
            let up = engine.handle(type: .keyUp, keyCode: route.tapKeyCode, flags: 0, at: duration)
            check(
                "an unused press reports its hold of \(duration)",
                up.effect == .unusedPress(heldFor: duration))
        }
        var engine = HyperKeyEngine(route: route)
        _ = engine.handle(type: .keyDown, keyCode: route.tapKeyCode, flags: 0, at: 0)
        check(
            "autorepeat is suppressed",
            engine.handle(
                type: .keyDown, keyCode: route.tapKeyCode, flags: 0, isAutorepeat: true, at: 0.5
            ).decision == .suppress)
        check(
            "autorepeat never re-arms the press",
            engine.handle(type: .keyUp, keyCode: route.tapKeyCode, flags: 0, at: 1).effect
                == .unusedPress(heldFor: 1))
        check(
            "a raw Caps Lock passes and reports the lost remap",
            engine.handle(type: .flagsChanged, keyCode: kVK_CapsLock, flags: 0x10000, at: 2)
                == HyperKeyEngine.Result(decision: .pass, effect: .unmappedCapsLock))

        let compatible = HyperKeyPhysicalKey.capsLock.route(secureInputCompatible: true)!
        var compatibleEngine = HyperKeyEngine(route: compatible)
        _ = compatibleEngine.handle(type: .flagsChanged, keyCode: compatible.tapKeyCode, flags: 0x2000, at: 0)
        check(
            "Secure Input Compatibility still reports an unused press",
            compatibleEngine.handle(type: .flagsChanged, keyCode: compatible.tapKeyCode, flags: 0, at: 0.2)
                .effect == .unusedPress(heldFor: 0.2))
        _ = compatibleEngine.handle(
            type: .flagsChanged, keyCode: compatible.tapKeyCode, flags: 0x2000, at: 1,
            insideSecureInput: true)
        check(
            "a press begun inside Secure Input never counts as unused",
            compatibleEngine.handle(type: .flagsChanged, keyCode: compatible.tapKeyCode, flags: 0, at: 1.2)
                .effect == nil)

        let modifier = HyperKeyPhysicalKey.rightOption.route(secureInputCompatible: false)!
        var modifierEngine = HyperKeyEngine(route: modifier)
        _ = modifierEngine.handle(type: .flagsChanged, keyCode: modifier.tapKeyCode, flags: 0x40, at: 0)
        check(
            "a modifier has no Quick Press",
            modifierEngine.handle(type: .flagsChanged, keyCode: modifier.tapKeyCode, flags: 0, at: 0.1)
                .effect == nil)
    }

    static func quickPressPolicy() {
        let original = HyperKeyQuickPress.originalKey
        check(
            "any press turns Caps Lock off",
            original.effect(heldFor: 0.01, capsLockOn: true, switchesInputSource: false)
                == .setCapsLock(false))
        check(
            "any press turns Caps Lock off before switching sources",
            original.effect(heldFor: 0.01, capsLockOn: true, switchesInputSource: true) == .setCapsLock(false)
        )
        check(
            "a press under 75 ms leaves Caps Lock off",
            original.effect(heldFor: 0.074, capsLockOn: false, switchesInputSource: false) == nil)
        check(
            "75 ms turns Caps Lock on",
            original.effect(heldFor: 0.076, capsLockOn: false, switchesInputSource: false)
                == .setCapsLock(true))
        check(
            "a press under 150 ms switches the input source",
            original.effect(heldFor: 0.149, capsLockOn: false, switchesInputSource: true)
                == .switchInputSource)
        check(
            "150 ms turns Caps Lock on when it switches sources",
            original.effect(heldFor: 0.151, capsLockOn: false, switchesInputSource: true)
                == .setCapsLock(true))
        check(
            "Escape ignores the hold",
            HyperKeyQuickPress.escape.effect(heldFor: 5, capsLockOn: true, switchesInputSource: true)
                == .escape)
        check(
            "None does nothing",
            HyperKeyQuickPress.none.effect(heldFor: 0.5, capsLockOn: false, switchesInputSource: false) == nil
        )
    }

    static func interruption() {
        let route = HyperKeyPhysicalKey.capsLock.route(secureInputCompatible: false)!
        var engine = HyperKeyEngine(route: route)
        _ = engine.handle(type: .keyDown, keyCode: route.tapKeyCode, flags: 0, at: 0)
        check("an F18 interruption needs a synthesized release", engine.reset())
        check("repeated reset emits no extra release", !engine.reset())
        let droppedUp = engine.handle(type: .keyUp, keyCode: route.tapKeyCode, flags: 0, at: 0.1)
        check("a release after cancellation is swallowed", droppedUp.decision == .suppress)
        check("a release after cancellation does not replay an action", droppedUp.effect == nil)
        _ = engine.handle(type: .keyDown, keyCode: route.tapKeyCode, flags: 0, at: 1)
        check("the next press recovers", engine.isActive)

        let compatible = HyperKeyPhysicalKey.capsLock.route(secureInputCompatible: true)!
        var modifierEngine = HyperKeyEngine(route: compatible)
        _ = modifierEngine.handle(type: .flagsChanged, keyCode: compatible.tapKeyCode, flags: 0x2000, at: 0)
        check("a modifier interruption needs no synthesized release", !modifierEngine.reset())
        let release = modifierEngine.handle(
            type: .flagsChanged, keyCode: compatible.tapKeyCode, flags: 0, at: 0.1)
        check(
            "a modifier's own release still clears the chord",
            release.decision == .rewrite(flags: 0, keyCode: Int64(kVK_Command), asFlagsChanged: true)
                && release.effect == nil)
    }
}
