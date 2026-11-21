import Foundation
import os

/// Generous: one defaults delta after a backup import carries every library at once.
private let maximumFrameBytes = 32 << 20

/// Typed messages both ways between two Tinycast processes, delivered on the main actor in order.
@MainActor
final class ProcessLink<Outgoing: Encodable & Sendable, Incoming: Decodable & Sendable> {
    var onReceive: ((Incoming) -> Void)?
    var onClose: ((Error?) -> Void)?
    private(set) var isOpen = true

    private let reading: FileHandle
    private let channel: DispatchIO
    /// Held so Foundation reaps the child; nil on the child's own side.
    private let child: Process?
    private let reader = DispatchQueue(label: "com.tinycast.process-link.read")
    private let writer = DispatchQueue(label: "com.tinycast.process-link.write")
    private var receiver: Task<Void, Never>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abueammar.tinycast", category: "ProcessLink")

    private init(reading: FileHandle, writing: FileHandle, child: Process?) {
        self.reading = reading
        self.child = child
        channel = DispatchIO(type: .stream, fileDescriptor: writing.fileDescriptor, queue: writer) {
            @Sendable _ in
            try? writing.close()
        }
    }

    isolated deinit {
        receiver?.cancel()
        channel.close(flags: .stop)
    }

    var childProcessIdentifier: pid_t? { child?.processIdentifier }

    /// The child ends itself when the link closes.
    static func spawn(_ executable: URL, arguments: [String]) throws -> ProcessLink {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(.EIO)
        }
        _ = try process.runObservingExit()
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
        guard reading >= 0 else { return nil }
        let readHandle = FileHandle(fileDescriptor: reading, closeOnDealloc: true)
        let writing = fcntl(STDOUT_FILENO, F_DUPFD_CLOEXEC, 0)
        guard writing >= 0 else { return nil }
        let writeHandle = FileHandle(fileDescriptor: writing, closeOnDealloc: true)
        let null = open("/dev/null", O_RDWR | O_CLOEXEC)
        guard null >= 0 else { return nil }
        defer { close(null) }
        guard fcntl(writing, F_SETNOSIGPIPE, 1) == 0,
            dup2(null, STDIN_FILENO) >= 0, dup2(null, STDOUT_FILENO) >= 0
        else { return nil }
        return ProcessLink(reading: readHandle, writing: writeHandle, child: nil)
    }

    func start() {
        guard isOpen, receiver == nil else { return }
        let reading = reading
        let (messages, continuation) = AsyncThrowingStream.makeStream(of: Incoming.self)
        reader.async {
            do {
                while let message = try PipeFraming.read(
                    Incoming.self, from: reading, maximum: maximumFrameBytes)
                {
                    if case .terminated = continuation.yield(message) { return }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        receiver = Task { [weak self] in
            do {
                for try await message in messages { self?.onReceive?(message) }
                self?.finish(nil)
            } catch {
                self?.finish(error)
            }
        }
    }

    func send(_ message: Outgoing) {
        guard isOpen else { return }
        let channel = channel
        let writer = writer
        writer.async { [weak self] in
            do {
                let frame = try PipeFraming.encode(message, maximum: maximumFrameBytes)
                var length = frame.length
                var data = withUnsafeBytes(of: &length) { DispatchData(bytes: $0) }
                data.append(frame.payload.withUnsafeBytes { DispatchData(bytes: $0) })
                channel.write(offset: 0, data: data, queue: writer) { @Sendable [weak self] _, _, code in
                    guard code != 0 else { return }
                    let error = POSIXError(.init(rawValue: code) ?? .EIO)
                    Task { @MainActor [weak self] in self?.finish(error) }
                }
            } catch {
                channel.close(flags: .stop)
                Task { @MainActor [weak self] in self?.finish(error) }
            }
        }
    }

    private func finish(_ error: Error?) {
        guard isOpen else { return }
        isOpen = false
        receiver?.cancel()
        channel.close(flags: .stop)
        if let error { logger.error("Process link closed: \(error.localizedDescription, privacy: .public)") }
        onClose?(error)
    }
}
