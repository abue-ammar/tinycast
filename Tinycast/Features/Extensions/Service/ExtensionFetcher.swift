import Foundation

/// `fetch` for extensions, backed by `URLSession`. Bodies cross the bridge base64-encoded so binary
/// responses survive; JSON and text go through the same path.
///
/// `Sendable` because it holds only an immutable `URLSession`.
final class ExtensionFetcher: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpCookieStorage = nil
        // Extensions do their own caching through the Cache API; a shared URL cache would surprise them.
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

/// The async half of the `child_process` shim: `exec` / `execFile` without blocking the JS queue while
/// a slow command runs. The synchronous forms live in `ExtensionNodeShims`; both resolve executables
/// through `resolveExecutable` below.
enum ExtensionAsyncProcess {
    enum ProcessError: LocalizedError {
        case notFound(String)
        case failedToStart(String, String)

        var errorDescription: String? {
            switch self {
            case .notFound(let command):
                return "ENOENT: command not found: '\(command)'"
            case .failedToStart(let command, let reason):
                return "Could not run '\(command)': \(reason)"
            }
        }
    }

    /// Resolve a bare command name against PATH the way `execFile` does. An app bundle inherits no
    /// login shell, so `execFile("brew", …)` would otherwise fail for every Homebrew-based extension.
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

    static func run(_ spec: RenderValue?) async throws -> [String: Any] {
        let fields = spec?.objectValue ?? [:]
        let command = fields["command"]?.stringValue ?? ""
        let useShell = fields["shell"]?.boolValue ?? false
        let args = (fields["args"]?.arrayValue ?? []).compactMap(\.stringValue)
        let cwd = fields["cwd"]?.stringValue
        let environment = (fields["env"]?.objectValue).map { $0.compactMapValues(\.stringValue) }
        let input = fields["input"]?.stringValue.flatMap { Data(base64Encoded: $0) }
        let timeout = fields["timeout"]?.doubleValue
        let detached = fields["detached"]?.boolValue ?? false

        return try await withCheckedThrowingContinuation { continuation in
            // `Process` termination is delivered on a private queue; run the whole thing off-main.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try execute(
                        command: command, useShell: useShell, args: args, cwd: cwd,
                        environment: environment, input: input, timeout: timeout,
                        detached: detached)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func execute(
        command: String, useShell: Bool, args: [String], cwd: String?,
        environment: [String: String]?, input: Data?, timeout: Double?, detached: Bool = false
    ) throws -> [String: Any] {
        let task = Process()
        if useShell {
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", command]
        } else {
            guard let resolved = resolveExecutable(command) else {
                throw ProcessError.notFound(command)
            }
            task.executableURL = resolved
            task.arguments = args
        }
        if let cwd, !cwd.isEmpty {
            task.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath)
        }
        task.environment = environment ?? ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        if let input {
            let stdin = Pipe()
            task.standardInput = stdin
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }

        do {
            try task.run()
        } catch {
            throw ProcessError.failedToStart(command, error.localizedDescription)
        }
        // A detached child is meant to outlive the call (`caffeinate -t 300`); answer as soon as it's
        // running rather than pinning a worker thread until it exits.
        if detached {
            return ["stdout": "", "stderr": "", "status": 0, "signal": NSNull()]
        }
        let (outData, errData) = drain(task, stdout: stdout, stderr: stderr, timeout: timeout)

        return [
            "stdout": outData.base64EncodedString(),
            "stderr": errData.base64EncodedString(),
            "status": Int(task.terminationStatus),
            "signal": task.terminationReason == .uncaughtSignal ? "SIGTERM" : NSNull()
        ]
    }

    /// Reads a started child to completion. A child that fills the 64 KB pipe buffer blocks before it
    /// can exit, so the drain has to come first — which leaves the deadline nothing to be but a watchdog.
    static func drain(
        _ task: Process, stdout: Pipe, stderr: Pipe, timeout: Double?
    ) -> (Data, Data) {
        var watchdog: DispatchSourceTimer?
        if let timeout, timeout > 0 { watchdog = terminationWatchdog(task, after: timeout / 1000) }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        watchdog?.cancel()
        return (outData, errData)
    }

    /// Signals the pid rather than the `Process`, which a `@Sendable` timer handler cannot capture.
    private static func terminationWatchdog(
        _ task: Process, after seconds: Double
    ) -> DispatchSourceTimer {
        let pid = task.processIdentifier
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { kill(pid, SIGTERM) }
        timer.resume()
        return timer
    }
}
