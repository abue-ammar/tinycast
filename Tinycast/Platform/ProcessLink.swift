import Foundation

/// Generous: one defaults delta after a backup import carries every library at once.
private let maximumFrameBytes = 32 << 20

/// Typed messages both ways between two roles, delivered on the main actor in the order sent.
@MainActor
final class ProcessLink<Outgoing: Encodable & Sendable, Incoming: Decodable & Sendable> {
    var onReceive: ((Incoming) -> Void)?
    /// Fires once, when the other end goes away; a closed link never reopens.
    var onClose: (() -> Void)?

    private let reading: FileHandle
    private let writing: FileHandle
    /// Held so Foundation reaps the child; nil on the child's own side.
    private let child: Process?
    private let reader = DispatchQueue(label: "com.tinycast.process-link.read")
    private let writer = DispatchQueue(label: "com.tinycast.process-link.write")
    private var receiver: Task<Void, Never>?

    private init(reading: FileHandle, writing: FileHandle, child: Process?) {
        self.reading = reading
        self.writing = writing
        self.child = child
    }

    isolated deinit {
        receiver?.cancel()
    }

    var childProcessIdentifier: pid_t? { child?.processIdentifier }

    /// Starts this executable again as `role`; the child ends itself when the link closes.
    static func spawn(_ role: ProcessRole) throws -> ProcessLink {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [role.argument]
        process.standardInput = input
        process.standardOutput = output
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(.EIO)
        }
        try process.run()
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        return ProcessLink(
            reading: output.fileHandleForReading, writing: input.fileHandleForWriting, child: process)
    }

    /// The child's half; stdio then goes to /dev/null, so no print or tool can touch a frame.
    static func standardIO() -> ProcessLink? {
        var status = stat()
        guard fstat(STDIN_FILENO, &status) == 0, status.st_mode & S_IFMT == S_IFIFO else { return nil }
        let reading = fcntl(STDIN_FILENO, F_DUPFD_CLOEXEC, 0)
        let writing = fcntl(STDOUT_FILENO, F_DUPFD_CLOEXEC, 0)
        let null = open("/dev/null", O_RDWR | O_CLOEXEC)
        guard reading >= 0, writing >= 0, null >= 0, fcntl(writing, F_SETNOSIGPIPE, 1) == 0 else {
            return nil
        }
        dup2(null, STDIN_FILENO)
        dup2(null, STDOUT_FILENO)
        close(null)
        return ProcessLink(
            reading: FileHandle(fileDescriptor: reading, closeOnDealloc: true),
            writing: FileHandle(fileDescriptor: writing, closeOnDealloc: true), child: nil)
    }

    func start() {
        guard receiver == nil else { return }
        let reading = reading
        let (messages, continuation) = AsyncStream.makeStream(of: Incoming.self)
        reader.async {
            while let message = try? PipeFraming.read(
                Incoming.self, from: reading, maximum: maximumFrameBytes)
            {
                continuation.yield(message)
            }
            continuation.finish()
        }
        receiver = Task { [weak self] in
            for await message in messages { self?.onReceive?(message) }
            self?.onClose?()
        }
    }

    /// A write to a peer that has gone fails quietly; its end of stream reports the loss.
    func send(_ message: Outgoing) {
        let writing = writing
        writer.async {
            try? PipeFraming.write(message, to: writing, maximum: maximumFrameBytes)
        }
    }

    /// Blocks until every message sent so far is in the pipe; for the last ones before exit.
    func flush() {
        writer.sync {}
    }
}
