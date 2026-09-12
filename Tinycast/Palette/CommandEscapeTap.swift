import AppKit
import Carbon.HIToolbox

/// C entry point: the decision is a key-code compare, so it is made here rather than crossing out.
private func commandEscapeTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<CommandEscapeTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard
        CommandEscapeTap.isChord(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
    else { return Unmanaged.passUnretained(event) }

    let claimed = MainActor.assumeIsolated { tap.fire() }
    return claimed ? nil : Unmanaged.passUnretained(event)
}

/// ⌘⎋ is claimed upstream of every app, so the palette takes it where it enters the system.
///
/// The window server binds the chord itself, so it never reaches `onCommandShortcut` the way ⌘.
/// and ⌘w do: no keystroke is left by the time the responder chain runs, and a head-inserted HID
/// tap is the one place earlier than that. See docs/features/palette.md.
@MainActor
final class CommandEscapeTap {
    /// Claims the chord and returns true, or declines it so the rest of the system still gets it.
    private let onChord: () -> Bool

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onChord: @escaping () -> Bool) {
        self.onChord = onChord
    }

    isolated deinit {
        tearDown()
    }

    /// True only for a bare ⌘⎋: any further modifier spells somebody else's chord.
    nonisolated static func isChord(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == Int64(kVK_Escape)
            && flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                == .maskCommand
    }

    /// Called on every show: a tap refused for want of Accessibility is retried the next time.
    func enable() {
        guard let port = installIfNeeded() else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func disable() {
        guard let tapPort else { return }
        CGEvent.tapEnable(tap: tapPort, enable: false)
    }

    private func installIfNeeded() -> CFMachPort? {
        if let tapPort { return tapPort }
        // Head of the HID stream: anywhere later and the system hotkey has already eaten the chord.
        guard
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                callback: commandEscapeTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else { return nil }
        tapPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return port
    }

    private func tearDown() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }

    fileprivate func fire() -> Bool {
        onChord()
    }

    /// The system disables a tap it thinks is too slow; ours only ever compares two integers.
    fileprivate func reenable() {
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }
}
