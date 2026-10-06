import AppKit
import Carbon.HIToolbox

@MainActor
private func shortcutEventTapCallback(
    _: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ShortcutEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let flagsRaw = event.flags.rawValue
    let consumed = tap.process(type: type, keyCode: keyCode, flagsRaw: flagsRaw)
    return consumed ? nil : Unmanaged.passUnretained(event)
}

@MainActor
@Observable
final class ShortcutEventTap: HealthCheckable {
    struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: () -> Void
        var onKeyUp: (() -> Void)?
    }

    private(set) var needsAccessibility = false
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            heldGlobe = false
            releaseConsumedKeys()
        }
    }

    @ObservationIgnored weak var healthTicker: HealthTicker?
    @ObservationIgnored private var entries: [Entry] = []
    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var sessionTokens: [NotificationToken] = []
    private var sessionActive = true
    private var heldGlobe = false
    private var consumedKeys: [Int: Entry] = [:]
    private var loggedTapFailure = false

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    isolated deinit { tearDownTap() }

    func update(entries: [Entry]) {
        self.entries = entries
        installObserversIfNeeded()
        syncTapPresence()
    }

    func process(type: CGEventType, keyCode: Int, flagsRaw: UInt64) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            heldGlobe = false
            releaseConsumedKeys()
            if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
            return false
        }
        guard !isPaused, sessionActive else { return false }
        if type == .flagsChanged {
            if keyCode == kVK_Function {
                heldGlobe = CGEventFlags(rawValue: flagsRaw).contains(.maskSecondaryFn)
            }
            return false
        }
        if type == .keyUp {
            guard let entry = consumedKeys.removeValue(forKey: keyCode) else { return false }
            entry.onKeyUp?()
            return true
        }
        guard type == .keyDown else { return false }
        if consumedKeys[keyCode] != nil { return true }
        var flags = NSEvent.ModifierFlags(rawValue: UInt(flagsRaw))
        if !heldGlobe { flags.remove(.function) }
        for entry in entries where entry.shortcut.carbonModifiers == KeyShortcut.carbonModifiers(from: flags)
        {
            let character =
                entry.shortcut.keyEquivalent == nil
                ? nil
                : KeyShortcut.character(
                    for: keyCode, carbonModifiers: entry.shortcut.carbonModifiers)
            guard entry.shortcut.matches(keyCode: keyCode, modifierFlags: flags, character: character)
            else { continue }
            consumedKeys[keyCode] = entry
            entry.onKeyDown()
            return true
        }
        return false
    }

    private func installObserversIfNeeded() {
        guard !entries.isEmpty, sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.sessionDidChange(active: false) }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.sessionDidChange(active: true) }
                }, center: center)
        ]
    }

    private func sessionDidChange(active: Bool) {
        sessionActive = active
        syncTapPresence()
    }

    private func syncTapPresence() {
        guard !entries.isEmpty, sessionActive else {
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
            | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                eventsOfInterest: mask,
                callback: { @MainActor proxy, type, event, userInfo in
                    shortcutEventTapCallback(proxy, type: type, event: event, userInfo: userInfo)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            if !loggedTapFailure {
                NSLog("Tinycast: Failed to create detailed shortcut event tap")
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

    private func releaseConsumedKeys() {
        let consumed = consumedKeys.values
        consumedKeys = [:]
        for entry in consumed { entry.onKeyUp?() }
    }

    private func tearDownTap() {
        heldGlobe = false
        releaseConsumedKeys()
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

    func healthCheck() {
        guard !entries.isEmpty, sessionActive else { return }
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
