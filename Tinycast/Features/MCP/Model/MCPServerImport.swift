import Foundation

/// The `mcpServers` JSON that Raycast, Claude Desktop, Cursor and VS Code share, read into servers.
enum MCPServerImport {
    struct Entry: Equatable, Sendable {
        var server: MCPServer
        var headerValue: String
        var environment: [String: String]
        /// What the shape carried that a Tinycast server has nowhere to keep, named for the reader.
        var dropped: [String]
    }

    /// What an import did, in the sentence Settings shows under the button.
    struct Summary: Equatable, Sendable {
        var added: Int
        var skipped: Int
        var dropped: [String]

        var message: String {
            var parts = [added == 1 ? "Imported 1 server." : "Imported \(added) servers."]
            if skipped > 0 {
                parts.append(skipped == 1 ? "1 was already set up." : "\(skipped) were already set up.")
            }
            if !dropped.isEmpty { parts.append("Not kept: \(dropped.joined(separator: ", ")).") }
            return parts.joined(separator: " ")
        }
    }

    enum Failure: LocalizedError, Equatable {
        case notJSON
        case noServers

        var errorDescription: String? {
            switch self {
            case .notJSON: return "The clipboard does not hold MCP configuration JSON."
            case .noServers: return "That JSON names no MCP server with a command or a URL."
            }
        }
    }

    static func parse(_ text: String) throws -> [Entry] {
        guard let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.notJSON }
        let entries = servers(in: root).compactMap { name, config in entry(name: name, config) }
        guard !entries.isEmpty else { throw Failure.noServers }
        return entries
    }

    /// `mcpServers` (Raycast, Claude, Cursor), `servers` (VS Code), a bare map, or one server.
    private static func servers(in root: [String: Any]) -> [(String, [String: Any])] {
        for key in ["mcpServers", "servers", "mcp_servers"] {
            if let map = root[key] as? [String: Any] { return named(map) }
        }
        if isServer(root) {
            return [((root["name"] as? String) ?? "Imported server", root)]
        }
        return named(root)
    }

    private static func named(_ map: [String: Any]) -> [(String, [String: Any])] {
        map.keys.sorted().compactMap { name in
            (map[name] as? [String: Any]).map { (name, $0) }
        }
    }

    private static func isServer(_ object: [String: Any]) -> Bool {
        object["command"] is String || object["url"] is String || object["serverUrl"] is String
    }

    private static func entry(name: String, _ config: [String: Any]) -> Entry? {
        var dropped: [String] = []
        let isEnabled = (config["disabled"] as? Bool) != true
        if let url = (config["url"] as? String) ?? (config["serverUrl"] as? String),
            !url.trimmingCharacters(in: .whitespaces).isEmpty
        {
            let headers = (config["headers"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            let headerName =
                headers.keys.first { $0.caseInsensitiveCompare("Authorization") == .orderedSame }
                ?? headers.keys.sorted().first ?? MCPTransportKind.defaultHeaderName
            dropped += headers.keys.filter { $0 != headerName }.sorted().map { "header \($0)" }
            let server = MCPServer(
                name: name,
                transport: .http(url: url.trimmingCharacters(in: .whitespaces), headerName: headerName),
                isEnabled: isEnabled)
            return Entry(
                server: server, headerValue: headers[headerName] ?? "", environment: [:],
                dropped: dropped)
        }
        guard var command = (config["command"] as? String)?.trimmingCharacters(in: .whitespaces),
            !command.isEmpty
        else { return nil }
        var arguments = (config["args"] as? [Any] ?? []).map { "\($0)" }
        // `"command": "npx -y pkg"` with no args is common in hand-written configs.
        if config["args"] == nil, !command.hasPrefix("/"), command.contains(" ") {
            let words = command.split(separator: " ").map(String.init)
            command = words[0]
            arguments = Array(words.dropFirst())
        }
        let environment = (config["env"] as? [String: Any] ?? [:]).compactMapValues { value in
            value is String || value is NSNumber ? "\(value)" : nil
        }
        if config["cwd"] != nil { dropped.append("cwd") }
        let server = MCPServer(
            name: name,
            transport: .stdio(
                command: command, arguments: arguments,
                environmentKeys: environment.keys.sorted()),
            isEnabled: isEnabled)
        return Entry(server: server, headerValue: "", environment: environment, dropped: dropped)
    }
}
