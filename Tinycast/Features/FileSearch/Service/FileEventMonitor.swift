import CoreServices
import Foundation

/// Folder-level FSEvents for the indexed roots, delivered as one async sequence of batches.
enum FileEventMonitor {
    enum Batch: Sendable, Equatable {
        case changes([FileIndexScanner.Change])
        /// The history is incomplete or a root itself moved: only a full walk is trustworthy again.
        case rebuild
    }

    nonisolated static func batches(for roots: [String], latency: TimeInterval = 1) -> AsyncStream<Batch> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let sink = Sink(continuation)
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(sink).toOpaque(),
                retain: nil, release: nil, copyDescription: nil)
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
            guard
                let stream = FSEventStreamCreate(
                    nil, deliver, &context, roots as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
            else {
                continuation.finish()
                return
            }
            let handle = StreamHandle(stream: stream, sink: sink)
            FSEventStreamSetDispatchQueue(stream, handle.queue)
            FSEventStreamStart(stream)
            continuation.onTermination = { _ in handle.invalidate() }
        }
    }

    nonisolated static func batch(
        paths: [String], flags: [FSEventStreamEventFlags]
    ) -> Batch {
        let lost = FSEventStreamEventFlags(
            kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged)
        let recursive = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        var order: [String] = []
        var isRecursive: [String: Bool] = [:]
        for (path, flag) in zip(paths, flags) {
            if flag & lost != 0 { return .rebuild }
            let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
            if isRecursive[trimmed] == nil { order.append(trimmed) }
            isRecursive[trimmed, default: false] = isRecursive[trimmed] == true || flag & recursive != 0
        }
        return .changes(order.map { FileIndexScanner.Change(path: $0, isRecursive: isRecursive[$0]!) })
    }
}

private final class Sink: Sendable {
    let continuation: AsyncStream<FileEventMonitor.Batch>.Continuation

    init(_ continuation: AsyncStream<FileEventMonitor.Batch>.Continuation) {
        self.continuation = continuation
    }
}

/// The stream ref is only touched on its own serial queue, which is what makes it safe to share.
private final class StreamHandle: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.tinycast.file-events", qos: .utility)
    private let stream: FSEventStreamRef
    private let sink: Sink

    init(stream: FSEventStreamRef, sink: Sink) {
        self.stream = stream
        self.sink = sink
    }

    func invalidate() {
        queue.async { [self] in
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            withExtendedLifetime(sink) {}
        }
    }
}

private func deliver(
    _ stream: ConstFSEventStreamRef, _ info: UnsafeMutableRawPointer?, _ count: Int,
    _ paths: UnsafeMutableRawPointer, _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let sink = Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue()
    let cPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    let batch = FileEventMonitor.batch(
        paths: (0..<count).map { String(cString: cPaths[$0]) },
        flags: Array(UnsafeBufferPointer(start: flags, count: count)))
    sink.continuation.yield(batch)
}
