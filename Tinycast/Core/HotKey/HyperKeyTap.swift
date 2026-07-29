import AppKit
import Carbon.HIToolbox
import Combine
@preconcurrency import Darwin
@preconcurrency import IOKit.hidsystem

// Snapshot the imported mutable C global `mach_task_self_` (process-constant) so actor code never touches the raw global under strict concurrency.
private let machTaskSelf = mach_task_self_

/// C entry point for the event tap (always on the main thread): decode the `CGEvent`, cross into the actor via `assumeIsolated` for a Sendable `Decision`, then apply it out here (`Unmanaged<CGEvent>` isn't Sendable).
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

/// HID-level remap of Caps Lock → F18 while it's the Hyper key — the caps-lock toggle (LED + latch) happens below every CGEventTap, so the key must stop being Caps Lock at the source (same `UserKeyMapping` as `hidutil`; cleared on unbind/quit, never survives reboot).
private enum CapsLockRemap {
    // HID usages: keyboard page 0x07, Caps Lock 0x39, F18 0x6D.
    private static let mappingOn =
        #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#
    private static let mappingOff = #"{"UserKeyMapping":[]}"#

    // Serial queue so rapid on→off→on toggles (e.g. switching the Hyper key away from Caps Lock and back) apply hidutil in call order instead of racing as independent detached tasks and leaving the wrong final remap.
    private static let queue = DispatchQueue(label: "com.tinycast.capslock-remap", qos: .utility)

    static func setEnabled(_ enabled: Bool) {
        let mapping = enabled ? mappingOn : mappingOff
        queue.async { apply(mapping) }
    }

    /// Synchronous variant for `applicationWillTerminate`; sharing the queue guarantees every pending remap finishes before Caps Lock is restored.
    @MainActor
    static func clearBlocking() {
        queue.sync { apply(mappingOff) }
    }

    private static func apply(_ mapping: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", mapping]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                NSLog("Tinycast: hidutil remap exited %d", process.terminationStatus)
            }
        } catch {
            NSLog("Tinycast: hidutil caps lock remap failed: %@", error.localizedDescription)
        }
    }
}

/// The Hyper Key engine: a modifying `CGEventTap` turning one physical key (Caps Lock or a right-side modifier) into the ⌃⌥(⇧)⌘ chord system-wide; a separate layer from `HotKeyCenter` (Carbon can't intercept lone keys), with rewritten flags flowing into Carbon matching so existing hotkeys fire from Hyper+key unchanged.
@MainActor
final class HyperKeyTap: ObservableObject {
    enum Status: Equatable {
        case off
        case active
        case needsAccessibility
    }

    /// What the tap callback should do with an event, decided on the actor (`asFlagsChanged` converts the type in place, turning remapped Caps Lock F18 key events into modifier transitions downstream).
    enum Decision: Sendable {
        case pass
        case suppress
        case rewrite(flags: UInt64, keyCode: Int64? = nil, asFlagsChanged: Bool = false)
    }

    /// Marker in `.eventSourceUserData` on events this tap posts, so it never reacts to its own synthetics (FourCC "TYCT", same as `HotKeyCenter`).
    nonisolated static let syntheticTag: Int64 = 0x5459_4354

    /// `NX_DEVICE…KEYMASK` bits (IOLLEvent.h): device-level flags a real modifier press carries alongside its generic mask; the Hyper chord posts the *left* set since some consumers distinguish sides and generic-only flags don't always read as fully pressed.
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

    @Published private(set) var status: Status = .off

    private var settings: AppSettings?
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var sessionTokens: [NotificationToken] = []
    private var hidConnect: io_connect_t = IO_OBJECT_NULL

    /// Mirror of `settings.hyperKey`, updated only by its publisher; the toggles (`Include Shift`, `Quick Press`) are read live from `settings` so the tap never acts on a stale copy.
    private var key: HyperKeyPhysicalKey = .none

    // Hold state machine.
    private var hyperActive = false
    private var hyperDownAt: ContinuousClock.Instant?
    private var otherKeyPressed = false
    private let clock = ContinuousClock()
    private static let quickPressWindow: Duration = .milliseconds(250)

    #if compiler(>=6.2)
        // Isolated so teardown can release the main-actor IOKit connection; the tap is an AppCore-owned singleton released on main. The kernel reclaims this at process exit anyway, so this only matters if it's ever recreated.
        isolated deinit {
            if hidConnect != IO_OBJECT_NULL { IOServiceClose(hidConnect) }
        }
    #else
        deinit {
            if hidConnect != IO_OBJECT_NULL { IOServiceClose(hidConnect) }
        }
    #endif

    func start(settings: AppSettings) {
        self.settings = settings
        // @Published emits synchronously on the main actor (hence assumeIsolated), before the property is written, so the handler uses the payload.
        settings.$hyperKey
            .sink { [weak self] value in MainActor.assumeIsolated { self?.applyKey(value) } }
            .store(in: &cancellables)

        // Fast user switching: another session owns the keyboard, so drop half-held state and stop rewriting until this session is active again.
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidResign() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidBecomeActive() }
                }, center: center),
        ]
    }

    // MARK: - Hyper chord flags

    /// The flags OR'd into every event while Hyper is held: the generic ⌃⌥(⇧)⌘ masks plus the left-side device bits.
    private var hyperFlagsRaw: UInt64 {
        var raw =
            CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
            | DeviceFlag.leftControl | DeviceFlag.leftOption | DeviceFlag.leftCommand
        if settings?.hyperKeyIncludesShift ?? true {
            raw |= CGEventFlags.maskShift.rawValue | DeviceFlag.leftShift
        }
        return raw
    }

    /// The Hyper key's own flag residue scrubbed from rewritten events: Caps Lock's alpha-shift bit, or (key modifier outside the Hyper set) its generic mask plus both device bits.
    private var strippedFlagsRaw: UInt64 {
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

    private func hyperized(_ flagsRaw: UInt64) -> UInt64 {
        (flagsRaw & ~strippedFlagsRaw) | hyperFlagsRaw
    }

    // MARK: - Event decisions

    func decide(
        type: CGEventType, keyCode: Int, flagsRaw: UInt64, isAutorepeat: Bool, isSynthetic: Bool
    ) -> Decision {
        guard !isSynthetic, let tapCode = key.tapKeyCode else { return .pass }

        if keyCode == tapCode {
            return decideHyperKeyEvent(type: type, flagsRaw: flagsRaw, isAutorepeat: isAutorepeat)
        }
        // Fallback before the HID remap takes hold: the key still arrives as Caps Lock, so ride the modifier path (the LED toggles — un-remapped HID behavior, not ours to stop).
        if key == .capsLock, keyCode == kVK_CapsLock, type == .flagsChanged {
            return decideModifierTransition(flagsRaw: flagsRaw, swapKeyCode: true)
        }
        guard hyperActive else { return .pass }
        // Any other key or modifier going down while Hyper is held makes this a combo, not a tap.
        if type == .keyDown || type == .flagsChanged { otherKeyPressed = true }
        return .rewrite(flags: hyperized(flagsRaw))
    }

    private func decideHyperKeyEvent(
        type: CGEventType, flagsRaw: UInt64, isAutorepeat: Bool
    ) -> Decision {
        if key.tapUsesKeyEvents {
            // Caps Lock (via its F18 remap) arrives as keyDown/keyUp; convert both ends into Left Control flagsChanged transitions so downstream sees the Hyper chord move with the key, not a swallowed press.
            switch type {
            case .keyDown:
                if isAutorepeat { return .suppress }
                if !hyperActive { beginHold() }
                return .rewrite(
                    flags: hyperized(flagsRaw), keyCode: Int64(kVK_Control), asFlagsChanged: true)
            case .keyUp:
                if hyperActive { endHold() }
                return .rewrite(
                    flags: flagsRaw & ~strippedFlagsRaw, keyCode: Int64(kVK_Control),
                    asFlagsChanged: true)
            default:
                return .pass
            }
        }
        guard type == .flagsChanged else { return .pass }
        return decideModifierTransition(flagsRaw: flagsRaw, swapKeyCode: false)
    }

    /// Press/release of a modifier-style Hyper key: flagsChanged doesn't self-describe direction, so use toggle semantics (querying session key state races the release, inverting the state machine and breaking Quick Press); a missed release lingers only until the watchdog or next press.
    private func decideModifierTransition(flagsRaw: UInt64, swapKeyCode: Bool) -> Decision {
        let keyCode: Int64? = swapKeyCode ? Int64(kVK_Control) : nil
        if !hyperActive {
            beginHold()
            return .rewrite(flags: hyperized(flagsRaw), keyCode: keyCode)
        }
        endHold()
        return .rewrite(flags: flagsRaw & ~strippedFlagsRaw, keyCode: keyCode)
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
        guard isQuick else { return }
        let action = settings?.hyperKeyQuickPress ?? .none
        let key = key
        // Posting events or touching IOKit from inside the tap callback risks re-entrancy; finish the press on the next runloop turn.
        Task { @MainActor [weak self] in self?.fireQuickPress(action, for: key) }
    }

    private func fireQuickPress(_ action: HyperKeyQuickPress, for key: HyperKeyPhysicalKey) {
        switch action {
        case .none:
            break
        case .originalKey:
            if key == .capsLock { setCapsLockState(!capsLockState()) }
        case .escape:
            postKey(CGKeyCode(kVK_Escape))
        }
    }

    private func cancelHold() {
        hyperActive = false
        hyperDownAt = nil
        otherKeyPressed = false
    }

    // MARK: - Configuration

    private func applyKey(_ newKey: HyperKeyPhysicalKey) {
        guard newKey != key else { return }
        cancelHold()
        let wasCapsLock = key == .capsLock
        key = newKey
        if newKey == .capsLock {
            // Remapping takes Caps Lock's own function away: unlatch the lock and hand the physical key to the tap as F18.
            setCapsLockState(false)
            CapsLockRemap.setEnabled(true)
        } else if wasCapsLock {
            CapsLockRemap.setEnabled(false)
        }
        syncTapPresence()
    }

    /// Called from `applicationWillTerminate`: detach callbacks and hand the HID-level Caps Lock remap back to the system before exiting.
    func prepareForTermination() {
        tearDownTap()
        stopHealthTimer()
        CapsLockRemap.clearBlocking()
        if hidConnect != IO_OBJECT_NULL {
            IOServiceClose(hidConnect)
            hidConnect = IO_OBJECT_NULL
        }
    }

    // MARK: - Tap lifecycle

    private func syncTapPresence() {
        if key == .none {
            tearDownTap()
            stopHealthTimer()
            status = .off
        } else {
            startHealthTimer()
            installTapIfNeeded()
        }
    }

    private func installTapIfNeeded() {
        guard tapPort == nil, key != .none else { return }
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
        else {
            // A modifying keyboard tap needs the Accessibility grant; the health timer retries so the dot flips green the moment the user grants it.
            status = .needsAccessibility
            return
        }
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        status = .active
    }

    private func tearDownTap() {
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

    /// Called from the callback when the system disables the tap (timeout / user input); any half-tracked hold is stale by then.
    fileprivate func reenable() {
        cancelHold()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.healthCheck() }
        }
    }

    private func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    /// One-second watchdog while a key is configured: retries installation until Accessibility is granted, notices revocation, revives a system-disabled tap, and clears a stuck hold.
    private func healthCheck() {
        guard key != .none else { return }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
            status = .needsAccessibility
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }

    }

    private func sessionDidResign() {
        cancelHold()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: false) }
    }

    private func sessionDidBecomeActive() {
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        } else {
            installTapIfNeeded()
        }
    }

    // MARK: - Synthetics & caps state

    /// Synthesize a bare key press for Quick Press, tagged so `decide` ignores it.
    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        for event in [down, up] {
            event?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// The classic IOHIDSystem connection for reading/driving the Caps Lock LED + lock state; used only by the explicit Quick Press toggle and the one-time unlatch.
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
