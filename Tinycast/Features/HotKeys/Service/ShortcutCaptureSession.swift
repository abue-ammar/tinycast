import AppKit
import Carbon.HIToolbox

/// Local monitors for the one active recording. See docs/features/hotkeys.md#recorder.
@MainActor
@Observable
final class ShortcutCaptureSession {
    /// A rejected binding and whoever already holds it.
    struct Conflict: Equatable {
        let binding: HotKeyBinding
        let owner: String
    }

    private(set) var heldModifiers: NSEvent.ModifierFlags = []
    private(set) var heldGlobe = false
    private(set) var heldModifier: ModifierKey?
    private(set) var awaitingSecondModifier: ModifierKey?
    private(set) var conflict: Conflict?

    private static let conflictDwell: Duration = .seconds(1.5)

    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var conflictReset: Task<Void, Never>?
    @ObservationIgnored private var modifierCommit: Task<Void, Never>?
    @ObservationIgnored private weak var activeRecorderView: NSView?
    @ObservationIgnored private weak var activeCalloutView: NSView?
    /// The same recognizer the global monitor uses, so recording needs no tap and no grant.
    @ObservationIgnored private var detector = ModifierKeyDetector()

    func start(action: HotKeyAction, hotKeys: HotKeyManager) {
        stop()
        heldModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
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
            matching: .flagsChanged,
            handler: { [weak self, weak hotKeys] event in
                let all = event.modifierFlags
                let keyCode = Int(event.keyCode)
                let flags = all.intersection([.command, .option, .control, .shift])
                let timestamp = event.timestamp
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.heldModifiers = flags
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
                guard let self else { return event }
                self.detector.cancel()
                self.cancelModifierCommit()
                guard !self.activeRecorderContains(event), !self.activeCalloutContains(event)
                else { return event }
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
        detector.reset()
        activeRecorderView = nil
        activeCalloutView = nil
    }

    func setActiveRecorderView(_ view: NSView) {
        activeRecorderView = view
    }

    func clearActiveRecorderView(_ view: NSView) {
        if activeRecorderView === view { activeRecorderView = nil }
    }

    func setActiveCalloutView(_ view: NSView) {
        activeCalloutView = view
    }

    func clearActiveCalloutView(_ view: NSView) {
        if activeCalloutView === view { activeCalloutView = nil }
    }

    func updateShortcut(_ shortcut: KeyShortcut, action: HotKeyAction, hotKeys: HotKeyManager) {
        commit(.combo(shortcut), action: action, hotKeys: hotKeys, keepRecording: true)
    }

    private func activeCalloutContains(_ event: NSEvent) -> Bool {
        guard let view = activeCalloutView, event.window === view.window else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
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

        // F-keys also carry `.function`; only the physical Globe press makes it a modifier.
        let flags = heldGlobe ? flags.union(.function) : flags.subtracting(.function)
        let bareKey = flags.isDisjoint(with: [.command, .option, .control, .shift, .function])

        if bareKey, keyCode == kVK_Escape {
            hotKeys.recordingAction = nil
            return
        }
        // Plain Delete clears the existing binding.
        if bareKey, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            hotKeys.setBinding(nil, for: action)
            hotKeys.recordingAction = nil
            return
        }
        // Not a bindable combo (e.g. a bare letter): swallow it and keep recording.
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags) else { return }
        commit(.combo(shortcut), action: action, hotKeys: hotKeys, keepRecording: true)
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

    private func commit(
        _ binding: HotKeyBinding, action: HotKeyAction, hotKeys: HotKeyManager,
        keepRecording: Bool = false
    ) {
        if let owner = hotKeys.conflictOwner(of: binding, excluding: action) {
            flashConflict(Conflict(binding: binding, owner: owner))
            return
        }
        hotKeys.setBinding(binding, for: action)
        conflictReset?.cancel()
        conflictReset = nil
        conflict = nil
        if !keepRecording { hotKeys.recordingAction = nil }
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
