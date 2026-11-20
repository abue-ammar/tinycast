import AppKit
import Carbon.HIToolbox
@preconcurrency import IOKit.hidsystem
import Synchronization

// Snapshot the mutable C global `mach_task_self_`, so actor code never reads it raw.
private let machTaskSelf = mach_task_self_

private func hyperKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HyperKeyTap.Session>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}

@MainActor
final class HyperKeyTap {
    /// Marker on events this tap posts, so it never reacts to its own synthetics.
    nonisolated static let syntheticTag: Int64 = 0x5459_4354

    var onUnmappedCapsLock: (() -> Void)?

    private var route: HyperKeyRoute?
    private var includesShift = true
    private var quickPress: HyperKeyQuickPress = .none
    private var session: Session?
    private var forwardedPresses: ForwardedQuickPressMonitor?
    private var hidConnect: io_connect_t = IO_OBJECT_NULL

    // Isolated so teardown can release the main-actor IOKit connection.
    isolated deinit {
        tearDown()
        if hidConnect != IO_OBJECT_NULL { IOServiceClose(hidConnect) }
    }

    var isEnabled: Bool? { session?.isEnabled }
    var runLoopSourceIsValid: Bool? { session?.runLoopSourceIsValid }

    func configure(route: HyperKeyRoute?, includesShift: Bool, quickPress: HyperKeyQuickPress) {
        self.quickPress = quickPress
        guard route != self.route || includesShift != self.includesShift else { return }
        self.route = route
        self.includesShift = includesShift
        guard session?.configure(route: route, includesShift: includesShift) == true else { return }
        Self.postModifierRelease()
    }

    func cancelHold() {
        forwardedPresses?.cancelHold()
        guard session?.cancelHold() == true else { return }
        Self.postModifierRelease()
    }

    // MARK: - Tap lifecycle

    /// Created here, so a refused grant fails synchronously; the session's thread then serves it.
    @discardableResult
    func install() -> Bool {
        guard session == nil else { return true }
        let engine = HyperKeyEngine(route: route, includesShift: includesShift)
        session = Session(engine: engine) { [weak self] route, effect in
            self?.handle(effect, from: route)
        }
        return session != nil
    }

    func tearDown() {
        cancelHold()
        forwardedPresses = nil
        session?.stop()
        session = nil
    }

    // MARK: - Effects

    private var isForwarding: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.universalcontrol"
    }

    // Universal Control can forward the chord's letter before it reaches the sending Mac's tap.
    func updateForwarding() {
        guard let session, let mapping = route?.remap, quickPress != .none, isForwarding,
            !IsSecureEventInputEnabled(), Permissions.hasInputMonitoring()
        else {
            guard forwardedPresses != nil else { return }
            forwardedPresses = nil
            session?.setForwarding(false)
            return
        }
        guard forwardedPresses?.mapping != mapping else { return }
        forwardedPresses = ForwardedQuickPressMonitor(mapping: mapping) { [weak self] timestamp, duration in
            guard let self, let confirmed = session.physicalRelease(timestamp: timestamp, heldFor: duration),
                isForwarding, session.isEnabled
            else { return }
            performQuickPress(heldFor: confirmed)
        }
        session.setForwarding(forwardedPresses != nil)
    }

    private func handle(_ effect: HyperKeyEngine.Effect, from route: HyperKeyRoute) {
        guard session != nil, route == self.route else { return }
        switch effect {
        case .unmappedCapsLock:
            onUnmappedCapsLock?()
        case .unusedPress(let duration):
            if forwardedPresses == nil || isForwarding { performQuickPress(heldFor: duration) }
        }
    }

    private func performQuickPress(heldFor duration: TimeInterval) {
        // Secure Input hides the key that made this press a chord, so a short hold proves nothing.
        guard !IsSecureEventInputEnabled(),
            let effect = quickPress.effect(
                heldFor: duration, capsLockOn: capsLockState(),
                switchesInputSource: UserDefaults.standard.bool(forKey: "TISRomanSwitchState"))
        else { return }
        switch effect {
        case .escape:
            postKey(CGKeyCode(kVK_Escape))
        case .setCapsLock(let on):
            setCapsLockState(on)
        case .switchInputSource:
            InputSourceSwitcher.toggleCapsLockInputSource()
        }
    }

    // MARK: - Synthetics & caps state

    nonisolated static func postModifierRelease() {
        guard let event = CGEvent(source: nil) else { return }
        event.type = .flagsChanged
        event.flags = []
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Command))
        event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        event.post(tap: .cghidEventTap)
    }

    /// Synthesize a bare key press for Quick Press, tagged so the tap ignores it.
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

    // MARK: - Session

    /// One installed tap and the thread that serves it, so a busy main thread never stalls typing.
    fileprivate final class Session: Sendable {
        // Core Foundation allows cross-thread port and run-loop calls; only the worker runs the loop.
        private struct Installation: @unchecked Sendable {
            let port: CFMachPort
            var source: CFRunLoopSource?
            var runLoop: CFRunLoop?
        }

        private struct State {
            var engine: HyperKeyEngine
            var installation: Installation?
            var isRunning = true
        }

        private let state: Mutex<State>
        private let deliver: @MainActor @Sendable (HyperKeyRoute, HyperKeyEngine.Effect) -> Void

        init?(
            engine: HyperKeyEngine,
            deliver: @escaping @MainActor @Sendable (HyperKeyRoute, HyperKeyEngine.Effect) -> Void
        ) {
            state = Mutex(State(engine: engine))
            self.deliver = deliver
            let events: CGEventMask =
                (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
            guard
                let port = CGEvent.tapCreate(
                    tap: .cghidEventTap,
                    place: .headInsertEventTap,
                    options: .defaultTap,
                    eventsOfInterest: events,
                    callback: hyperKeyTapCallback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque())
            else { return nil }
            state.withLock { $0.installation = Installation(port: port) }
            let thread = Thread { [self] in run() }
            thread.name = "com.tinycast.hyper-key"
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        var isEnabled: Bool {
            state.withLock { $0.installation.map { CGEvent.tapIsEnabled(tap: $0.port) } } ?? false
        }

        var runLoopSourceIsValid: Bool {
            state.withLock { $0.installation?.source.map(CFRunLoopSourceIsValid) } ?? false
        }

        /// Swaps the route and drops any hold, which the old route's release would no longer end.
        func configure(route: HyperKeyRoute?, includesShift: Bool) -> Bool {
            state.withLock { state in
                let needsRelease = state.engine.reset()
                state.engine.route = route
                state.engine.includesShift = includesShift
                return needsRelease
            }
        }

        func cancelHold() -> Bool {
            state.withLock { $0.engine.reset() }
        }

        func setForwarding(_ enabled: Bool) {
            state.withLock { $0.engine.setForwarding(enabled) }
        }

        func physicalRelease(timestamp: UInt64, heldFor duration: TimeInterval) -> TimeInterval? {
            state.withLock { $0.engine.physicalRelease(timestamp: timestamp, heldFor: duration) }
        }

        func stop() {
            state.withLock { state in
                state.isRunning = false
                guard let runLoop = state.installation?.runLoop else { return }
                // A queued stop also covers closing before the worker enters its run loop.
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                    CFRunLoopStop(CFRunLoopGetCurrent())
                }
                CFRunLoopWakeUp(runLoop)
            }
        }

        private func run() {
            autoreleasepool {
                guard let port = state.withLock({ $0.installation })?.port else { return }
                defer {
                    CGEvent.tapEnable(tap: port, enable: false)
                    CFMachPortInvalidate(port)
                }
                guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0),
                    let runLoop = CFRunLoopGetCurrent()
                else { return }
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                defer { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }
                let shouldRun = state.withLock { state in
                    guard state.isRunning else { return false }
                    state.installation = Installation(port: port, source: source, runLoop: runLoop)
                    return true
                }
                guard shouldRun else { return }
                CFRunLoopRun()
            }
        }

        func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
            let unchanged = Unmanaged.passUnretained(event)
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // Whatever was held went unseen while disabled, so the hold is stale.
                let needsRelease = state.withLock { state in
                    if let port = state.installation?.port { CGEvent.tapEnable(tap: port, enable: true) }
                    return state.engine.reset()
                }
                if needsRelease { HyperKeyTap.postModifierRelease() }
                return unchanged
            }
            guard event.getIntegerValueField(.eventSourceUserData) != HyperKeyTap.syntheticTag else {
                return unchanged
            }
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.rawValue
            let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let now = ProcessInfo.processInfo.systemUptime
            let (route, result, generation) = state.withLock { state in
                let route = state.engine.route
                let insideSecureInput = keyCode == route?.tapKeyCode && IsSecureEventInputEnabled()
                let result = state.engine.handle(
                    type: type, keyCode: keyCode, flags: flags, isAutorepeat: isAutorepeat, at: now,
                    insideSecureInput: insideSecureInput, timestamp: event.timestamp)
                return (route, result, state.engine.quickPressGeneration)
            }
            if let route, let effect = result.effect {
                Task { @MainActor [self] in
                    if case .unusedPress = effect,
                        !state.withLock({ $0.isRunning && $0.engine.quickPressGeneration == generation })
                    { return }
                    deliver(route, effect)
                }
            }
            switch result.decision {
            case .pass:
                return unchanged
            case .suppress:
                return nil
            case .rewrite(let flags, let keyCode, let asFlagsChanged):
                if asFlagsChanged { event.type = .flagsChanged }
                if let keyCode { event.setIntegerValueField(.keyboardEventKeycode, value: keyCode) }
                event.flags = CGEventFlags(rawValue: flags)
                return unchanged
            }
        }
    }
}
