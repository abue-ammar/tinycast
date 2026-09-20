import Foundation

/// Tinycast's servers as the Claude CLI's own MCP configuration, and the names it calls them by.
/// The file this writes is the only place the secrets go: `ps` would show anything on argv.
enum ClaudeMCPLaunch {
    static let toolPrefix = "mcp__"
    /// Per turn, like the Grok prompt file: a second turn must not overwrite, or delete, a live
    /// turn's configuration out from under the process reading it.
    static func configurationFileName(_ id: UUID = UUID()) -> String {
        "tinycast-mcp-\(id.uuidString).json"
    }
    private static let separator = "__"

    static func configuration(servers: [AIToolServer]) -> String {
        var entries: [String: Any] = [:]
        for server in servers {
            switch server.transport {
            case .command(let path, let arguments, let environment):
                entries[server.handle] = [
                    "command": path, "args": arguments, "env": environment
                ]
            case .url(let url, let headerName, let headerValue):
                entries[server.handle] = [
                    "type": "http", "url": url, "headers": [headerName: headerValue]
                ]
            }
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["mcpServers": entries], options: [.sortedKeys]),
            let text = String(bytes: data, encoding: .utf8)
        else { return #"{"mcpServers":{}}"# }
        return text
    }

    /// The flags that arm the servers. `--disallowedTools *` is deliberately absent: it removes
    /// the MCP tools along with the built-ins, and then the model narrates a call it never made.
    static func arguments(configurationPath: String, rounds: Int) -> [String] {
        [
            "--strict-mcp-config",
            "--mcp-config", configurationPath,
            "--permission-prompt-tool", "stdio",
            "--max-turns", "\(rounds)"
        ]
    }

    /// `mcp__<handle>__<tool>` back to the pair Tinycast addresses. A handle may hold `__` itself,
    /// so the tool is what the last separator names, exactly as the CLI composes it.
    static func route(_ wireName: String) -> AIToolServerCall? {
        guard wireName.hasPrefix(toolPrefix) else { return nil }
        let rest = wireName.dropFirst(toolPrefix.count)
        guard let separator = rest.range(of: Self.separator, options: .backwards) else { return nil }
        let handle = String(rest[..<separator.lowerBound])
        let tool = String(rest[separator.upperBound...])
        guard !handle.isEmpty, !tool.isEmpty else { return nil }
        return AIToolServerCall(handle: handle, tool: tool)
    }
}
