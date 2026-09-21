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
    private(set) var awaitingSecondGlobe = false
    private(set) var conflict: Conflict?

    private static let conflictDwell: Duration = .seconds(1.5)

    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var conflictReset: Task<Void, Never>?
    @ObservationIgnored private var globeCommit: Task<Void, Never>?
    /// The same recognizer the global monitor uses, so recording needs no tap and no grant.
    @ObservationIgnored private var detector = DoubleTapDetector()
    @ObservationIgnored private var globeDetector = GlobeTapDetector()

    func start(action: HotKeyAction, hotKeys: HotKeyManager) {
        stop()
        heldModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])

        // Main-thread handlers that predate actor annotations; only Sendable pieces cross in.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self, weak hotKeys] event in
                let keyCode = Int(event.keyCode)
                let flags = event.modifierFlags
                let timestamp = event.timestamp
                MainActor.assumeIsolated {
                    guard let self, let hotKeys else { return }
                    self.handleKeyDown(
                        keyCode: keyCode, flags: flags, at: timestamp, action: action,
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
                // `.function` only: `.capsLock` is the latch, and would refuse every double-tap.
                let hasOthers = all.contains(.function)
                let timestamp = event.timestamp
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.heldModifiers = flags
                    if keyCode == kVK_Function { self.heldGlobe = all.contains(.function) }
                    guard let hotKeys else { return }
                    self.handleModifiers(
                        flags, isGlobeKey: keyCode == kVK_Function,
                        functionDown: all.contains(.function), hasOtherModifiers: hasOthers,
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
            handler: { [weak hotKeys] event in
                MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
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
        cancelGlobeCommit()
        conflict = nil
        heldModifiers = []
        heldGlobe = false
        detector.reset()
        globeDetector.cancel()
    }

    private func handleKeyDown(
        keyCode: Int, flags: NSEvent.ModifierFlags, at timestamp: TimeInterval,
        action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        // A key press makes any modifier held at the moment part of a combo, not a tap.
        _ = detector.handle(.otherInput, at: timestamp)
        cancelGlobeCommit()
        globeDetector.cancel()

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
        commit(.combo(shortcut), action: action, hotKeys: hotKeys)
    }

    private func handleModifiers(
        _ flags: NSEvent.ModifierFlags, isGlobeKey: Bool, functionDown: Bool,
        hasOtherModifiers: Bool, at timestamp: TimeInterval,
        action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        if !isGlobeKey { cancelGlobeCommit() }
        if let gesture = globeDetector.handle(
            isGlobeKey: isGlobeKey, functionDown: functionDown,
            hasOtherModifiers: !flags.isEmpty, at: timestamp)
        {
            switch gesture {
            case .single:
                if globeCommit != nil {
                    cancelGlobeCommit()
                    commit(.globe, action: action, hotKeys: hotKeys)
                } else {
                    awaitingSecondGlobe = true
                    globeCommit = Task { [weak self, weak hotKeys] in
                        try? await Task.sleep(for: GlobeTapDetector.resolutionWindow)
                        guard !Task.isCancelled, let self, let hotKeys else { return }
                        self.globeCommit = nil
                        self.awaitingSecondGlobe = false
                        self.commit(.globe, action: action, hotKeys: hotKeys)
                    }
                }
            case .double:
                cancelGlobeCommit()
                commit(.doubleGlobe, action: action, hotKeys: hotKeys)
            }
            return
        }
        // `NSEvent.timestamp` is the same monotonic basis `ModifierTapMonitor` feeds in.
        guard
            let modifier = detector.handle(
                .modifiers(Self.doubleTapModifiers(in: flags), hasOtherModifiers: hasOtherModifiers),
                at: timestamp)
        else { return }
        commit(.doubleTap(modifier), action: action, hotKeys: hotKeys)
    }

    private func cancelGlobeCommit() {
        globeCommit?.cancel()
        globeCommit = nil
        awaitingSecondGlobe = false
    }

    private static func doubleTapModifiers(
        in flags: NSEvent.ModifierFlags
    )
        -> Set<DoubleTapModifier>
    {
        var held: Set<DoubleTapModifier> = []
        if flags.contains(.control) { held.insert(.control) }
        if flags.contains(.option) { held.insert(.option) }
        if flags.contains(.shift) { held.insert(.shift) }
        if flags.contains(.command) { held.insert(.command) }
        return held
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
