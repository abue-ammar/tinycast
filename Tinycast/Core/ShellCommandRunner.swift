import Darwin
import Foundation

enum ShellCommandOutcome: Sendable, Equatable {
    case success
    case launchFailure(String)
    case nonZeroExit(status: Int32, stderr: String?)
}

enum ShellCommandRunner {
    private static let stderrLimit = 8 * 1024

    nonisolated static func run(_ command: String) async -> ShellCommandOutcome {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
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
        }.value
    }

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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
