import AppKit
import Carbon.HIToolbox
@preconcurrency import IOKit.hidsystem

// Snapshot the mutable C global `mach_task_self_`, so actor code never reads it raw.
private let machTaskSelf = mach_task_self_

/// C entry point: decode, cross in for a Sendable `Decision`, then apply it out here.
private func hyperKeyEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HyperKeyTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let isSynthetic = event.getIntegerValueField(.eventSourceUserData) == HyperKeyTap.syntheticTag
    let flags = event.flags.rawValue

    let decision = MainActor.assumeIsolated {
        tap.decide(
            type: type, keyCode: keyCode, flagsRaw: flags,
            isAutorepeat: isAutorepeat, isSynthetic: isSynthetic)
    }
    switch decision {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .suppress:
        return nil
    case .rewrite(let flags, let keyCode, let asFlagsChanged):
        if asFlagsChanged { event.type = .flagsChanged }
        if let keyCode {
            event.setIntegerValueField(.keyboardEventKeycode, value: keyCode)
        }
        event.flags = CGEventFlags(rawValue: flags)
        return Unmanaged.passUnretained(event)
    }
}

@MainActor
final class HyperKeyTap {
    /// What the callback should do, decided on the actor; `asFlagsChanged` converts in place.
    enum Decision: Sendable {
        case pass
        case suppress
        case rewrite(flags: UInt64, keyCode: Int64? = nil, asFlagsChanged: Bool = false)
    }

    /// Marker on events this tap posts, so it never reacts to its own synthetics.
    nonisolated static let syntheticTag: Int64 = 0x5459_4354

    /// Device-level modifier bits from IOLLEvent.h. See docs/features/hotkeys.md#the-hyper-key.
    private enum DeviceFlag {
        static let leftControl: UInt64 = 0x0000_0001
        static let leftShift: UInt64 = 0x0000_0002
        static let rightShift: UInt64 = 0x0000_0004
        static let leftCommand: UInt64 = 0x0000_0008
        static let rightCommand: UInt64 = 0x0000_0010
        static let leftOption: UInt64 = 0x0000_0020
        static let rightOption: UInt64 = 0x0000_0040
        static let rightControl: UInt64 = 0x0000_2000
    }

    var route: HyperKeyRoute? {
        didSet { if route != oldValue { cancelHold() } }
    }

    var onUnmappedCapsLock: (() -> Void)?

    private let settings: AppSettings
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hidConnect: io_connect_t = IO_OBJECT_NULL

    private var hyperActive = false
    private var hyperDownAt: ContinuousClock.Instant?
    private var otherKeyPressed = false
    private let clock = ContinuousClock()
    private static let quickPressWindow: Duration = .milliseconds(250)

    init(settings: AppSettings) {
        self.settings = settings
    }

    // Isolated so teardown can release the main-actor IOKit connection.
    isolated deinit {
        if hidConnect != IO_OBJECT_NULL { IOServiceClose(hidConnect) }
    }

    var isInstalled: Bool { tapPort != nil }
    var isEnabled: Bool? { tapPort.map { CGEvent.tapIsEnabled(tap: $0) } }
    var runLoopSourceIsValid: Bool? { runLoopSource.map(CFRunLoopSourceIsValid) }

    // MARK: - Hyper chord flags

    /// The flags OR'd in while Hyper is held: the generic masks plus left-side device bits.
    private var hyperFlagsRaw: UInt64 {
        var raw =
            CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
            | DeviceFlag.leftControl | DeviceFlag.leftOption | DeviceFlag.leftCommand
        if settings.hyperKeyIncludesShift {
            raw |= CGEventFlags.maskShift.rawValue | DeviceFlag.leftShift
        }
        return raw
    }

    /// The Hyper key's own flag residue, scrubbed from every rewritten event.
    private var strippedFlagsRaw: UInt64 {
        guard let key = route?.key else { return 0 }
        if key == .capsLock { return CGEventFlags.maskAlphaShift.rawValue }
        guard let own = key.ownFlag, hyperFlagsRaw & own.rawValue == 0 else { return 0 }
        return own.rawValue | Self.deviceBits(for: own)
    }

    private static func deviceBits(for flag: CGEventFlags) -> UInt64 {
        switch flag {
        case .maskControl: return DeviceFlag.leftControl | DeviceFlag.rightControl
        case .maskShift: return DeviceFlag.leftShift | DeviceFlag.rightShift
        case .maskAlternate: return DeviceFlag.leftOption | DeviceFlag.rightOption
        case .maskCommand: return DeviceFlag.leftCommand | DeviceFlag.rightCommand
        default: return 0
        }
    }

    /// F18 carries fn like any function key; a `flagsChanged` saying so reads as a real fn press.
    private static let functionKeyFlagRaw = CGEventFlags.maskSecondaryFn.rawValue

    private func hyperized(_ flagsRaw: UInt64) -> UInt64 {
        (flagsRaw & ~strippedFlagsRaw) | hyperFlagsRaw
    }

    // MARK: - Event decisions

    func decide(
        type: CGEventType, keyCode: Int, flagsRaw: UInt64, isAutorepeat: Bool, isSynthetic: Bool
    ) -> Decision {
        guard !isSynthetic, let route else { return .pass }

        if keyCode == route.tapKeyCode {
            return decideHyperKeyEvent(
                route: route, type: type, flagsRaw: flagsRaw, isAutorepeat: isAutorepeat)
        }
        // A latch carries no release, so it passes as Caps Lock and the keyboard is repaired.
        if route.remap != nil, keyCode == kVK_CapsLock, type == .flagsChanged {
            Task { @MainActor [weak self] in self?.onUnmappedCapsLock?() }
            return .pass
        }
        guard hyperActive else { return .pass }
        // Any other key or modifier going down while Hyper is held makes this a combo, not a tap.
        if type == .keyDown || type == .flagsChanged { otherKeyPressed = true }
        return .rewrite(flags: hyperized(flagsRaw))
    }

    /// docs/features/hotkeys.md#press-tracking-reads-the-event
    private func decideHyperKeyEvent(
        route: HyperKeyRoute, type: CGEventType, flagsRaw: UInt64, isAutorepeat: Bool
    ) -> Decision {
        guard let modifier = route.modifier else {
            return decideFunctionKeyEvent(type: type, flagsRaw: flagsRaw, isAutorepeat: isAutorepeat)
        }
        guard type == .flagsChanged else { return .pass }
        let isDown = ModifierKey.held(in: flagsRaw, globeDown: false).contains(modifier)
        return .rewrite(flags: transition(isDown: isDown, flagsRaw: flagsRaw))
    }

    /// F18 arrives as keyDown/keyUp; both ends become Left Control `flagsChanged` transitions.
    private func decideFunctionKeyEvent(
        type: CGEventType, flagsRaw: UInt64, isAutorepeat: Bool
    ) -> Decision {
        let flagsRaw = flagsRaw & ~Self.functionKeyFlagRaw
        switch type {
        case .keyDown:
            if isAutorepeat { return .suppress }
            let flags = transition(isDown: true, flagsRaw: flagsRaw)
            return .rewrite(flags: flags, keyCode: Int64(kVK_Control), asFlagsChanged: true)
        case .keyUp:
            let flags = transition(isDown: false, flagsRaw: flagsRaw)
            return .rewrite(flags: flags, keyCode: Int64(kVK_Control), asFlagsChanged: true)
        default:
            return .pass
        }
    }

    private func transition(isDown: Bool, flagsRaw: UInt64) -> UInt64 {
        if isDown {
            if !hyperActive { beginHold() }
            return hyperized(flagsRaw)
        }
        if hyperActive { endHold() }
        return flagsRaw & ~strippedFlagsRaw
    }

    // MARK: - Hold state machine

    private func beginHold() {
        hyperActive = true
        hyperDownAt = clock.now
        otherKeyPressed = false
    }

    private func endHold() {
        let isQuick =
            !otherKeyPressed && hyperDownAt.map { clock.now - $0 < Self.quickPressWindow } ?? false
        hyperActive = false
        hyperDownAt = nil
        guard isQuick, let key = route?.key, key.hasOriginalFunction else { return }
        let action = settings.hyperKeyQuickPress
        // Posting or touching IOKit inside the callback risks re-entrancy, so defer a turn.
        Task { @MainActor [weak self] in self?.fireQuickPress(action, for: key) }
    }

    private func fireQuickPress(_ action: HyperKeyQuickPress, for key: HyperKeyPhysicalKey) {
        // Secure Input hides the key that made this press a chord, so a short hold proves nothing.
        guard !IsSecureEventInputEnabled() else { return }
        switch action {
        case .none:
            break
        case .originalKey:
            if key == .capsLock { setCapsLockState(!capsLockState()) }
        case .escape:
            postKey(CGKeyCode(kVK_Escape))
        }
    }

    func cancelHold() {
        hyperActive = false
        hyperDownAt = nil
        otherKeyPressed = false
    }

    // MARK: - Tap lifecycle

    /// False when Accessibility is missing: only a trusted process may modify events.
    @discardableResult
    func install() -> Bool {
        guard tapPort == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hyperKeyEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func tearDown() {
        cancelHold()
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

    /// Called when the system disables the tap; any half-tracked hold is stale by then.
    func reenable() {
        cancelHold()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    // MARK: - Synthetics & caps state

    /// Synthesize a bare key press for Quick Press, tagged so `decide` ignores it.
    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        for event in [down, up] {
            // The session source still carries our injected chord, and a modified Escape is eaten.
            event?.flags = []
            event?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Remapping takes Caps Lock's own function away, so a latched lock would stay stuck on.
    func unlatchCapsLock() {
        setCapsLockState(false)
    }

    /// The IOHIDSystem connection for the Caps Lock LED and lock state.
    private func hidConnection() -> io_connect_t {
        if hidConnect != IO_OBJECT_NULL { return hidConnect }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return IO_OBJECT_NULL }
        var connect: io_connect_t = IO_OBJECT_NULL
        IOServiceOpen(service, machTaskSelf, UInt32(kIOHIDParamConnectType), &connect)
        IOObjectRelease(service)
        hidConnect = connect
        return connect
    }

    private func capsLockState() -> Bool {
        let connect = hidConnection()
        guard connect != IO_OBJECT_NULL else { return false }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        return on
    }

    private func setCapsLockState(_ on: Bool) {
        let connect = hidConnection()
        guard connect != IO_OBJECT_NULL else { return }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
    }
}
