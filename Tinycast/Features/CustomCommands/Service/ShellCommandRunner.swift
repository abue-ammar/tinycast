import Darwin
import Foundation

/// How a run ended. `launchFailed` means the shell never started, so nothing was captured.
enum ShellCommandTermination: Sendable, Equatable {
    case exited(status: Int32)
    case launchFailed(String)
    /// The reader pressed Stop. Kept apart from the status, which a signalled shell reports as 143
    /// or 15 depending on what it was doing — neither of which is worth showing anyone.
    case stopped

    /// A signal death reports the signal as its status, so it fails here like any non-zero exit.
    var succeeded: Bool { self == .exited(status: 0) }
}

enum ShellCommandEvent: Sendable {
    case output(String)
    case finished(ShellCommandResult)
}

/// A command running now: what it is printing, and the handle that ends it. `stop` is deliberately
/// not the stream's cancellation — abandoning the events must never kill the reader's command.
struct ShellCommandSession: Sendable {
    let events: AsyncStream<ShellCommandEvent>
    let stop: @Sendable () -> Void
}

/// A finished run. `standardError` is the tail kept for the failure dialog, and only the
/// non-streaming path fills it — a streamed run reports everything through its events instead.
struct ShellCommandResult: Sendable, Equatable {
    let termination: ShellCommandTermination
    let standardError: String?

    var succeeded: Bool { termination.succeeded }

    init(termination: ShellCommandTermination, standardError: String? = nil) {
        self.termination = termination
        self.standardError = standardError
    }
}

enum ShellCommandRunner {
    /// Only ever surfaces on failure, where the last few lines are the whole story.
    private static let standardErrorLimit = 8 * 1024
    private static let shell = "/bin/zsh"
    /// Big enough that a chatty command needs few reads, small enough to stay live.
    private static let readSize = 16 * 1024
    /// Coalesces bursts so a flood cannot drive a redraw per line.
    private static let flushInterval: Duration = .milliseconds(40)
    /// A prompt or a progress bar never ends a line; past this it is shown anyway.
    private static let unlinedLimit = 4 * 1024
    /// How long a stopped command is given to leave politely before it is killed.
    private static let stopGrace: DispatchTimeInterval = .seconds(2)
    /// `waitUntilExit` blocks, so it stays off the cooperative pool; concurrent, not serial.
    private static let queue = DispatchQueue(
        label: "com.tinycast.shell-command", qos: .userInitiated, attributes: .concurrent)

    /// Fire-and-forget: nothing is kept but the error tail a failure dialog needs. A command whose
    /// output is shown goes through `stream` instead.
    nonisolated static func run(
        _ command: String, arguments: [String] = [], loadingShellEnvironment: Bool = false
    ) async -> ShellCommandResult {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(
                    returning: execute(
                        command, arguments: arguments,
                        loadingShellEnvironment: loadingShellEnvironment))
            }
        }
    }

    nonisolated private static func execute(
        _ command: String, arguments: [String], loadingShellEnvironment: Bool
    ) -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = shellArguments(
            command: command, arguments: arguments,
            loadingShellEnvironment: loadingShellEnvironment)
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        // Lets a shell config skip slow sections when Tinycast is the caller.
        process.environment = ProcessInfo.processInfo.environment.merging(["TINYCAST": "1"]) { _, new in
            new
        }
        // Load-bearing: a config that prompts reads EOF and moves on, never hanging.
        process.standardInput = FileHandle.nullDevice

        let errors = StreamCapture.make()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors?.handle ?? FileHandle.nullDevice
        defer { errors?.remove() }

        do {
            try process.run()
        } catch {
            return ShellCommandResult(termination: .launchFailed(error.localizedDescription))
        }
        process.waitUntilExit()

        return ShellCommandResult(
            termination: .exited(status: process.terminationStatus),
            standardError: errors?.readSuffix(limit: standardErrorLimit))
    }

    // MARK: - Streaming

    /// Runs the command under a pseudo-terminal and reports what it prints as it prints it.
    /// See `PseudoTerminal` for why a pipe cannot do this.
    nonisolated static func stream(
        _ command: String, arguments: [String] = [], loadingShellEnvironment: Bool = false
    ) -> ShellCommandSession {
        var environment = ProcessInfo.processInfo.environment
        environment["TINYCAST"] = "1"
        // A terminal makes tools colour their output; the window renders those codes rather than
        // showing them, so this asks for the colour it can draw and nothing fancier.
        environment["TERM"] = "xterm-256color"

        let terminal = PseudoTerminal.spawn(
            executable: shell,
            arguments: shellArguments(
                command: command, arguments: arguments,
                loadingShellEnvironment: loadingShellEnvironment),
            environment: environment,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path)

        guard let terminal else {
            return ShellCommandSession(
                events: AsyncStream { continuation in
                    continuation.yield(
                        .finished(
                            ShellCommandResult(
                                termination: .launchFailed("The shell could not be started."))))
                    continuation.finish()
                },
                stop: {})
        }

        let stopped = StopFlag()
        let events = AsyncStream<ShellCommandEvent> { continuation in
            queue.async {
                drain(terminal, stopped: stopped, into: continuation)
            }
        }
        return ShellCommandSession(
            events: events,
            stop: { [weak stopFlag = stopped] in
                stopFlag?.mark()
                terminal.signalSession(SIGTERM)
                // The backstop, for a command that ignores a polite ask.
                queue.asyncAfter(deadline: .now() + stopGrace) {
                    terminal.signalSession(SIGKILL)
                }
            })
    }

    /// One queue, one reader: the decode buffer is touched from here alone, so it needs no lock.
    nonisolated private static func drain(
        _ terminal: PseudoTerminal, stopped: StopFlag,
        into continuation: AsyncStream<ShellCommandEvent>.Continuation
    ) {
        var decoder = TerminalTextDecoder()
        var buffer = [UInt8](repeating: 0, count: readSize)
        var lastYield = ContinuousClock().now

        while true {
            // Zero is EOF; -1 with EIO is what a pty master returns once its child is gone.
            let count = read(terminal.parentEnd, &buffer, readSize)
            guard count > 0 else { break }
            decoder.append(buffer, count: count)
            let due = ContinuousClock().now - lastYield >= flushInterval
            if let text = decoder.take(force: due) {
                continuation.yield(.output(text))
                lastYield = ContinuousClock().now
            }
        }
        if let text = decoder.take(force: true) { continuation.yield(.output(text)) }

        let status = terminal.wait()
        terminal.close()
        continuation.yield(
            .finished(
                ShellCommandResult(
                    termination: stopped.isSet ? .stopped : .exited(status: status))))
        continuation.finish()
    }

    /// Set from the main actor and read on the drain queue, so the flag carries its own lock.
    private final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func mark() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }

    /// Holds bytes back to whole lines: a newline is always a scalar boundary, so a read landing
    /// mid-character can never be decoded into a replacement character.
    private struct TerminalTextDecoder {
        private var pending: [UInt8] = []

        mutating func append(_ bytes: [UInt8], count: Int) {
            pending.append(contentsOf: bytes[0..<count])
        }

        /// `force` flushes what is there regardless — at exit, and for a prompt that never ends a
        /// line. Even then the tail is cut at a scalar boundary rather than mid-character.
        mutating func take(force: Bool) -> String? {
            guard !pending.isEmpty else { return nil }
            var end = pending.lastIndex(of: 0x0A).map { $0 + 1 }
            if end == nil {
                guard force || pending.count >= unlinedLimit else { return nil }
                end = scalarBoundary(before: pending.count)
            }
            guard let end, end > 0 else { return nil }
            // Latin-1 cannot fail, so output written in some other encoding still reaches the reader.
            let bytes = Array(pending[0..<end])
            pending.removeFirst(end)
            return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1)
        }

        /// Walks back over at most three continuation bytes to the start of a whole character.
        private func scalarBoundary(before index: Int) -> Int {
            var boundary = index
            var stepped = 0
            while boundary > 0, stepped < 4, pending[boundary - 1] & 0xC0 == 0x80 {
                boundary -= 1
                stepped += 1
            }
            // A lead byte only holds back when its own sequence is still incomplete.
            guard boundary > 0 else { return index }
            let lead = pending[boundary - 1]
            let width = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
            return index - boundary + 1 >= width ? index : boundary - 1
        }
    }

    /// `$0` names the caller and the user's values follow as `$1`, `$2` — never spliced into the
    /// command text, where zsh would re-parse them as syntax.
    nonisolated private static func shellArguments(
        command: String, arguments: [String], loadingShellEnvironment: Bool
    ) -> [String] {
        // zsh reads `.zshrc` only for interactive shells, so `-l` alone sees no aliases.
        [loadingShellEnvironment ? "-ilc" : "-lc", command, "tinycast"] + arguments
    }

    /// A temp file rather than a `Pipe`: nothing drains a pipe until `waitUntilExit` returns, so a
    /// command that outran the buffer would deadlock. Immutable, confined to one `execute` on
    /// `queue`, and only read after the process is gone.
    private final class StreamCapture: @unchecked Sendable {
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
            // A byte-offset tail can open mid-scalar; dropping the orphans avoids a leading U+FFFD.
            let body = start > 0 ? data.drop { $0 & 0xC0 == 0x80 } : data[...]
            return String(decoding: body, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        func remove() {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
        }

        static func make() -> StreamCapture? {
            let template = FileManager.default.temporaryDirectory
                .appendingPathComponent("tinycast-command-stream.XXXXXX").path
            var bytes = Array(template.utf8CString)
            let descriptor = bytes.withUnsafeMutableBufferPointer { buffer in
                mkstemp(buffer.baseAddress!)
            }
            guard descriptor >= 0 else { return nil }
            let path = String(
                decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return StreamCapture(
                url: URL(fileURLWithPath: path),
                handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
