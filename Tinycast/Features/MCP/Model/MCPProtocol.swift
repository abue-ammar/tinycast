import Foundation

/// JSON-RPC 2.0 as MCP speaks it: one encoder for both transports, newline framing for stdio.
enum MCPProtocol {
    enum Message: Equatable {
        case response(id: Int, result: JSONValue)
        case failure(id: Int, message: String)
        case notification(method: String, params: JSONValue)
        case request(id: JSONValue, method: String)
        case invalid
    }

    static let version = "2025-06-18"
    /// What Tinycast can speak; a server answering `initialize` with one of these is held to it.
    static let supportedVersions: Set<String> = ["2025-06-18", "2025-03-26", "2024-11-05"]
    /// A page cap, so a server that keeps handing back a cursor cannot hold the handshake forever.
    static let maxListPages = 50

    /// A first `npx -y` or `uvx` downloads before `initialize` answers; a browser tool outlasts 60 s.
    static func timeout(for method: String) -> Duration {
        switch method {
        case "initialize": return .seconds(120)
        case "tools/call": return .seconds(300)
        default: return .seconds(30)
        }
    }

    static func request(
        id: Int, method: String, params: [String: Any]? = nil, newlineTerminated: Bool = false
    ) throws -> Data {
        var object: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { object["params"] = params }
        return try encode(object, newlineTerminated: newlineTerminated)
    }

    static func notification(
        method: String, params: [String: Any]? = nil, newlineTerminated: Bool = false
    ) throws -> Data {
        var object: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { object["params"] = params }
        return try encode(object, newlineTerminated: newlineTerminated)
    }

    /// A server's `ping` must be answered or it may hang up; every other request is declined.
    static func reply(
        toRequest id: JSONValue, method: String, newlineTerminated: Bool = false
    ) throws -> Data {
        guard method == "ping" else { return try decline(id: id, newlineTerminated: newlineTerminated) }
        return try encode(
            ["jsonrpc": "2.0", "id": id.jsonObject, "result": [String: Any]()],
            newlineTerminated: newlineTerminated)
    }

    /// The version the server chose, which every later HTTP request has to name in its header.
    static func negotiatedVersion(_ initializeResult: JSONValue) -> String {
        guard let chosen = initializeResult.objectValue?["protocolVersion"]?.stringValue,
            supportedVersions.contains(chosen)
        else { return version }
        return chosen
    }

    /// `tools/list` pages: an absent or empty `nextCursor` is the last page.
    static func nextCursor(_ result: JSONValue) -> String? {
        guard let cursor = result.objectValue?["nextCursor"]?.stringValue, !cursor.isEmpty else {
            return nil
        }
        return cursor
    }

    /// Tinycast exposes nothing back, so a server request is always declined the same way.
    static func decline(id: JSONValue, newlineTerminated: Bool = false) throws -> Data {
        try encode(
            [
                "jsonrpc": "2.0", "id": id.jsonObject,
                "error": ["code": -32_601, "message": "Tinycast exposes no MCP capabilities."]
            ],
            newlineTerminated: newlineTerminated)
    }

    static func parse(_ data: Data) -> Message {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .invalid
        }
        let numericID = (object["id"] as? NSNumber).flatMap {
            CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue
        }
        if let method = object["method"] as? String {
            guard let id = object["id"], !(id is NSNull) else {
                return .notification(method: method, params: JSONValue(object["params"] ?? [:]))
            }
            return .request(id: JSONValue(id), method: method)
        }
        guard let id = numericID else { return .invalid }
        if let error = object["error"] as? [String: Any] {
            return .failure(id: id, message: error["message"] as? String ?? "The server failed.")
        }
        guard let result = object["result"] else { return .invalid }
        return .response(id: id, result: JSONValue(result))
    }

    private static func encode(_ object: [String: Any], newlineTerminated: Bool) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object)
        if newlineTerminated { data.append(0x0A) }
        return data
    }
}
