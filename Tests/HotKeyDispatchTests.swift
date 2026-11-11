import AppKit
import Carbon.HIToolbox

@main
@MainActor
struct HotKeyDispatchTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        for includesShift in [false, true] { dispatch(includesShift: includesShift) }
        print("\(checks) dispatch checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    static func dispatch(includesShift: Bool) {
        let domain = "tinycast.hotkey-dispatch-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let manager = HotKeyManager(defaults: defaults)
        let center = HotKeyCenter.current!
        var presses = 0
        var releases = 0
        var cancellations = 0
        var palette = 0
        manager.onDictationPressed = { presses += 1 }
        manager.onDictationReleased = { releases += 1 }
        manager.onDictationCancelled = { cancellations += 1 }
        manager.onTogglePalette = { palette += 1 }
        manager.dictationEnabled = true
        manager.dictationHoldToTalk = true
        let chord = KeyShortcut.hyperChord(includesShift: includesShift)
        let hyper = KeyShortcut(
            carbonKeyCode: kVK_ANSI_G, carbonModifiers: KeyShortcut.carbonModifiers(from: chord))
        let control = KeyShortcut(carbonKeyCode: kVK_ANSI_G, carbonModifiers: controlKey)
        manager.setBinding(.combo(hyper), for: .dictation)
        let normal = center.entries[HotKeyAction.dictation.defaultsKey]!
        normal.onKeyDown(0)
        normal.onKeyUp?()
        check("normal dictation has both callbacks", presses == 1 && releases == 1)
        manager.setSecureInputEquivalents(includesShift: includesShift)
        let id = "secureInputEquivalent." + HotKeyAction.dictation.defaultsKey
        let secure = center.entries[id]!
        secure.onKeyDown(CGEventFlags.maskControl.rawValue | 1)
        secure.onKeyUp?()
        check("Left Control cannot invoke Hyper", presses == 1 && releases == 1)
        secure.onKeyDown(CGEventFlags.maskControl.rawValue)
        secure.onKeyUp?()
        check("missing side identity cannot invoke Hyper", presses == 1)
        secure.onKeyDown(CGEventFlags.maskControl.rawValue | 0x2000)
        secure.onKeyUp?()
        check("Right Control dispatches Hyper and release", presses == 2 && releases == 2)
        secure.onKeyDown(CGEventFlags.maskControl.rawValue | 0x2001)
        secure.onKeyUp?()
        check("both Controls keep the reserved Right Control route", presses == 3 && releases == 3)
        manager.setBinding(.combo(control), for: .togglePalette)
        check(
            "shared Control combination has one registration",
            center.entries.values.filter { $0.shortcut == control }.count == 1)
        let shared = center.entries[id]!
        shared.onKeyDown(CGEventFlags.maskControl.rawValue | 1)
        shared.onKeyUp?()
        check(
            "Left Control retains its ordinary Tinycast binding",
            palette == 1 && presses == 3 && releases == 3)
        shared.onKeyDown(CGEventFlags.maskControl.rawValue | 0x2000)
        shared.onKeyUp?()
        check(
            "Right Control selects Hyper rather than ordinary binding",
            palette == 1 && presses == 4 && releases == 4)
        shared.onKeyDown(CGEventFlags.maskControl.rawValue | 0x2000)
        manager.recordingAction = .togglePalette
        manager.recordingAction = nil
        let resumed = center.entries[id]!
        let beforeResume = presses
        resumed.onKeyDown(CGEventFlags.maskControl.rawValue | 1)
        resumed.onKeyUp?()
        check("recording clears the previous Hyper press route", presses == beforeResume && palette == 2)
        let beforeCancellation = cancellations
        resumed.onKeyDown(CGEventFlags.maskControl.rawValue | 0x2000)
        manager.setSecureInputEquivalents(includesShift: nil)
        check("leaving Secure Input cancels an active hold", cancellations == beforeCancellation + 1)
        check("leaving Secure Input removes equivalent", center.entries[id] == nil)
        check(
            "leaving Secure Input restores ordinary registration",
            center.entries[HotKeyAction.togglePalette.defaultsKey]?.shortcut == control)
        manager.setSecureInputEquivalents(includesShift: includesShift)
        manager.setBinding(nil, for: .dictation)
        check("unbinding removes equivalent", center.entries[id] == nil)
        check(
            "unbinding preserves ordinary Control registration",
            center.entries[HotKeyAction.togglePalette.defaultsKey]?.shortcut == control)
        manager.setBinding(.combo(hyper), for: .dictation)
        manager.setBinding(nil, for: .togglePalette)
        check(
            "deleting ordinary binding preserves Hyper equivalent",
            center.entries[id]?.shortcut == control
                && center.entries[HotKeyAction.togglePalette.defaultsKey] == nil)
        manager.setSecureInputEquivalents(includesShift: nil)
        manager.setBinding(.combo(control), for: .dictation)
        manager.setBinding(.combo(hyper), for: .togglePalette)
        manager.setSecureInputEquivalents(includesShift: includesShift)
        let swappedID = "secureInputEquivalent." + HotKeyAction.togglePalette.defaultsKey
        let swapped = center.entries[swappedID]!
        let beforePress = presses
        let beforeRelease = releases
        swapped.onKeyDown(CGEventFlags.maskControl.rawValue | 1)
        swapped.onKeyUp?()
        check(
            "ordinary Control dictation still releases through a shared registration",
            presses == beforePress + 1 && releases == beforeRelease + 1)
        swapped.onKeyDown(CGEventFlags.maskControl.rawValue | 0x2000)
        swapped.onKeyUp?()
        check(
            "Hyper selects the other action in a shared registration",
            palette == 3 && presses == beforePress + 1)
    }
}
