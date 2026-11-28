import Foundation

@testable import Tinycast

func directoryChanges(at directory: URL) throws -> AsyncStream<Void> {
    let descriptor = open(directory.path, O_EVTONLY)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let (events, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor, eventMask: .write, queue: .global())
    source.setEventHandler { continuation.yield() }
    source.setCancelHandler { close(descriptor) }
    continuation.onTermination = { _ in source.cancel() }
    source.activate()
    continuation.yield()
    return events
}

func derivativeQueueDrained() async {
    await withCheckedContinuation { continuation in
        ImageDerivative.queue.async { continuation.resume() }
    }
}
