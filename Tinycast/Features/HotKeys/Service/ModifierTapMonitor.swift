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
    let keyCode =
        type == .keyDown || isFlagsChanged
        ? Int(event.getIntegerValueField(.keyboardEventKeycode)) : -1
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

    /// Fired on the tap's final release, so the key is up by the time the action runs.
    @ObservationIgnored var onTrigger: ((HotKeyBinding) -> Void)?
    @ObservationIgnored var onHoldPressed: (() -> Void)?
    @ObservationIgnored var onHoldReleased: (() -> Void)?
    @ObservationIgnored var onHoldCancelled: (() -> Void)?

    /// Set while a recorder captures, so editing a binding can't trigger it.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            resetDetectors()
        }
    }

    private var bound: Set<HotKeyBinding> = []
    /// Advanced by the tap callback on every modifier transition; released by teardown.
    @ObservationIgnored private var doubleTapDetector = DoubleTapDetector()
    @ObservationIgnored private var modifierDetector = ModifierKeyDetector()
    @ObservationIgnored private var pendingSingle: Task<Void, Never>?
    @ObservationIgnored private var pendingHold: Task<Void, Never>?
    @ObservationIgnored private var pendingBinding: HotKeyBinding?
    private var globeDown = false
    private var holdKey: ModifierKey?
    private var holding = false
    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var sessionTokens: [NotificationToken] = []
    private var sessionActive = true
    private var loggedTapFailure = false

    @ObservationIgnored weak var healthTicker: HealthTicker?

    init(bound: Set<HotKeyBinding> = []) {
        self.bound = bound
    }

    // The tap holds an unretained `self`, so it must not outlive it.
    isolated deinit {
        tearDownTap()
    }

    func start() {
        installObserversIfNeeded()
        syncTapPresence()
    }

    /// Modifier-only bindings currently assigned; an empty set tears the tap down entirely.
    func update(bound: Set<HotKeyBinding>, holdKey: ModifierKey? = nil) {
        guard bound != self.bound || holdKey != self.holdKey else { return }
        self.bound = bound
        self.holdKey = holdKey
        resetDetectors()
        syncTapPresence()
    }

    // MARK: - Detection

    func process(isFlagsChanged: Bool, flagsRaw: UInt64, keyCode: Int) {
        guard !isPaused else { return }
        // `systemUptime` is monotonic, so a wall-clock adjustment can't turn a tap into a hold.
        let now = ProcessInfo.processInfo.systemUptime
        let input: DoubleTapDetector.Input
        if isFlagsChanged {
            let flags = CGEventFlags(rawValue: flagsRaw)
            let modifiers = Self.modifiers(in: flags)
            if keyCode == kVK_Function { globeDown = flags.contains(.maskSecondaryFn) }
            let keys = ModifierKey.held(in: flagsRaw, globeDown: globeDown)
            if let event = modifierDetector.handle(keys, at: now) {
                handleModifier(event)
            }
            input = .modifiers(modifiers, hasOtherModifiers: Self.hasOtherModifiers(in: flags))
        } else {
            // Return and Escape belong to the dictation panel while a hold is active.
            if holding,
                keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter
                    || keyCode == kVK_Escape
            {
                return
            }
            modifierDetector.cancel()
            cancelPendingSingle()
            cancelHold()
            input = .otherInput
        }
        guard let modifier = doubleTapDetector.handle(input, at: now),
            bound.contains(.doubleTap(modifier))
        else { return }
        cancelPendingSingle()
        onTrigger?(.doubleTap(modifier))
    }

    private func handleModifier(_ event: ModifierKeyDetector.Event) {
        switch event {
        case .pressed(let key):
            if let holdKey, key == holdKey {
                pendingHold = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(DoubleTapDetector.maxHold))
                    guard !Task.isCancelled, let self else { return }
                    pendingHold = nil
                    holding = true
                    onHoldPressed?()
                }
            } else if key.singleBinding != pendingBinding {
                cancelPendingSingle()
            }
        case .released(let key, let doubleTap, let held):
            if key == holdKey {
                pendingHold?.cancel()
                pendingHold = nil
                if holding {
                    holding = false
                    onHoldReleased?()
                }
                return
            }
            guard !held else { cancelPendingSingle(); return }
            if doubleTap, bound.contains(key.doubleBinding) {
                cancelPendingSingle()
                onTrigger?(key.doubleBinding)
            } else if bound.contains(key.singleBinding) {
                cancelPendingSingle()
                let hasDoubleTap =
                    bound.contains(key.doubleBinding)
                    || key.modifier.map { bound.contains(.doubleTap($0)) } == true
                guard hasDoubleTap else {
                    modifierDetector.cancel()
                    onTrigger?(key.singleBinding)
                    return
                }
                pendingBinding = key.singleBinding
                pendingSingle = Task { [weak self] in
                    try? await Task.sleep(for: ModifierKeyDetector.resolutionWindow)
                    guard !Task.isCancelled, let self else { return }
                    pendingSingle = nil
                    pendingBinding = nil
                    onTrigger?(key.singleBinding)
                }
            }
        case .cancelled:
            cancelPendingSingle()
            cancelHold()
        }
    }

    private func cancelPendingSingle() {
        pendingSingle?.cancel()
        pendingSingle = nil
        pendingBinding = nil
    }

    private func cancelHold() {
        pendingHold?.cancel()
        pendingHold = nil
        guard holding else { return }
        holding = false
        onHoldCancelled?()
    }

    private func resetDetectors() {
        doubleTapDetector.reset()
        modifierDetector.reset()
        globeDown = false
        cancelPendingSingle()
        cancelHold()
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
        guard !bound.isEmpty, sessionActive else {
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
        guard !bound.isEmpty, sessionActive else { return }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
            needsAccessibility = true
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            resetDetectors()
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
    }
}
