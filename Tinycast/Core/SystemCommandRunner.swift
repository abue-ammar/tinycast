import AppKit
import Carbon
import CoreAudio
import Darwin

struct SystemCommandFailure: LocalizedError, Sendable {
    enum Settings: Sendable {
        case accessibility
        case automation
        case bluetooth
    }

    let message: String
    let settings: Settings?

    init(_ message: String, settings: Settings? = nil) {
        self.message = message
        self.settings = settings
    }

    var errorDescription: String? { message }
}

struct SystemCommandFeedback: Sendable {
    let title: String
    let symbol: String
    /// Set when the command found nothing to do; it reads as information rather than a completed change.
    let isNoOp: Bool

    init(_ title: String, symbol: String, isNoOp: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.isNoOp = isNoOp
    }
}

@MainActor
enum SystemCommandRunner {

    /// What a command reports back once it succeeded. Only commands whose effect is otherwise invisible
    /// return one, since Show Desktop or Hide Others are their own confirmation.
    static func run(_ id: SystemCommand.ID, previousApp: NSRunningApplication?) async throws
        -> SystemCommandFeedback?
    {
        switch id {
        case .lockScreen:
            try postKey(keyCode: CGKeyCode(kVK_ANSI_Q), flags: [.maskControl, .maskCommand])
        }
        return nil
    }

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard Permissions.ensureAccessibility() else {
            throw SystemCommandFailure(
                "Allow Tinycast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { throw SystemCommandFailure("macOS could not create the keyboard event.") }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

}
