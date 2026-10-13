import AppKit
import Carbon.HIToolbox

/// Local monitors for the one active recording. See docs/features/hotkeys.md#recorder.
@MainActor
@Observable
final class ShortcutCaptureSession {
    struct Conflict: Equatable {
        let binding: HotKeyBinding
        let owner: String
    }

    private(set) var heldModifiers: NSEvent.ModifierFlags = []
    private(set) var heldGlobe = false
    private(set) var heldModifier: ModifierKey?
    private(set) var awaitingSecondModifier: ModifierKey?
    private(set) var conflict: Conflict?

    /// The applied Hyper route, read here too because Secure Input hides keystrokes from the tap.
    @ObservationIgnored var hyperRoute: HyperKeyRoute? {
        didSet { if hyperRoute != oldValue { hyperKeyDown = false } }
    }
    @ObservationIgnored private var hyperKeyDown = false

    private static let conflictDwell: Duration = .seconds(1.5)
    private static let chordModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var conflictReset: Task<Void, Never>?
    @ObservationIgnored private var modifierCommit: Task<Void, Never>?
    @ObservationIgnored private weak var activeRecorderView: NSView?
    /// The same recognizer the global monitor uses, so recording needs no tap and no grant.
    @ObservationIgnored private var detector = ModifierKeyDetector()

    func start(action: HotKeyAction, hotKeys: HotKeyManager) {
        stop()
        heldModifiers = NSEvent.modifierFlags.intersection(Self.chordModifiers)
        _ = detector.handle(
            ModifierKey.held(in: UInt64(NSEvent.modifierFlags.rawValue), globeDown: false),
            at: ProcessInfo.processInfo.systemUptime)
        detector.cancel()

        // Main-thread handlers that predate actor annotations; only Sendable pieces cross in.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self, weak hotKeys] event in
                let keyCode = Int(event.keyCode)
                let flags = event.modifierFlags
                MainActor.assumeIsolated {
                    guard let self, let hotKeys else { return }
                    self.handleKeyDown(
                        keyCode: keyCode, flags: flags, action: action,
                        hotKeys: hotKeys)
                }
                return nil  // always consume: no beeps, no leaking keys to the window
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyUp,
            handler: { [weak self] event in
                let keyCode = Int(event.keyCode)
                MainActor.assumeIsolated { self?.handleKeyUp(keyCode: keyCode) }
                return event
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self, weak hotKeys] event in
                let all = event.modifierFlags
                let keyCode = Int(event.keyCode)
                let timestamp = event.timestamp
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.heldModifiers = self.hyperized(all).intersection(Self.chordModifiers)
                    if keyCode == kVK_Function { self.heldGlobe = all.contains(.function) }
                    guard let hotKeys else { return }
                    self.handleModifiers(
                        all.rawValue,
                        at: timestamp, action: action,
                        hotKeys: hotKeys)
                }
                return event
            })
        {
            monitors.append(monitor)
        }

        // A click ends the recording then travels on, so one click can move to another row.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { @MainActor [weak self, weak hotKeys] event in
                guard self?.activeRecorderContains(event) != true else { return event }
                hotKeys?.recordingAction = nil
                return event
            })
        {
            monitors.append(monitor)
        }

        // Local monitors go quiet on resign key, so treat it as a cancel and unpause.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak hotKeys] _ in
            MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        conflictReset?.cancel()
        conflictReset = nil
        cancelModifierCommit()
        conflict = nil
        heldModifiers = []
        heldGlobe = false
        heldModifier = nil
        hyperKeyDown = false
        detector.reset()
        activeRecorderView = nil
    }

    func setActiveRecorderView(_ view: NSView) {
        activeRecorderView = view
    }

    func clearActiveRecorderView(_ view: NSView) {
        if activeRecorderView === view { activeRecorderView = nil }
    }

    private func activeRecorderContains(_ event: NSEvent) -> Bool {
        guard let view = activeRecorderView, event.window === view.window else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }

    private func handleKeyDown(
        keyCode: Int, flags: NSEvent.ModifierFlags,
        action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        // A key press makes any modifier held at the moment part of a combo, not a tap.
        detector.cancel()
        cancelModifierCommit()
        if isHyperKey(keyCode) {
            hyperKeyDown = true
            heldModifiers = hyperized(flags).intersection(Self.chordModifiers)
            return
        }

        // F-keys also carry `.function`; only the physical Globe press makes it a modifier.
        let flags = hyperized(heldGlobe ? flags.union(.function) : flags.subtracting(.function))
        let bareKey = flags.isDisjoint(with: [.command, .option, .control, .shift, .function])

        if bareKey, keyCode == kVK_Escape {
            hotKeys.recordingAction = nil
            return
        }
        if bareKey, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            hotKeys.setBinding(nil, for: action)
            hotKeys.recordingAction = nil
            return
        }
        // Not a bindable combo (e.g. a bare letter): swallow it and keep recording.
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags) else { return }
        commit(.combo(shortcut), action: action, hotKeys: hotKeys)
    }

    private func handleKeyUp(keyCode: Int) {
        guard isHyperKey(keyCode) else { return }
        hyperKeyDown = false
        heldModifiers = NSEvent.modifierFlags.intersection(Self.chordModifiers)
    }

    private func isHyperKey(_ keyCode: Int) -> Bool {
        guard let hyperRoute else { return false }
        return hyperRoute.modifier == nil && keyCode == hyperRoute.tapKeyCode
    }

    private func hyperized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        guard let hyperRoute, let chord = KeyShortcut.displayedHyperChord(),
            hyperKeyDown || hyperRoute.modifier?.isHeld(in: UInt64(flags.rawValue)) == true
        else { return flags }
        let own = hyperRoute.key.ownFlag.map { NSEvent.ModifierFlags(rawValue: UInt($0.rawValue)) }
        return flags.subtracting(own ?? []).union(chord)
    }

    private func handleModifiers(
        _ flags: UInt, at timestamp: TimeInterval,
        action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        let keys = ModifierKey.held(in: UInt64(flags), globeDown: heldGlobe)
        heldModifier = keys.count == 1 ? keys.first : nil
        guard let event = detector.handle(keys, at: timestamp) else { return }
        switch event {
        case .pressed(let key):
            if key != awaitingSecondModifier { cancelModifierCommit() }
        case .released(let key, let doubleTap, let held):
            cancelModifierCommit()
            if doubleTap || held {
                commit(
                    doubleTap ? key.doubleBinding : key.singleBinding,
                    action: action, hotKeys: hotKeys)
                return
            }
            awaitingSecondModifier = key
            modifierCommit = Task { [weak self, weak hotKeys] in
                try? await Task.sleep(for: ModifierKeyDetector.resolutionWindow)
                guard !Task.isCancelled, let self, let hotKeys else { return }
                modifierCommit = nil
                awaitingSecondModifier = nil
                commit(key.singleBinding, action: action, hotKeys: hotKeys)
            }
        case .cancelled:
            cancelModifierCommit()
        }
    }

    private func cancelModifierCommit() {
        modifierCommit?.cancel()
        modifierCommit = nil
        awaitingSecondModifier = nil
    }

    private func commit(_ binding: HotKeyBinding, action: HotKeyAction, hotKeys: HotKeyManager) {
        if let owner = hotKeys.conflictOwner(of: binding, excluding: action) {
            flashConflict(Conflict(binding: binding, owner: owner))
            return
        }
        hotKeys.setBinding(binding, for: action)
        hotKeys.recordingAction = nil
    }

    private func flashConflict(_ rejected: Conflict) {
        conflict = rejected
        conflictReset?.cancel()
        conflictReset = Task { [weak self] in
            try? await Task.sleep(for: Self.conflictDwell)
            guard !Task.isCancelled else { return }
            self?.conflict = nil
        }
    }
}
