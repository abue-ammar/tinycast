import Foundation
import Synchronization

/// Bodies cross the bridge base64-encoded, so binary responses survive.
final class ExtensionFetcher: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpCookieStorage = nil
        // Extensions cache through the Cache API; a shared URL cache would surprise them.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    enum FetchError: LocalizedError {
        case badURL(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let url): return "Invalid URL: \(url)"
            }
        }
    }

    func request(_ spec: RenderValue?) async throws -> [String: Any] {
        let fields = spec?.objectValue ?? [:]
        let urlString = fields["url"]?.stringValue ?? ""
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw FetchError.badURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = fields["method"]?.stringValue ?? "GET"
        for (name, value) in fields["headers"]?.objectValue ?? [:] {
            guard let text = value.stringValue else { continue }
            request.setValue(text, forHTTPHeaderField: name)
        }
        if let base64 = fields["bodyBase64"]?.stringValue, let body = Data(base64Encoded: base64) {
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            guard let name = key as? String, let text = value as? String else { continue }
            headers[name.lowercased()] = text
        }
        let status = http?.statusCode ?? 200
        return [
            "status": status,
            "statusText": HTTPURLResponse.localizedString(forStatusCode: status),
            "headers": headers,
            "url": response.url?.absoluteString ?? urlString,
            "bodyBase64": data.base64EncodedString()
        ]
    }
}

/// `ExtensionNodeShims` launches a child on the JS queue; `wait` collects it off that queue.
enum ExtensionAsyncProcess {
    enum ProcessError: LocalizedError {
        case notStarted

        var errorDescription: String? { "No running child process with that pid." }
    }

    struct Child: Sendable {
        let task: Process
        let stdout: Pipe
        let stderr: Pipe

        /// A child filling the 64 KB pipe blocks before it can exit, so the drain comes first.
        func collect(timeout: Double?) -> [String: Any] {
            var watchdog: DispatchSourceTimer?
            if let timeout, timeout > 0 { watchdog = terminationWatchdog(after: timeout / 1000) }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            watchdog?.cancel()

            return [
                "stdout": outData.base64EncodedString(),
                "stderr": errData.base64EncodedString(),
                "status": Int(task.terminationStatus),
                "signal": task.terminationReason == .uncaughtSignal ? "SIGTERM" : NSNull()
            ]
        }

        /// Signals the pid rather than the `Process`, which a `@Sendable` timer handler cannot capture.
        private func terminationWatchdog(after seconds: Double) -> DispatchSourceTimer {
            let pid = task.processIdentifier
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + seconds)
            timer.setEventHandler { kill(pid, SIGTERM) }
            timer.resume()
            return timer
        }
    }

    /// Started by `enqueue` and not yet claimed by `wait`, keyed by pid.
    private static let uncollected = Mutex<[Int32: (child: Child, timeout: Double?)]>([:])

    /// An app bundle inherits no login shell, so a bare `brew` would otherwise fail.
    static func resolveExecutable(_ command: String) -> URL? {
        let fileManager = FileManager.default
        if command.contains("/") {
            let expanded = (command as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: expanded)
                ? URL(fileURLWithPath: expanded) : nil
        }
        let search =
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [
                "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin",
                "/sbin"
            ]
        for directory in search {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static func enqueue(_ child: Child, timeout: Double?) {
        uncollected.withLock { $0[child.task.processIdentifier] = (child, timeout) }
    }

    static func wait(_ pid: RenderValue?) async throws -> [String: Any] {
        guard let pid = pid?.doubleValue.flatMap({ Int32(exactly: $0) }),
            let entry = uncollected.withLock({ $0.removeValue(forKey: pid) })
        else { throw ProcessError.notStarted }

        return await withCheckedContinuation { continuation in
            // The drain blocks until the child closes its output, which can be minutes away.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: entry.child.collect(timeout: entry.timeout))
            }
        }
    }
}
