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
        forwardedPresses()
        unremappedCapsLock()
        forwardedF18()
        reorderedReleases()
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

    static func forwardedPresses() {
        let route = HyperKeyPhysicalKey.capsLock.route(secureInputCompatible: true)!
        var quartz = HyperKeyEngine(route: route)
        quartz.setForwarding(true)
        _ = quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0x2000, at: 0)
        let release = quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0, at: 0.25, timestamp: 10)
        check("Quartz must not request a second Quick Press when the keyboard handles it", release.effect == nil)
        check("a physical release delivered after Quartz confirms the solo press",
            quartz.physicalRelease(timestamp: 10, heldFor: 0.2) == 0.2)
        check("a physical release delivered first waits for Quartz",
            quartz.physicalRelease(timestamp: 20, heldFor: 0.3) == nil)
        _ = quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0x2000, at: 0.5)
        check("the same release delivered by Quartz consumes the physical duration",
            quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0, at: 0.9, timestamp: 20).effect
                == .unusedPress(heldFor: 0.3))
        _ = quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0x2000, at: 1)
        _ = quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0, at: 1.25, timestamp: 30)
        quartz.reset()
        check("a tap timeout discards Quartz evidence still waiting for the physical callback",
            quartz.physicalRelease(timestamp: 30, heldFor: 0.25) == nil)
        for stamp: UInt64 in [40, 50] {
            _ = quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0x2000, at: 2)
            check("Quartz releases can arrive in a batch before the HID callbacks",
                quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0, at: 2.25, timestamp: stamp).effect == nil)
        }
        check("a chord with no physical solo release cannot claim the next solo tap",
            quartz.physicalRelease(timestamp: 50, heldFor: 0.125) == 0.125)
        check("a consumed release cannot toggle twice", quartz.physicalRelease(timestamp: 50, heldFor: 0.125) == nil)
        for mapping in [HIDKeyMapping.capsLockToRightControl, .capsLockToF18] {
            var physical = PhysicalHyperKeyPress(mapping: mapping)
            for trigger in [mapping.source, mapping.destination] {
                _ = physical.handle(device: 1, usage: trigger, down: true, at: 1)
                check("a physical solo tap still toggles once",
                    physical.handle(device: 1, usage: trigger, down: false, at: 1.25) == 0.25)
                check("a duplicate release cannot toggle again",
                    physical.handle(device: 1, usage: trigger, down: false, at: 1.26) == nil)
                _ = physical.handle(device: 1, usage: trigger, down: true, at: 2)
                _ = physical.handle(device: 1, usage: 0x7_0000_000D, down: true, at: 2.1)
                _ = physical.handle(device: 1, usage: 0x7_0000_000D, down: false, at: 2.15)
                check("a J seen only on the keyboard disqualifies the press",
                    physical.handle(device: 1, usage: trigger, down: false, at: 2.25) == nil)
            }
            _ = physical.handle(device: 1, usage: mapping.source, down: true, at: 3)
            physical.remove(device: 1)
            check("disconnect cancels the hold", physical.handle(device: 1, usage: mapping.source, down: false, at: 4) == nil)
            _ = physical.handle(device: 1, usage: mapping.source, down: true, at: 5)
            _ = physical.handle(device: 2, usage: 0x7_0000_00E1, down: true, at: 5.1)
            check("another keyboard's Shift participates in the chord",
                physical.handle(device: 1, usage: mapping.source, down: false, at: 5.25) == nil)
            _ = physical.handle(device: 1, usage: mapping.source, down: true, at: 6)
            _ = physical.handle(device: 1, usage: 0x7_0000_00E1, down: false, at: 6.1)
            check("releasing a held Shift participates like Quartz flagsChanged",
                physical.handle(device: 1, usage: mapping.source, down: false, at: 6.25) == nil)
            for fn: UInt64 in [0x00FF_0000_0003, 0xFF01_0000_0003] {
                _ = physical.handle(device: 1, usage: mapping.source, down: true, at: 7)
                _ = physical.handle(device: 1, usage: fn, down: false, at: 7.1)
                check("releasing Fn while Caps Lock is held cancels a solo press",
                    physical.handle(device: 1, usage: mapping.source, down: false, at: 7.25) == nil)
            }
        }
        quartz.setForwarding(false)
        _ = quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0x2000, at: 5)
        check("returning to the local Mac restores Quartz Quick Press",
            quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0, at: 5.25).effect == .unusedPress(heldFor: 0.25))
        _ = quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0x2000, at: 6)
        quartz.setForwarding(true)
        quartz.setForwarding(false)
        check("a press spanning a change of focus is cancelled",
            quartz.handle(type: .flagsChanged, keyCode: 62, flags: 0, at: 6.25).effect == nil)
    }

    static func unremappedCapsLock() {
        var engine = HyperKeyEngine(route: HyperKeyPhysicalKey.capsLock.route(secureInputCompatible: true))
        engine.setForwarding(true)
        var physical = PhysicalHyperKeyPress(mapping: .capsLockToRightControl)
        _ = physical.handle(device: 1, usage: HIDKeyMapping.capsLock, down: true, at: 1)
        let duration = physical.handle(device: 1, usage: HIDKeyMapping.capsLock, down: false, at: 1.25)
        check("an unremapped physical Caps Lock cannot authorize Quick Press by itself",
            duration.flatMap { engine.physicalRelease(timestamp: 100, heldFor: $0) } == nil)
        _ = engine.handle(type: .flagsChanged, keyCode: kVK_CapsLock, flags: 0x10000, at: 1.25, timestamp: 100)
        _ = engine.handle(type: .flagsChanged, keyCode: 62, flags: 0x2000, at: 2)
        check("a later remapped press cannot claim the earlier raw Caps Lock release",
            engine.handle(type: .flagsChanged, keyCode: 62, flags: 0, at: 2.25, timestamp: 200).effect == nil)
    }

    static func forwardedF18() {
        var engine = HyperKeyEngine(route: HyperKeyPhysicalKey.capsLock.route(secureInputCompatible: false))
        engine.setForwarding(true)
        _ = engine.physicalRelease(timestamp: 100, heldFor: 0.25)
        _ = engine.handle(type: .keyDown, keyCode: kVK_F18, flags: 0, at: 1)
        check("an F18 solo release confirms its physical press",
            engine.handle(type: .keyUp, keyCode: kVK_F18, flags: 0, at: 1.25, timestamp: 100).effect
                == .unusedPress(heldFor: 0.25))
        _ = engine.handle(type: .keyDown, keyCode: kVK_F18, flags: 0, at: 2)
        engine.reset()
        _ = engine.physicalRelease(timestamp: 200, heldFor: 0.25)
        check("the release of an interrupted F18 press cannot confirm a solo tap",
            engine.handle(type: .keyUp, keyCode: kVK_F18, flags: 0, at: 2.25, timestamp: 200).effect == nil)
    }

    static func reorderedReleases() {
        var releases = ForwardedQuickPress()
        _ = releases.confirm(.keyboard, timestamp: 90, duration: 0.25)
        _ = releases.confirm(.keyboard, timestamp: 80, duration: 0.125)
        check("queued reports from different keyboards can arrive out of timestamp order",
            releases.confirm(.quartz, timestamp: 80, duration: 1) == 0.125)
        check("each report keeps its physical duration",
            releases.confirm(.quartz, timestamp: 90, duration: 1) == 0.25)
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
