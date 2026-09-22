import AppKit
import Darwin
import Foundation

/// What a pasteboard read means. The helper is the only process that blocks on one.
nonisolated enum ClipboardCapture {
    static let internalTypeName = "com.tinycast.internal"
    static let maxTextLength = 32_000
    static let maxCapturedFiles = 32
    /// A screenshot PNG fits; anything larger stays in the helper and is dropped.
    static let maxImageBytes = 16 * 1024 * 1024
    static let maxResponseLineBytes = 1024 * 1024
    static let sensitiveTypeNames: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.apple.is-sensitive"
    ]
    static let volatileRoots = [
        "/tmp/", "/var/tmp/", "/var/folders/", NSHomeDirectory() + "/Library/Caches/"
    ]

    enum Reason: String, Sendable, Equatable {
        case ownWrite
        case sensitive
        case empty
        case tooLarge
    }

    enum Payload: Sendable, Equatable {
        case text(String)
        case files([String])
        case png(Data)
        case skipped(Reason)
        case timedOut
        case unavailable
    }

    static func filePaths(
        on pasteboard: NSPasteboard, volatileRoots roots: [String] = volatileRoots
    ) -> [String]? {
        let durable = PasteboardFiles.urls(on: pasteboard, limit: maxCapturedFiles) {
            isDurable($0, roots: roots)
        }
        // Nil rather than empty, so a copied `http` URL falls through and stays a link.
        guard !durable.isEmpty else { return nil }
        // Reversed on insert, so the first file copied ends up leading the history.
        return durable.map(\.standardizedFileURL.path).reversed()
    }

    /// An app that stages a temp file beside better inline content must keep the inline content.
    private static func isDurable(_ url: URL, roots: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var path = url.resolvingSymlinksInPath().path
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        return !roots.contains { path.hasPrefix($0) }
    }

    /// Every content read lives here, so the app process never calls into a slow owner.
    static func read(_ pasteboard: NSPasteboard) -> Payload {
        let types = pasteboard.types ?? []
        if types.contains(NSPasteboard.PasteboardType(internalTypeName)) {
            return .skipped(.ownWrite)
        }
        if !sensitiveTypeNames.isDisjoint(with: Set(types.map(\.rawValue))) {
            return .skipped(.sensitive)
        }
        if let paths = filePaths(on: pasteboard) { return .files(paths) }
        if let text = pasteboard.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            guard text.count <= maxTextLength else { return .skipped(.tooLarge) }
            return .text(text)
        }
        guard let type = pasteboard.availableType(from: [.png, .tiff]),
            let data = pasteboard.data(forType: type)
        else { return .skipped(.empty) }
        let png =
            type == .png
            ? data
            : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        guard let png, png.count <= maxImageBytes else { return .skipped(.tooLarge) }
        return .png(png)
    }
}

/// Length-free line header, then raw PNG bytes when `bytes` is set. One format for both sides.
nonisolated enum ClipboardCaptureWire {
    struct Request: Codable, Sendable {
        var id: UInt64
        var board: String
    }

    struct Header: Codable, Sendable {
        var id: UInt64
        var kind: String
        var text: String?
        var paths: [String]?
        var reason: String?
        var bytes: Int?
    }

    static func line(_ request: Request) throws -> Data {
        var data = try JSONEncoder().encode(request)
        data.append(10)
        return data
    }

    static func request(from line: Data) -> Request? {
        try? JSONDecoder().decode(Request.self, from: line)
    }

    static func header(for payload: ClipboardCapture.Payload, id: UInt64) -> Header? {
        switch payload {
        case .text(let text):
            return Header(id: id, kind: "text", text: text, paths: nil, reason: nil, bytes: nil)
        case .files(let paths):
            return Header(id: id, kind: "files", text: nil, paths: paths, reason: nil, bytes: nil)
        case .png(let data):
            return Header(id: id, kind: "image", text: nil, paths: nil, reason: nil, bytes: data.count)
        case .skipped(let reason):
            return Header(
                id: id, kind: "skip", text: nil, paths: nil, reason: reason.rawValue, bytes: nil)
        case .timedOut, .unavailable:
            return nil
        }
    }

    static func payload(from header: Header, image: Data?) -> ClipboardCapture.Payload {
        switch header.kind {
        case "text":
            guard let text = header.text else { return .unavailable }
            return .text(text)
        case "files":
            guard let paths = header.paths, !paths.isEmpty else { return .skipped(.empty) }
            return .files(paths)
        case "image":
            guard let image else { return .unavailable }
            return .png(image)
        case "skip":
            guard let reason = header.reason.flatMap(ClipboardCapture.Reason.init(rawValue:)) else {
                return .unavailable
            }
            return .skipped(reason)
        default:
            return .unavailable
        }
    }

    static func headerLine(_ header: Header) throws -> Data {
        var data = try JSONEncoder().encode(header)
        data.append(10)
        return data
    }

    static func header(from line: Data) -> Header? {
        try? JSONDecoder().decode(Header.self, from: line)
    }
}

/// Resident helper client. `runningPID` is the only cross-queue state, guarded by `lock`.
final class ClipboardCaptureClient: @unchecked Sendable {
    private let executable: URL
    private let queue = DispatchQueue(label: "com.tinycast.clipboard-capture")
    private let lock = NSLock()
    private var process: Process?
    private var writer: FileHandle?
    private var reader: FileHandle?
    private var buffer = Data()
    private var nextID: UInt64 = 0
    private var runningPID: pid_t = 0
    private var sawEOF = false

    init(executable: URL) {
        self.executable = executable
    }

    var processID: pid_t { lock.withLock { runningPID } }

    func read(board: String, timeout: Duration) async -> ClipboardCapture.Payload {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.readBlocking(board: board, timeout: timeout))
            }
        }
    }

    /// Unblocks a helper stuck inside a pasteboard owner. Safe from the main actor and `deinit`.
    func cancel() {
        let pid = lock.withLock { runningPID }
        if pid > 0 { kill(pid, SIGKILL) }
        queue.async { self.reap() }
    }

    private func readBlocking(board: String, timeout: Duration) -> ClipboardCapture.Payload {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        guard ensureProcess() else { return .unavailable }
        nextID += 1
        let id = nextID
        do {
            guard let writer else { return fail() }
            try writer.write(contentsOf: try ClipboardCaptureWire.line(.init(id: id, board: board)))
        } catch {
            return fail()
        }
        guard let headerData = readLine(until: deadline) else { return timedOutOrDead() }
        guard let header = ClipboardCaptureWire.header(from: headerData), header.id == id else {
            return fail()
        }
        if let count = header.bytes {
            guard count > 0, count <= ClipboardCapture.maxImageBytes else { return fail() }
            guard let image = readCount(count, until: deadline) else { return timedOutOrDead() }
            return ClipboardCaptureWire.payload(from: header, image: image)
        }
        return ClipboardCaptureWire.payload(from: header, image: nil)
    }

    private func ensureProcess() -> Bool {
        if let process, process.isRunning { return true }
        reap()
        let process = Process()
        process.executableURL = executable
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        do { try process.run() } catch { return false }
        let writer = input.fileHandleForWriting
        let reader = output.fileHandleForReading
        // The helper can exit mid-write; the failure has to come back as EPIPE, not SIGPIPE.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        _ = fcntl(reader.fileDescriptor, F_SETNOSIGPIPE, 1)
        self.process = process
        self.writer = writer
        self.reader = reader
        buffer.removeAll(keepingCapacity: false)
        sawEOF = false
        lock.withLock { runningPID = pid_t(process.processIdentifier) }
        return true
    }

    private func readLine(until deadline: ContinuousClock.Instant) -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard line.count <= ClipboardCapture.maxResponseLineBytes else {
                    _ = fail()
                    return nil
                }
                return line
            }
            guard buffer.count <= ClipboardCapture.maxResponseLineBytes else {
                _ = fail()
                return nil
            }
            guard readMore(until: deadline) else { return nil }
        }
    }

    private func readCount(_ count: Int, until deadline: ContinuousClock.Instant) -> Data? {
        while buffer.count < count {
            guard readMore(until: deadline) else { return nil }
        }
        let data = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        // An idle client must not retain the last image-sized pipe buffer.
        if buffer.isEmpty { buffer = Data() }
        return data
    }

    private func readMore(until deadline: ContinuousClock.Instant) -> Bool {
        guard let reader else { return false }
        let milliseconds = Self.milliseconds(until: deadline)
        guard milliseconds > 0 else {
            _ = stop(timeout: true)
            return false
        }
        while true {
            var state = pollfd(fd: reader.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let waited = Darwin.poll(&state, 1, milliseconds)
            if waited == 0 {
                _ = stop(timeout: true)
                return false
            }
            if waited < 0, errno == EINTR { continue }
            if waited < 0 { return false }
            break
        }
        var scratch = [UInt8](repeating: 0, count: 16 * 1024)
        let count = Darwin.read(reader.fileDescriptor, &scratch, scratch.count)
        if count <= 0 {
            sawEOF = true
            reap()
            return false
        }
        buffer.append(contentsOf: scratch.prefix(count))
        return true
    }

    /// `poll` wants milliseconds, and `Duration` has no integer division.
    private static func milliseconds(until deadline: ContinuousClock.Instant) -> Int32 {
        let remaining = deadline - ContinuousClock.now
        guard remaining > .zero else { return 0 }
        let parts = remaining.components
        let millis = parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000
        return Int32(min(max(millis, 1), 60_000))
    }

    private func timedOutOrDead() -> ClipboardCapture.Payload {
        sawEOF ? .unavailable : .timedOut
    }

    @discardableResult
    private func fail() -> ClipboardCapture.Payload {
        stop(timeout: false)
        return .unavailable
    }

    @discardableResult
    private func stop(timeout: Bool) -> ClipboardCapture.Payload {
        cancel()
        reap()
        return timeout ? .timedOut : .unavailable
    }

    private func reap() {
        if let process {
            let pid = pid_t(process.processIdentifier)
            if process.isRunning { kill(pid, SIGKILL) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while true {
                var status: Int32 = 0
                let result = Darwin.waitpid(pid, &status, WNOHANG)
                if result == pid || (result == -1 && errno == ECHILD) { break }
                if result == -1 && errno != EINTR { break }
                if ContinuousClock.now >= deadline { break }
                usleep(1_000)
            }
        }
        try? writer?.close()
        try? reader?.close()
        process = nil
        writer = nil
        reader = nil
        buffer.removeAll(keepingCapacity: false)
        lock.withLock { runningPID = 0 }
    }
}
