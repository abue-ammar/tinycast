import AppKit
import Carbon.HIToolbox

enum SideModifier: String, CaseIterable, Codable, Hashable, Sendable {
    case leftControl, rightControl
    case leftOption, rightOption
    case leftShift, rightShift
    case leftCommand, rightCommand

    init?(keyCode: Int) {
        switch keyCode {
        case kVK_Control: self = .leftControl
        case kVK_RightControl: self = .rightControl
        case kVK_Option: self = .leftOption
        case kVK_RightOption: self = .rightOption
        case kVK_Shift: self = .leftShift
        case kVK_RightShift: self = .rightShift
        case kVK_Command: self = .leftCommand
        case kVK_RightCommand: self = .rightCommand
        default: return nil
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .leftControl, .rightControl: .control
        case .leftOption, .rightOption: .option
        case .leftShift, .rightShift: .shift
        case .leftCommand, .rightCommand: .command
        }
    }

    var symbol: String {
        switch self {
        case .leftControl: "L⌃"
        case .rightControl: "R⌃"
        case .leftOption: "L⌥"
        case .rightOption: "R⌥"
        case .leftShift: "L⇧"
        case .rightShift: "R⇧"
        case .leftCommand: "L⌘"
        case .rightCommand: "R⌘"
        }
    }
}

struct SideModifierRequirement: Hashable, Codable, Sendable {
    let modifiers: Set<SideModifier>

    init(_ modifiers: Set<SideModifier>) {
        self.modifiers = modifiers
    }

    var modifierFlags: NSEvent.ModifierFlags {
        modifiers.reduce(into: []) { $0.insert($1.modifierFlag) }
    }

    func symbols(for flag: NSEvent.ModifierFlags) -> [String] {
        SideModifier.allCases
            .filter { modifiers.contains($0) && $0.modifierFlag == flag }
            .map(\.symbol)
    }
}

struct SideModifierState: Sendable {
    private(set) var pressedModifiers: Set<SideModifier> = []

    mutating func handleFlagsChanged(keyCode: Int) {
        guard let modifier = SideModifier(keyCode: keyCode) else { return }
        if pressedModifiers.contains(modifier) {
            pressedModifiers.remove(modifier)
        } else {
            pressedModifiers.insert(modifier)
        }
    }

    mutating func reset() {
        pressedModifiers = []
    }
}

private func sideHotKeyEventTapCallback(
    _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let matcher = Unmanaged<SideHotKeyMatcher>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let flagsRaw = event.flags.rawValue
    MainActor.assumeIsolated { matcher.handle(type: type, keyCode: keyCode, flagsRaw: flagsRaw) }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class SideHotKeyMatcher {
    private struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: () -> Void
    }

    private var entries: [String: Entry] = [:]
    private var state = SideModifierState()
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var started = false
    private var sessionTokens: [NotificationToken] = []

    var isPaused = false {
        didSet {
            if isPaused { state.reset() }
        }
    }

    func start() {
        guard !started else { return }
        started = true
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
        syncTapPresence()
    }

    func register(id: String, shortcut: KeyShortcut, onKeyDown: @escaping () -> Void) {
        entries[id] = Entry(shortcut: shortcut, onKeyDown: onKeyDown)
        syncTapPresence()
    }

    func unregister(id: String) {
        entries.removeValue(forKey: id)
        syncTapPresence()
    }

    fileprivate func handle(type: CGEventType, keyCode: Int, flagsRaw: UInt64) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            state.reset()
            if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
        case .flagsChanged:
            state.handleFlagsChanged(keyCode: keyCode)
        case .keyDown:
            guard !isPaused else { return }
            for entry in entries.values
            where Self.matches(
                entry.shortcut,
                keyCode: keyCode,
                modifierFlags: Self.modifierFlags(from: CGEventFlags(rawValue: flagsRaw)),
                pressedModifiers: state.pressedModifiers
            ) {
                entry.onKeyDown()
            }
        default:
            break
        }
    }

    static func matches(
        _ shortcut: KeyShortcut, keyCode: Int, modifierFlags: NSEvent.ModifierFlags,
        pressedModifiers: Set<SideModifier>
    ) -> Bool {
        guard
            shortcut.carbonKeyCode == keyCode,
            shortcut.carbonModifiers == KeyShortcut.carbonModifiers(from: modifierFlags),
            let requirements = shortcut.sideModifiers
        else { return false }
        return pressedModifiers == requirements.modifiers
    }

    private static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }

    private func installTapIfNeeded() {
        guard started, !entries.isEmpty, tapPort == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: sideHotKeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installTapIfNeeded() }
        }
    }

    private func syncTapPresence() {
        guard started, !entries.isEmpty else {
            stopHealthTimer()
            tearDownTap()
            return
        }
        startHealthTimer()
        installTapIfNeeded()
    }

    private func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func tearDownTap() {
        state.reset()
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

    private func sessionDidResign() {
        state.reset()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: false) }
    }

    private func sessionDidBecomeActive() {
        state.reset()
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        } else {
            installTapIfNeeded()
        }
    }
}
