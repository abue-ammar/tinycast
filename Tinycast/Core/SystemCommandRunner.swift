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
    private struct ProcessOutput: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// What a command reports back once it succeeded. Only commands whose effect is otherwise invisible
    /// return one, since Show Desktop or Hide Others are their own confirmation.
    static func run(_ id: SystemCommand.ID, previousApp: NSRunningApplication?) async throws
        -> SystemCommandFeedback?
    {
        switch id {
        case .lockScreen:
            try postKey(keyCode: CGKeyCode(kVK_ANSI_Q), flags: [.maskControl, .maskCommand])
        case .sleep:
            try await runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .sleepDisplays:
            try await runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
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

    private static func runProcess(_ executable: String, arguments: [String]) async throws {
        let output = try await process(executable, arguments: arguments)
        guard output.status == 0 else { throw processFailure(output, executable: executable) }
    }

    private static func process(_ executable: String, arguments: [String]) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            do { try process.run() } catch {
                throw SystemCommandFailure("\(URL(fileURLWithPath: executable).lastPathComponent) could not start: \(error.localizedDescription)")
            }
            process.waitUntilExit()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessOutput(
                status: process.terminationStatus,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errorData, encoding: .utf8) ?? "")
        }.value
    }

    private static func processFailure(_ output: ProcessOutput, executable: String) -> SystemCommandFailure {
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return SystemCommandFailure(
            detail.isEmpty ? "\(name) exited with status \(output.status)." : detail)
    }
}
