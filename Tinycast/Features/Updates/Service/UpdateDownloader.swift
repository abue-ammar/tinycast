import Foundation

/// `URLSession` reports byte progress only to a delegate, hence the one left here.
enum UpdateDownloader {
    enum Event: Sendable {
        case progress(received: Int64, expected: Int64)
        case finished(URL)
    }

    /// Cancelling the consuming task cancels the transfer and tears the session down with it.
    static func download(
        _ release: AvailableRelease, to destination: URL
    ) -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let delegate = Delegate(
                destination: destination, expected: release.assetSize, events: continuation)
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: request(release.assetURL))
            continuation.onTermination = { _ in
                task.cancel()
                // A session holds its delegate until invalidated, so this is what breaks the cycle.
                session.finishTasksAndInvalidate()
            }
            task.resume()
        }
    }

    static func data(from url: URL) async throws -> Data {
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request(url))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw UpdateFailure.downloadFailed(String(localized: "The server answered \(status)."))
        }
        return data
    }

    /// Cacheless, never `URLSession.shared`, so the only copy is the one on disk.
    private static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 60
        return config
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Tinycast", forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// Every stored property is immutable and `Sendable`; only `NSObject` keeps it from being checked.
private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expected: Int64
    private let events: AsyncThrowingStream<UpdateDownloader.Event, any Error>.Continuation

    init(
        destination: URL, expected: Int64,
        events: AsyncThrowingStream<UpdateDownloader.Event, any Error>.Continuation
    ) {
        self.destination = destination
        self.expected = expected
        self.events = events
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        // A server omitting Content-Length reports -1; the release's size is the better guess.
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        events.yield(.progress(received: totalBytesWritten, expected: total))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            events.finish(
                throwing: UpdateFailure.downloadFailed(String(localized: "The server answered \(status).")))
            return
        }
        do {
            // The temp file is unlinked the moment this returns, so the move has to happen here.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            events.yield(.finished(destination))
            events.finish()
        } catch {
            events.finish(throwing: UpdateFailure.downloadFailed(error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        events.finish(throwing: UpdateFailure.downloadFailed(error.localizedDescription))
    }
}
