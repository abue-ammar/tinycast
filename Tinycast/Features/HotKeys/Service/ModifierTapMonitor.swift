import AppKit
import Carbon.HIToolbox

/// C entry point: reduce to Sendable scalars, then cross in. Listen-only, so nothing changes.
private func modifierTapEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<ModifierTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { monitor.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    // macOS follows a bare Globe release with key-down 179; it is not a separate key press.
    if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 179 {
        return Unmanaged.passUnretained(event)
    }
    let isFlagsChanged = type == .flagsChanged
    let flagsRaw = event.flags.rawValue
    let keyCode = isFlagsChanged ? Int(event.getIntegerValueField(.keyboardEventKeycode)) : 0
    MainActor.assumeIsolated {
        monitor.process(isFlagsChanged: isFlagsChanged, flagsRaw: flagsRaw, keyCode: keyCode)
    }
    return Unmanaged.passUnretained(event)
}

/// The listen-only modifier tap. See docs/features/hotkeys.md#modifier-only-shortcuts.
@MainActor
@Observable
final class ModifierTapMonitor: HealthCheckable {
    /// True while something is bound and the tap can't be created; the recorder surfaces it.
    private(set) var needsAccessibility = false

    /// Fired on the second release, so the modifier is up by the time the action runs.
    @ObservationIgnored var onDoubleTap: ((DoubleTapModifier) -> Void)?
    @ObservationIgnored var onGlobeTap: ((GlobeTapDetector.Gesture) -> Void)?

    /// Set while a recorder captures, so editing a binding can't trigger it.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            resetDetectors()
        }
    }

    private var bound: Set<DoubleTapModifier> = []
    private var singleGlobeBound = false
    private var doubleGlobeBound = false
    /// Advanced by the tap callback on every modifier transition; released by teardown.
    @ObservationIgnored private var doubleTapDetector = DoubleTapDetector()
    @ObservationIgnored private var globeDetector = GlobeTapDetector()
    @ObservationIgnored private var pendingSingleGlobe: Task<Void, Never>?
    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var sessionTokens: [NotificationToken] = []
    private var sessionActive = true
    private var loggedTapFailure = false

    @ObservationIgnored weak var healthTicker: HealthTicker?

    // The tap holds an unretained `self`, so it must not outlive it.
    isolated deinit {
        tearDownTap()
    }

    func start() {
        installObserversIfNeeded()
        syncTapPresence()
    }

    /// Modifiers currently carrying a binding; an empty set tears the tap down entirely.
    func update(
        bound: Set<DoubleTapModifier>, singleGlobeBound: Bool, doubleGlobeBound: Bool
    ) {
        guard
            bound != self.bound || singleGlobeBound != self.singleGlobeBound
                || doubleGlobeBound != self.doubleGlobeBound
        else { return }
        self.bound = bound
        self.singleGlobeBound = singleGlobeBound
        self.doubleGlobeBound = doubleGlobeBound
        resetDetectors()
        syncTapPresence()
    }

    // MARK: - Detection

    fileprivate func process(isFlagsChanged: Bool, flagsRaw: UInt64, keyCode: Int) {
        guard !isPaused else { return }
        let flags = CGEventFlags(rawValue: flagsRaw)
        let modifiers = isFlagsChanged ? Self.modifiers(in: flags) : []
        if isFlagsChanged {
            let isGlobeKey = keyCode == kVK_Function
            let hasOtherModifiers = !modifiers.isEmpty
            if !isGlobeKey || hasOtherModifiers { cancelPendingSingleGlobe() }
            if singleGlobeBound || doubleGlobeBound,
                let gesture = globeDetector.handle(
                    isGlobeKey: isGlobeKey,
                    functionDown: flags.contains(.maskSecondaryFn),
                    hasOtherModifiers: hasOtherModifiers,
                    at: ProcessInfo.processInfo.systemUptime)
            {
                handleGlobe(gesture)
            }
        } else {
            globeDetector.cancel()
            cancelPendingSingleGlobe()
        }
        guard !bound.isEmpty else { return }
        let input: DoubleTapDetector.Input =
            isFlagsChanged
            ? .modifiers(
                modifiers, hasOtherModifiers: Self.hasOtherModifiers(in: flags))
            : .otherInput
        // `systemUptime` is monotonic, so a wall-clock adjustment can't turn a tap into a hold.
        guard
            let modifier = doubleTapDetector.handle(
                input, at: ProcessInfo.processInfo.systemUptime),
            bound.contains(modifier)
        else { return }
        onDoubleTap?(modifier)
    }

    private func handleGlobe(_ gesture: GlobeTapDetector.Gesture) {
        switch gesture {
        case .single:
            guard singleGlobeBound else { return }
            guard doubleGlobeBound else {
                globeDetector.cancel()
                onGlobeTap?(.single)
                return
            }
            if pendingSingleGlobe != nil {
                cancelPendingSingleGlobe()
                onGlobeTap?(.single)
            }
            pendingSingleGlobe = Task { [weak self] in
                try? await Task.sleep(for: GlobeTapDetector.resolutionWindow)
                guard !Task.isCancelled, let self else { return }
                self.pendingSingleGlobe = nil
                guard !self.isPaused, self.sessionActive, self.singleGlobeBound else { return }
                self.onGlobeTap?(.single)
            }
        case .double:
            cancelPendingSingleGlobe()
            if doubleGlobeBound { onGlobeTap?(.double) }
        }
    }

    private func cancelPendingSingleGlobe() {
        pendingSingleGlobe?.cancel()
        pendingSingleGlobe = nil
    }

    private func resetDetectors() {
        doubleTapDetector.reset()
        globeDetector.cancel()
        cancelPendingSingleGlobe()
    }

    private static func modifiers(in flags: CGEventFlags) -> Set<DoubleTapModifier> {
        var held: Set<DoubleTapModifier> = []
        if flags.contains(.maskControl) { held.insert(.control) }
        if flags.contains(.maskAlternate) { held.insert(.option) }
        if flags.contains(.maskShift) { held.insert(.shift) }
        if flags.contains(.maskCommand) { held.insert(.command) }
        return held
    }

    // Never `maskAlphaShift`: it tracks the latch, killing every tap while Caps Lock is on.
    private static func hasOtherModifiers(in flags: CGEventFlags) -> Bool {
        flags.contains(.maskSecondaryFn)
    }

    // MARK: - Tap lifecycle

    private func installObserversIfNeeded() {
        guard sessionTokens.isEmpty else { return }
        // Fast user switching: another session owns the keyboard, so stop watching.
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidChange(active: false) }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidChange(active: true) }
                }, center: center)
        ]
    }

    private func sessionDidChange(active: Bool) {
        sessionActive = active
        resetDetectors()
        syncTapPresence()
    }

    private func syncTapPresence() {
        guard !bound.isEmpty || singleGlobeBound || doubleGlobeBound, sessionActive else {
            tearDownTap()
            healthTicker?.unsubscribe(self)
            needsAccessibility = false
            return
        }
        healthTicker?.subscribe(self)
        installTapIfNeeded()
    }

    private func installTapIfNeeded() {
        guard tapPort == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                // Appended, so `HyperKeyTap`'s rewrite lands first. See docs/features/hotkeys.md.
                place: .tailAppendEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: modifierTapEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            // Even a listen-only tap needs Accessibility; the health timer retries until granted.
            if !loggedTapFailure {
                NSLog("Tinycast: Failed to create modifier event tap")
                loggedTapFailure = true
            }
            needsAccessibility = true
            return
        }
        loggedTapFailure = false
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        needsAccessibility = false
    }

    private func tearDownTap() {
        resetDetectors()
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

    /// Called when the system disables the tap; any half-tracked press is stale by then.
    fileprivate func tapWasDisabled() {
        resetDetectors()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    /// One-second watchdog while something is bound. See docs/features/hotkeys.md#lifecycle.
    func healthCheck() {
        guard !bound.isEmpty || singleGlobeBound || doubleGlobeBound, sessionActive else {
            return
        }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
            needsAccessibility = true
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
    }
}
