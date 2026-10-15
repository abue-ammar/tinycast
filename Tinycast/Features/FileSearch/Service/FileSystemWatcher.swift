import CoreServices
import Foundation

final class FileSystemWatcher {
    struct Event: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags

        func has(_ flag: Int) -> Bool { flags & FSEventStreamEventFlags(flag) != 0 }
    }

    private final class Handler: Sendable {
        let handle: @Sendable ([Event]) -> Void

        init(_ handle: @escaping @Sendable ([Event]) -> Void) { self.handle = handle }
    }

    private static let latency: CFTimeInterval = 1
    private let stream: FSEventStreamRef

    init?(
        paths: [String], since eventID: FSEventStreamEventId, queue: DispatchQueue,
        handler: @escaping @Sendable ([Event]) -> Void
    ) {
        // The stream owns this retain and gives it back through `release` when it is freed.
        let box = Unmanaged.passRetained(Handler(handler))
        var context = FSEventStreamContext(
            version: 0, info: box.toOpaque(), retain: nil,
            release: { info in info.map { Unmanaged<Handler>.fromOpaque($0).release() } },
            copyDescription: nil)
        let flags =
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
        guard
            let stream = FSEventStreamCreate(
                nil,
                { _, info, count, paths, flags, _ in
                    guard let info,
                        let paths = Unmanaged<CFArray>.fromOpaque(paths)
                            .takeUnretainedValue() as? [String]
                    else { return }
                    let events = (0..<min(count, paths.count)).map {
                        Event(path: paths[$0], flags: flags[$0])
                    }
                    Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue().handle(events)
                },
                &context, paths as CFArray, eventID, Self.latency, FSEventStreamCreateFlags(flags))
        else {
            box.release()
            return nil
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
