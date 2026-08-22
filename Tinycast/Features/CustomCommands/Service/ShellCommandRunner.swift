import Darwin
import Foundation

enum ShellCommandOutcome: Sendable, Equatable {
    case success
    case launchFailure(String)
    case nonZeroExit(status: Int32, stderr: String?)
}

enum ShellCommandRunner {
    private static let stderrLimit = 8 * 1024
    /// `waitUntilExit` blocks, so it stays off the cooperative pool; concurrent, not serial.
    private static let queue = DispatchQueue(
        label: "com.tinycast.shell-command", qos: .userInitiated, attributes: .concurrent)

    /// Defaults to the fast path, so forgetting it gets the cheap shell, not the config.
    nonisolated static func run(
        _ command: String, loadingShellEnvironment: Bool = false
    ) async -> ShellCommandOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(
                    returning: execute(command, loadingShellEnvironment: loadingShellEnvironment))
            }
        }
    }

    nonisolated private static func execute(
        _ command: String, loadingShellEnvironment: Bool
    ) -> ShellCommandOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // zsh reads `.zshrc` only for interactive shells, so `-l` alone sees no aliases.
        process.arguments = [loadingShellEnvironment ? "-il" : "-l", "+m", "-c", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        // Lets a shell config skip slow sections when Tinycast is the caller.
        process.environment = ProcessInfo.processInfo.environment.merging(["TINYCAST": "1"]) { _, new in
            new
        }
        // Load-bearing: a config that prompts reads EOF and moves on, never hanging.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        let capture = makeStderrCapture()
        process.standardError = capture?.handle ?? FileHandle.nullDevice
        defer { capture?.remove() }

        do {
            try process.run()
        } catch {
            return .launchFailure(error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            return .nonZeroExit(
                status: process.terminationStatus,
                stderr: capture?.readSuffix(limit: stderrLimit))
        }
        return .success
    }

    /// Immutable, confined to one `execute` on `queue`, and only read after `waitUntilExit`.
    private final class StderrCapture: @unchecked Sendable {
        let url: URL
        let handle: FileHandle

        init(url: URL, handle: FileHandle) {
            self.url = url
            self.handle = handle
        }

        func readSuffix(limit: Int) -> String? {
            try? handle.synchronize()
            guard let end = try? handle.seekToEnd() else { return nil }
            let start = end > UInt64(limit) ? end - UInt64(limit) : 0
            try? handle.seek(toOffset: start)
            guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
            return String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        func remove() {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func makeStderrCapture() -> StderrCapture? {
        let template = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-command-stderr.XXXXXX").path
        var bytes = Array(template.utf8CString)
        let descriptor = bytes.withUnsafeMutableBufferPointer { buffer in
            mkstemp(buffer.baseAddress!)
        }
        guard descriptor >= 0 else { return nil }
        let path = String(
            decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return StderrCapture(
            url: URL(fileURLWithPath: path),
            handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
