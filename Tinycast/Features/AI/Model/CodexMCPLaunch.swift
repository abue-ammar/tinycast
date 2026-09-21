import Foundation

/// Tinycast's servers as `codex app-server` launch overrides, and the elicitation they answer.
/// Every value here is process-scoped: nothing reaches `~/.codex/config.toml`.
enum CodexMCPLaunch {
    /// `-c` pairs for the servers Tinycast supplies, plus each of the user's own, disabled by name.
    /// A name the user's configuration does not define cannot be disabled — the whole config then
    /// fails to load — so `foreignNames` is what `mcp mcp list` reported under these same flags.
    static func arguments(servers: [AIToolServer], disabling foreignNames: [String]) -> [String] {
        var arguments: [String] = []
        for name in foreignNames where !servers.contains(where: { $0.handle == name }) {
            arguments += ["-c", "mcp_servers.\(name).enabled=false"]
        }
        for server in servers {
            let key = "mcp_servers.\(server.handle)"
            arguments += ["-c", "\(key).enabled=true"]
            // Codex's default runs a tool its server marks read-only unasked; trust is Tinycast's call.
            arguments += ["-c", "\(key).default_tools_approval_mode=\(quoted("prompt"))"]
            switch server.transport {
            case .command(let path, let commandArguments, let environment):
                let launch = command(
                    path: path, arguments: commandArguments, handle: server.handle,
                    names: environment.keys.sorted())
                arguments += ["-c", "\(key).command=\(quoted(launch.path))"]
                arguments += ["-c", "\(key).args=\(array(launch.arguments))"]
                let names = environment.keys.sorted().map { variable(server.handle, $0) }
                arguments += ["-c", "\(key).env_vars=\(array(names))"]
            case .url(let url, let headerName, let headerValue):
                arguments += ["-c", "\(key).url=\(quoted(url))"]
                let name = variable(server.handle, headerName)
                if bearerToken(headerName: headerName, headerValue: headerValue) != nil {
                    arguments += ["-c", "\(key).bearer_token_env_var=\(quoted(name))"]
                } else {
                    arguments += [
                        "-c", "\(key).env_http_headers={\(quoted(headerName))=\(quoted(name))}"
                    ]
                }
            }
        }
        return arguments
    }

    /// The values the overrides above name. They ride the app-server's own environment because
    /// `ps` shows everything on argv, and Codex hands a stdio server nothing it was not named.
    static func environment(servers: [AIToolServer]) -> [String: String] {
        var result: [String: String] = [:]
        for server in servers {
            switch server.transport {
            case .command(_, _, let environment):
                for (key, value) in environment { result[variable(server.handle, key)] = value }
            case .url(_, let headerName, let headerValue):
                result[variable(server.handle, headerName)] =
                    bearerToken(headerName: headerName, headerValue: headerValue) ?? headerValue
            }
        }
        return result
    }

    /// Codex cannot rename a forwarded variable, so `/bin/sh` moves each to its server's name.
    static func command(
        path: String, arguments: [String], handle: String, names: [String]
    ) -> (path: String, arguments: [String]) {
        let renamed = names.filter(isShellName)
        guard !renamed.isEmpty else { return (path, arguments) }
        let moves = renamed.map { name in
            let derived = variable(handle, name)
            return "export \(name)=\"$\(derived)\"; unset \(derived)"
        }
        let script = (moves + [#"exec "$@""#]).joined(separator: "; ")
        return ("/bin/sh", ["-c", script, "tinycast-mcp", path] + arguments)
    }

    /// What `export` accepts; any other name stays under its derived one, as it always has here.
    private static func isShellName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else {
            return false
        }
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    /// Prefixed and derived, so a server's own variable names can never shadow the child's PATH.
    static func variable(_ handle: String, _ key: String) -> String {
        let sanitized = (handle + "_" + key).uppercased().map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "_"
        }
        return "TC_MCP_" + String(sanitized)
    }

    /// Codex composes `Bearer` itself, so only the bare token goes in the variable it reads.
    private static func bearerToken(headerName: String, headerValue: String) -> String? {
        guard headerName.caseInsensitiveCompare("Authorization") == .orderedSame,
            headerValue.count > 7,
            headerValue.prefix(7).caseInsensitiveCompare("Bearer ") == .orderedSame
        else { return nil }
        return String(headerValue.dropFirst(7))
    }

    private static func array(_ values: [String]) -> String {
        "[" + values.map(quoted).joined(separator: ",") + "]"
    }

    /// A TOML basic string: `-c` parses the value as TOML and only falls back to a raw literal.
    private static func quoted(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"" + escaped + "\""
    }
}

/// The one server request Tinycast answers: may this MCP tool call run? Everything else is declined.
struct CodexElicitation: Equatable, Sendable {
    /// What the reply says. `persist` is never sent: only Settings may change a standing decision.
    enum Action: String, Sendable {
        case accept
        case decline
    }

    let serverName: String
    let toolName: String

    /// `nil` for every other elicitation — a form, a sampling request — which stays declined.
    init?(params: [String: JSONValue]) {
        guard let serverName = params["serverName"]?.stringValue, !serverName.isEmpty else {
            return nil
        }
        let meta = params["_meta"]?.objectValue ?? [:]
        guard meta["codex_approval_kind"]?.stringValue == "mcp_tool_call" else { return nil }
        self.serverName = serverName
        toolName =
            meta["tool_name"]?.stringValue ?? meta["tool_title"]?.stringValue
            ?? Self.quotedName(in: params["message"]?.stringValue ?? "") ?? "a tool"
    }

    /// The message names the tool in quotes; it is the last resort when `_meta` carried neither.
    private static func quotedName(in message: String) -> String? {
        guard let open = message.firstIndex(of: "\u{201C}"),
            let close = message.lastIndex(of: "\u{201D}"), open < close
        else { return nil }
        let name = message[message.index(after: open)..<close]
        return name.isEmpty ? nil : String(name)
    }
}
