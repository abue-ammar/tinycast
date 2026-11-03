import AppKit
import Carbon.HIToolbox
import Synchronization

private func inlineEmojiCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<InlineEmojiListener.Session>.fromOpaque(userInfo).takeUnretainedValue()
    return session.handle(type, event)
}

@MainActor
@Observable
final class InlineEmojiListener: HealthCheckable {
    struct Version: Equatable, Sendable {
        let sessionID: UUID
        let revision: UInt64
    }

    struct Message: Sendable {
        let version: Version
        let effect: InlineEmojiPolicy.Effect
    }

    private(set) var isListening = false
    @ObservationIgnored private var port: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NotificationToken] = []
    private let healthTicker: HealthTicker

    init(healthTicker: HealthTicker) {
        self.healthTicker = healthTicker
    }

    func start(onMessage: @escaping @MainActor (Message) async -> Void) {
        guard session == nil else { return }
        let (stream, continuation) = AsyncStream<Message>.makeStream(bufferingPolicy: .bufferingNewest(32))
        let session = Session(continuation: continuation)
        self.session = session
        deliveryTask = Task {
            for await message in stream {
                guard !Task.isCancelled else { return }
                await onMessage(message)
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.didWakeNotification
        ].map { name in
            NotificationToken(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    switch name {
                    case NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification:
                        session.setSuspended(true)
                    case NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification:
                        session.setSuspended(false)
                    default: session.reset()
                    }
                },
                center: center)
        }
        healthTicker.subscribe(self)
        healthCheck()
    }

    func stop() {
        session?.finish()
        deliveryTask?.cancel()
        deliveryTask = nil
        observers.removeAll()
        healthTicker.unsubscribe(self)
        tearDownTap()
        session = nil
    }

    func reset() { session?.reset() }

    func isCurrent(_ version: Version) -> Bool { session?.isCurrent(version) == true }

    func setHasResults(_ hasResults: Bool, version: Version) {
        session?.setHasResults(hasResults, version: version)
    }

    func setPanelBounds(_ bounds: CGRect?) { session?.setPanelBounds(bounds) }

    func finishSelection(version: Version) { session?.finishSelection(version: version) }

    func healthCheck() {
        guard session != nil else { return }
        guard session?.isSuspended == false,
            Permissions.isAccessibilityTrusted(), !IsSecureEventInputEnabled()
        else {
            session?.reset()
            tearDownTap()
            return
        }
        if let port {
            if !CGEvent.tapIsEnabled(tap: port) {
                session?.reset()
                CGEvent.tapEnable(tap: port, enable: true)
            }
            isListening = CGEvent.tapIsEnabled(tap: port)
            return
        }
        installTap()
    }

    private func installTap() {
        guard let session else { return }
        let mask = [
            CGEventType.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel
        ].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard
            let port = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                options: .defaultTap, eventsOfInterest: mask,
                callback: inlineEmojiCallback,
                userInfo: Unmanaged.passUnretained(session).toOpaque())
        else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return
        }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isListening = CGEvent.tapIsEnabled(tap: port)
    }

    private func tearDownTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
        isListening = false
    }

    final class Session: Sendable {
        private struct State {
            var policy = InlineEmojiPolicy()
            var version: UInt64 = 0
            var hasResults = false
            var swallowedKeys: Set<Int64> = []
            var panelBounds: CGRect?
            var isSuspended = false
        }

        private let state = Mutex(State())
        private let id = UUID()
        private let continuation: AsyncStream<Message>.Continuation
        private let secureEventInputEnabled: @Sendable () -> Bool

        init(
            continuation: AsyncStream<Message>.Continuation,
            secureEventInputEnabled: @escaping @Sendable () -> Bool = { IsSecureEventInputEnabled() }
        ) {
            self.continuation = continuation
            self.secureEventInputEnabled = secureEventInputEnabled
        }

        func isCurrent(_ version: Version) -> Bool {
            version.sessionID == id && state.withLock { $0.version == version.revision }
        }

        var isSuspended: Bool { state.withLock { $0.isSuspended } }

        func setSuspended(_ suspended: Bool) {
            state.withLock { $0.isSuspended = suspended }
            reset()
        }

        func setHasResults(_ hasResults: Bool, version: Version) {
            guard version.sessionID == id else { return }
            state.withLock { if $0.version == version.revision { $0.hasResults = hasResults } }
        }

        func setPanelBounds(_ bounds: CGRect?) { state.withLock { $0.panelBounds = bounds } }

        func finishSelection(version: Version) {
            guard version.sessionID == id else { return }
            state.withLock {
                guard $0.version == version.revision else { return }
                $0.policy.reset()
                $0.hasResults = false
                $0.panelBounds = nil
            }
        }

        func reset() {
            state.withLock { state in
                state.version &+= 1
                state.policy.reset()
                state.hasResults = false
                state.panelBounds = nil
                continuation.yield(message(.dismiss, revision: state.version))
            }
        }

        func finish() {
            reset()
            continuation.finish()
        }

        func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
            let original = Unmanaged.passUnretained(event)
            guard event.getIntegerValueField(.eventSourceUserData) != Paster.tinycastEventTag else {
                return original
            }
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                reset()
                return original
            }
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if type == .keyUp {
                return state.withLock { $0.swallowedKeys.remove(key) != nil } ? nil : original
            }
            if type == .keyDown, key != kVK_UpArrow, key != kVK_DownArrow,
                event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                state.withLock({ $0.swallowedKeys.contains(key) })
            {
                return nil
            }
            let flags = event.flags
            if isSuspended || secureEventInputEnabled()
                || !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
            {
                reset()
                return original
            }
            guard type != .flagsChanged else { return original }
            guard type == .keyDown else {
                if !state.withLock({ $0.panelBounds?.contains(event.location) == true }) { reset() }
                return original
            }
            let input = Self.input(for: key, event: event)
            return state.withLock { state in
                let isNavigating: Bool
                if case .move = input {
                    isNavigating = state.policy.query != nil && state.hasResults
                } else {
                    isNavigating = false
                }
                if !isNavigating { state.version &+= 1 }
                let effectiveInput = input == .escape && state.panelBounds == nil ? .reset : input
                let decision = state.policy.process(effectiveInput, at: Date(), hasResults: state.hasResults)
                if let effect = decision.effect {
                    if !isNavigating { state.hasResults = false }
                    continuation.yield(message(effect, revision: state.version))
                } else if state.panelBounds != nil {
                    continuation.yield(message(.dismiss, revision: state.version))
                }
                if decision.consumesKey { state.swallowedKeys.insert(key) }
                return decision.consumesKey ? nil : original
            }
        }

        private func message(_ effect: InlineEmojiPolicy.Effect, revision: UInt64) -> Message {
            Message(version: Version(sessionID: id, revision: revision), effect: effect)
        }

        private static func input(for key: Int64, event: CGEvent) -> InlineEmojiPolicy.Input {
            switch Int(key) {
            case kVK_Delete: return .deleteBackward
            case kVK_UpArrow: return .move(-1)
            case kVK_DownArrow: return .move(1)
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab: return .accept
            case kVK_Escape: return .escape
            case kVK_LeftArrow, kVK_RightArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
                kVK_ForwardDelete:
                return .reset
            default:
                var length = 0
                var characters = [UniChar](repeating: 0, count: 16)
                event.keyboardGetUnicodeString(
                    maxStringLength: characters.count, actualStringLength: &length,
                    unicodeString: &characters)
                guard length > 0 else { return .reset }
                return .text(String(utf16CodeUnits: characters, count: length))
            }
        }
    }
}
