import AppKit
import Carbon.HIToolbox

private func snippetKeywordCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let listener = Unmanaged<SnippetKeywordListener>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { listener.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    // A click relocates the caret, so the buffered prefix no longer describes what precedes it.
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        MainActor.assumeIsolated {
            listener.userActivity()
            listener.clearBuffer()
        }
        return Unmanaged.passUnretained(event)
    }

    let eventUserData = event.getIntegerValueField(.eventSourceUserData)
    let secureEventInputEnabled = IsSecureEventInputEnabled()
    let typeRaw = type.rawValue
    let flagsRaw = event.flags.rawValue
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    var length = 0
    var characters = [UniChar](repeating: 0, count: 16)
    event.keyboardGetUnicodeString(
        maxStringLength: characters.count,
        actualStringLength: &length,
        unicodeString: &characters)
    let text = length > 0 ? String(utf16CodeUnits: characters, count: length) : nil

    MainActor.assumeIsolated {
        listener.processEvent(
            typeRaw: typeRaw,
            keyCode: keyCode,
            flagsRaw: flagsRaw,
            text: text,
            eventUserData: eventUserData,
            secureEventInputEnabled: secureEventInputEnabled)
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
protocol SnippetKeywordTapControlling: AnyObject {
    var state: SnippetKeywordLifecyclePolicy.TapState { get }
    func install(listener: SnippetKeywordListener) -> Bool
    func reenable() -> Bool
    func tearDown()
}

@MainActor
private final class SystemSnippetKeywordTapController: SnippetKeywordTapControlling {
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var state: SnippetKeywordLifecyclePolicy.TapState {
        guard let tapPort else { return .absent }
        return CGEvent.tapIsEnabled(tap: tapPort) ? .active : .disabled
    }

    func install(listener: SnippetKeywordListener) -> Bool {
        guard tapPort == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: snippetKeywordCallback,
                userInfo: Unmanaged.passUnretained(listener).toOpaque())
        else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }

        tapPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    func reenable() -> Bool {
        guard let tapPort else { return false }
        CGEvent.tapEnable(tap: tapPort, enable: true)
        return CGEvent.tapIsEnabled(tap: tapPort)
    }

    func tearDown() {
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
}

@MainActor
@Observable
final class SnippetKeywordListener: HealthCheckable {
    typealias Status = SnippetKeywordListenerStatus

    private(set) var status: Status = .off

    @ObservationIgnored weak var healthTicker: HealthTicker?

    @ObservationIgnored private var observers: [NotificationToken] = []
    /// The keystroke buffer: the tap callback mutates it per event, so it stays untracked.
    @ObservationIgnored private var policy = SnippetKeywordPolicy()
    @ObservationIgnored private var onUserActivity: (() -> Void)?
    @ObservationIgnored
    private var onMatch: ((StoredSnippet.ID, String, Int, NSRunningApplication?) -> Void)?
    private var sessionActive = true
    private var loggedTapFailure = false

    private let tapController: any SnippetKeywordTapControlling
    private let accessibilityTrusted: () -> Bool
    private let secureEventInputEnabled: () -> Bool
    private let now: () -> Date
    private let syntheticEventTag: Int64
    private let logsTapFailures: Bool

    init(
        tapController: (any SnippetKeywordTapControlling)? = nil,
        accessibilityTrusted: @escaping () -> Bool = AXIsProcessTrusted,
        secureEventInputEnabled: @escaping () -> Bool = IsSecureEventInputEnabled,
        now: @escaping () -> Date = Date.init,
        syntheticEventTag: Int64,
        logsTapFailures: Bool = true
    ) {
        self.tapController = tapController ?? SystemSnippetKeywordTapController()
        self.accessibilityTrusted = accessibilityTrusted
        self.secureEventInputEnabled = secureEventInputEnabled
        self.now = now
        self.syntheticEventTag = syntheticEventTag
        self.logsTapFailures = logsTapFailures
    }

    func update(_ records: [StoredSnippet]) {
        policy.update(
            records.compactMap { record in
                guard record.snippet.isEnabled, let keyword = record.snippet.keyword else { return nil }
                return SnippetKeywordPolicy.Keyword(snippetID: record.id, value: keyword)
            })
    }

    func start(
        onUserActivity: @escaping () -> Void,
        onMatch: @escaping (StoredSnippet.ID, String, Int, NSRunningApplication?) -> Void
    ) {
        self.onUserActivity = onUserActivity
        self.onMatch = onMatch
        installObserversIfNeeded()
        healthTicker?.subscribe(self)
        syncTapPresence()
    }

    func stop() {
        onUserActivity = nil
        onMatch = nil
        healthTicker?.unsubscribe(self)
        observers.removeAll()
        policy.reset()
        tapController.tearDown()
        sessionActive = true
        status = .off
    }

    func clearBuffer() {
        policy.reset()
    }

    /// A keystroke Tinycast did not synthesize means the caret is the reader's again, not ours.
    fileprivate func userActivity() {
        onUserActivity?()
    }

    func healthCheck() {
        if secureEventInputEnabled() { policy.reset() }
        syncTapPresence()
    }

    private var isRequested: Bool { onMatch != nil }

    /// A listen-only tap needs the Accessibility grant and nothing else.
    private var hasAccessibility: Bool { accessibilityTrusted() }

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clearBuffer() }
                },
                center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidResign() }
                },
                center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidBecomeActive() }
                },
                center: center)
        ]
    }

    private func syncTapPresence() {
        let decision = lifecycleDecision()
        switch decision.tapAction {
        // Nothing moved, so the decision still describes the tap: don't pay for a second one.
        case .none:
            status = decision.status
            return
        case .install:
            installTapIfNeeded()
        case .reenable:
            reenableTap()
        case .tearDown:
            policy.reset()
            tapController.tearDown()
        }
        status = lifecycleDecision().status
    }

    private func installTapIfNeeded() {
        guard tapController.state == .absent,
            isRequested,
            sessionActive,
            hasAccessibility
        else { return }
        guard tapController.install(listener: self) else {
            if !loggedTapFailure {
                if logsTapFailures {
                    NSLog("Tinycast: Failed to create snippet keyword event tap")
                }
                loggedTapFailure = true
            }
            return
        }
        loggedTapFailure = false
    }

    private func lifecycleDecision() -> SnippetKeywordLifecyclePolicy.Decision {
        SnippetKeywordLifecyclePolicy.decide(
            isRequested: isRequested,
            isSessionActive: sessionActive,
            hasAccessibility: accessibilityTrusted(),
            tapState: tapController.state)
    }

    private func reenableTap() {
        policy.reset()
        guard tapController.reenable() else {
            tapController.tearDown()
            installTapIfNeeded()
            return
        }
    }

    fileprivate func tapWasDisabled() {
        policy.reset()
        syncTapPresence()
    }

    private func sessionDidResign() {
        sessionActive = false
        policy.reset()
        syncTapPresence()
    }

    private func sessionDidBecomeActive() {
        sessionActive = true
        policy.reset()
        syncTapPresence()
    }

    func processEvent(
        typeRaw: UInt32,
        keyCode: Int,
        flagsRaw: UInt64,
        text: String?,
        eventUserData: Int64,
        secureEventInputEnabled: Bool
    ) {
        guard isRequested, status == .active else { return }
        let flags = CGEventFlags(rawValue: flagsRaw)
        let input = SnippetKeywordPolicy.classifyInput(
            text: text,
            isSynthetic: eventUserData == syntheticEventTag,
            secureEventInputEnabled: secureEventInputEnabled,
            isFlagsChanged: typeRaw == CGEventType.flagsChanged.rawValue,
            isKeyDown: typeRaw == CGEventType.keyDown.rawValue,
            hasCommandOrControl: flags.contains(.maskCommand) || flags.contains(.maskControl),
            isResetKey: Self.resetKeyCodes.contains(keyCode),
            isDeleteBackward: keyCode == kVK_Delete)
        if input != .ignored { onUserActivity?() }
        guard let match = policy.process(input, at: now()) else { return }
        onMatch?(
            match.snippetID,
            match.keyword,
            match.deletionCount,
            NSWorkspace.shared.frontmostApplication)
    }

    private static let resetKeyCodes: Set<Int> = [
        kVK_Return,
        kVK_ANSI_KeypadEnter,
        kVK_Escape,
        kVK_Tab,
        kVK_LeftArrow,
        kVK_RightArrow,
        kVK_UpArrow,
        kVK_DownArrow,
        kVK_Home,
        kVK_End,
        kVK_PageUp,
        kVK_PageDown,
        kVK_ForwardDelete
    ]
}
