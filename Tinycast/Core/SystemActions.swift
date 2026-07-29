import Carbon.HIToolbox
import CoreGraphics
import IOKit.pwr_mgt

enum SystemAction: Sendable {
    case lockScreen
    case sleep
}

enum SystemActionResult: Equatable, Sendable {
    case success
    case permissionDenied
    case systemFailure
}

enum SystemActions {
    @discardableResult
    static func perform(_ action: SystemAction) -> SystemActionResult {
        perform(action, lockScreen: postLockScreenShortcut, sleep: requestSystemSleep)
    }

    /// Injectable handlers keep command routing testable without locking or sleeping the test Mac.
    @discardableResult
    static func perform(
        _ action: SystemAction,
        lockScreen: () -> SystemActionResult,
        sleep: () -> SystemActionResult
    ) -> SystemActionResult {
        switch action {
        case .lockScreen: return lockScreen()
        case .sleep: return sleep()
        }
    }

    private static func postLockScreenShortcut() -> SystemActionResult {
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            return .permissionDenied
        }
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: true),
            let keyUp = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: false)
        else { return .systemFailure }

        let flags: CGEventFlags = [.maskControl, .maskCommand]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .success
    }

    private static func requestSystemSleep() -> SystemActionResult {
        let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connection != 0 else { return .systemFailure }
        defer { IOServiceClose(connection) }
        return IOPMSleepSystem(connection) == kIOReturnSuccess ? .success : .systemFailure
    }
}
