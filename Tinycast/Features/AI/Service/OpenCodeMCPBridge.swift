import Foundation
import Network

@MainActor
final class OpenCodeMCPBridge {
    private let session: AIToolSession
    private let event: (AIStreamEvent) -> Void
    private let failure: (String) -> Void
    private let bearer = UUID().uuidString + UUID().uuidString
    private let server = "tinycast_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var task: Task<Void, Never>?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var stopped = false
    private var calls = 0
    private var spent = 0
    private var invoking = false
    private var waiting: [CheckedContinuation<Void, Error>] = []

    init(
        session: AIToolSession, event: @escaping (AIStreamEvent) -> Void,
        failure: @escaping (String) -> Void
    ) {
        self.session = session
        self.event = event
        self.failure = failure
    }

    isolated deinit { task?.cancel() }

    func start() async throws -> String {
        let listener = try NetworkListener(
            using: .parameters { TCP() }
                .localEndpoint(.hostPort(host: .ipv4(.loopback), port: .any)))
        listener.newConnectionLimit = 16
        let port = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                task = Task { [weak self] in
                    do {
                        try await listener.onStateUpdate { [weak self] listener, state in
                            switch state {
                            case .ready:
                                guard let port = listener.port?.rawValue else { return }
                                self?.ready?.resume(returning: port)
                                self?.ready = nil
                            case .waiting, .failed:
                                self?.fail(URLError(.cannotConnectToHost))
                            default: break
                            }
                        }.run { [weak self] connection in
                            defer { listener.newConnectionLimit += 1 }
                            await self?.receive(connection)
                        }
                    } catch {
                        self?.fail(error)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        return try OpenCodeMCPLaunch.configuration(
            server: server, url: "http://127.0.0.1:\(port)/mcp", bearer: bearer,
            tools: session.tools)
    }

    func stop() {
        stopped = true
        ready?.resume(throwing: CancellationError())
        ready = nil
        for waiter in waiting { waiter.resume(throwing: CancellationError()) }
        waiting = []
        task?.cancel()
        task = nil
    }

    private func fail(_ error: any Error) {
        guard !stopped else { return }
        ready?.resume(throwing: error)
        ready = nil
        stop()
        failure(error.localizedDescription)
    }

    private func receive(_ connection: NetworkConnection<TCP>) async {
        do {
            let body = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask { [weak self] in
                    guard let self else { throw CancellationError() }
                    return try await self.read(connection)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                return try await group.next() ?? Data()
            }
            guard !stopped else { return }
            let result = try await respond(body)
            try Task.checkCancellation()
            guard !stopped else { return }
            try await send(connection, status: result == nil ? "202 Accepted" : "200 OK", body: result)
        } catch let error as HTTPFailure {
            try? await send(connection, status: error.status, body: nil)
        } catch {
            return
        }
    }

    private struct HTTPFailure: Error {
        let status: String
    }

    private func read(_ connection: NetworkConnection<TCP>) async throws -> Data {
        var bytes = Data()
        var bodyStart: Int?
        var length = 0
        while true {
            let message = try await connection.receive(atLeast: 1, atMost: 8192)
            bytes.append(message.content)
            if bodyStart == nil {
                if let separator = bytes.range(of: Data("\r\n\r\n".utf8)) {
                    guard separator.lowerBound <= 8192,
                        let header = String(data: bytes[..<separator.lowerBound], encoding: .utf8)
                    else { throw HTTPFailure(status: "400 Bad Request") }
                    let lines = header.components(separatedBy: "\r\n")
                    guard lines.first == "POST /mcp HTTP/1.1" else {
                        throw HTTPFailure(status: "405 Method Not Allowed")
                    }
                    var headers: [String: String] = [:]
                    for line in lines.dropFirst() {
                        guard let colon = line.firstIndex(of: ":") else {
                            throw HTTPFailure(status: "400 Bad Request")
                        }
                        let key = line[..<colon].lowercased()
                        guard headers[key] == nil else {
                            throw HTTPFailure(status: "400 Bad Request")
                        }
                        headers[key] = line[line.index(after: colon)...]
                            .trimmingCharacters(in: .whitespaces)
                    }
                    guard headers["authorization"] == "Bearer " + bearer,
                        headers["origin"] == nil
                    else { throw HTTPFailure(status: "403 Forbidden") }
                    guard headers["transfer-encoding"] == nil,
                        let value = headers["content-length"], let count = Int(value),
                        count > 0, count <= 1_048_576
                    else { throw HTTPFailure(status: "413 Content Too Large") }
                    bodyStart = separator.upperBound
                    length = count
                } else if bytes.count > 8192 {
                    throw HTTPFailure(status: "431 Request Header Fields Too Large")
                }
            }
            if let bodyStart, bytes.count >= bodyStart + length {
                return Data(bytes[bodyStart..<(bodyStart + length)])
            }
            if message.metadata.endOfStream { throw HTTPFailure(status: "400 Bad Request") }
        }
    }

    private func respond(_ body: Data) async throws -> Data? {
        guard let request = JSONValue(data: body)?.objectValue,
            request["jsonrpc"]?.stringValue == "2.0",
            let method = request["method"]?.stringValue
        else { throw HTTPFailure(status: "400 Bad Request") }
        guard let id = request["id"] else { return nil }
        let params = request["params"]?.objectValue ?? [:]
        let result: JSONValue
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue ?? ""
            let version =
                ["2024-11-05", "2025-03-26", "2025-06-18"].contains(requested)
                ? requested : "2025-06-18"
            result = .object([
                "protocolVersion": .string(version), "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": .string("Tinycast"), "version": .string("1")])
            ])
        case "ping":
            result = .object([:])
        case "tools/list":
            result = .object([
                "tools": .array(
                    session.tools.enumerated().map { index, tool in
                        .object([
                            "name": .string(OpenCodeMCPLaunch.toolName(at: index)),
                            "description": .string(tool.origin + ": " + tool.title + "\n" + tool.description),
                            "inputSchema": tool.parameters
                        ])
                    })
            ])
        case "tools/call":
            result = try await call(params)
        default:
            return try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": id.jsonObject,
                "error": ["code": -32601, "message": "Method not found"]
            ])
        }
        return try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id.jsonObject, "result": result.jsonObject
        ])
    }

    private func call(_ params: [String: JSONValue]) async throws -> JSONValue {
        guard !stopped else { throw CancellationError() }
        guard let name = params["name"]?.stringValue,
            let index = session.tools.indices.first(where: {
                OpenCodeMCPLaunch.toolName(at: $0) == name
            }),
            params["arguments"] == nil || params["arguments"]?.objectValue != nil
        else { return toolResult("Unknown tool or invalid arguments.", isError: true) }
        let tool = session.tools[index]
        if invoking {
            try await withCheckedThrowingContinuation { waiting.append($0) }
        } else {
            invoking = true
        }
        defer {
            if waiting.isEmpty { invoking = false } else { waiting.removeFirst().resume() }
        }
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        let arguments = params["arguments"]?.objectValue ?? [:]
        if let limit = session.maxCalls, calls >= limit {
            failure(String(localized: "Stopped after \(limit) rounds of tool calls."))
            stop()
            throw CancellationError()
        }
        guard spent < AIToolLoopProvider.maxTurnResultBytes else {
            failure(String(localized: "\(InstalledAIKind.openCode.title) returned an oversized response."))
            stop()
            throw CancellationError()
        }
        calls += 1
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: arguments.mapValues(\.jsonObject))
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw HTTPFailure(status: "400 Bad Request")
        }
        let call = AIToolCall(id: id, name: tool.name, arguments: encoded)
        event(.toolCall(id: id, origin: tool.origin, title: tool.title))
        let result = await session.invoke(call)
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        event(.toolResult(id: id, isError: result.isError))
        let bounded = AIToolLoopProvider.bounded(result, spent: &spent)
        return toolResult(bounded.content, isError: bounded.isError)
    }

    private func toolResult(_ text: String, isError: Bool) -> JSONValue {
        .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(isError)
        ])
    }

    private func send(
        _ connection: NetworkConnection<TCP>, status: String, body: Data?
    ) async throws {
        let body = body ?? Data()
        var response = Data(
            ("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
                + "Cache-Control: no-store\r\nConnection: close\r\n"
                + "Content-Length: \(body.count)\r\n\r\n").utf8)
        response.append(body)
        try await connection.send(response, endOfStream: true)
    }
}
