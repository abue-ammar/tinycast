import Foundation
import Synchronization

/// One `URLSessionWebSocketTask` per socket, read by the single `receive` JS keeps in flight.
final class ExtensionWebSocketBridge: NSObject, Sendable, URLSessionWebSocketDelegate {
    private struct Connection {
        let task: URLSessionWebSocketTask
        var opening: CheckedContinuation<String, Error>?
    }

    private let connections = Mutex<[Int: Connection]>([:])
    private let sessionBox = Mutex<URLSession?>(nil)

    enum SocketError: LocalizedError {
        case badURL(String)
        case closed
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let url): return "Invalid WebSocket URL: \(url)"
            case .closed: return "The WebSocket is closed."
            case .unknown(let method): return "Unknown host call 'websocket.\(method)'."
            }
        }
    }

    func perform(method: String, arguments: [RenderValue]) async throws -> Any? {
        let fields = arguments.first?.objectValue ?? [:]
        switch method {
        case "open": return try await open(fields)
        case "receive": return try await receive(id: whole(arguments.first))
        case "send": return try await send(fields)
        case "close":
            close(
                id: whole(fields["id"]), code: whole(fields["code"], or: 1000),
                reason: fields["reason"]?.stringValue ?? "")
            return nil
        default: throw SocketError.unknown(method)
        }
    }

    private func whole(_ value: RenderValue?, or fallback: Int = 0) -> Int {
        value?.doubleValue.map(Int.init) ?? fallback
    }

    /// The context is thrown away between commands, so nothing would read these again.
    func closeAll() {
        let open = connections.withLock { state -> [Connection] in
            let all = Array(state.values)
            state.removeAll()
            return all
        }
        for connection in open {
            connection.opening?.resume(throwing: SocketError.closed)
            connection.task.cancel(with: .goingAway, reason: nil)
        }
    }

    // MARK: - Calls

    private func open(_ fields: [String: RenderValue]) async throws -> [String: Any] {
        let text = fields["url"]?.stringValue ?? ""
        guard let url = URL(string: text), url.scheme == "ws" || url.scheme == "wss" else {
            throw SocketError.badURL(text)
        }
        var request = URLRequest(url: url)
        for (name, value) in fields["headers"]?.objectValue ?? [:] {
            guard let header = value.stringValue else { continue }
            request.setValue(header, forHTTPHeaderField: name)
        }
        let protocols = (fields["protocols"]?.arrayValue ?? []).compactMap(\.stringValue)
        if !protocols.isEmpty {
            request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        let task = session().webSocketTask(with: request)
        let id = task.taskIdentifier
        let negotiated = try await withCheckedThrowingContinuation { continuation in
            connections.withLock { $0[id] = Connection(task: task, opening: continuation) }
            task.resume()
        }
        return ["id": id, "protocol": negotiated]
    }

    private func receive(id: Int) async throws -> [String: Any] {
        guard let task = connections.withLock({ $0[id]?.task }) else { throw SocketError.closed }
        do {
            switch try await task.receive() {
            case .string(let text): return ["type": "text", "text": text]
            case .data(let data): return ["type": "binary", "base64": data.base64EncodedString()]
            @unknown default: return ["type": "text", "text": ""]
            }
        } catch {
            connections.withLock { $0[id] = nil }
            let code = task.closeCode
            let clean = code != .invalid
            return [
                "type": "close",
                "code": clean ? code.rawValue : 1006,
                "reason": String(data: task.closeReason ?? Data(), encoding: .utf8) ?? "",
                "abnormal": !clean
            ]
        }
    }

    private func send(_ fields: [String: RenderValue]) async throws -> Any? {
        let id = whole(fields["id"])
        guard let task = connections.withLock({ $0[id]?.task }) else { throw SocketError.closed }
        if let base64 = fields["base64"]?.stringValue, let data = Data(base64Encoded: base64) {
            try await task.send(.data(data))
        } else {
            try await task.send(.string(fields["text"]?.stringValue ?? ""))
        }
        return nil
    }

    private func close(id: Int, code: Int, reason: String) {
        guard let connection = connections.withLock({ $0.removeValue(forKey: id) }) else { return }
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        connection.task.cancel(with: closeCode, reason: reason.data(using: .utf8))
    }

    // MARK: - Session

    /// Private and ephemeral, like every other networked surface: no cookie jar, no shared cache.
    private func session() -> URLSession {
        sessionBox.withLock { box in
            if let existing = box { return existing }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let created = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            box = created
            return created
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocolName: String?
    ) {
        finishOpening(id: webSocketTask.taskIdentifier, result: .success(protocolName ?? ""))
    }

    /// The only place a failed handshake surfaces: `receive` is never reached when one fails.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finishOpening(
            id: task.taskIdentifier,
            result: .failure(error ?? SocketError.closed))
    }

    private func finishOpening(id: Int, result: Result<String, Error>) {
        let continuation = connections.withLock { state -> CheckedContinuation<String, Error>? in
            guard let opening = state[id]?.opening else { return nil }
            state[id]?.opening = nil
            if case .failure = result { state[id] = nil }
            return opening
        }
        continuation?.resume(with: result)
    }
}
