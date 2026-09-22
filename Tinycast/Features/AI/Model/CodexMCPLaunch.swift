import Foundation

/// Tinycast's servers as `codex app-server` launch overrides; nothing reaches `~/.codex`.
enum CodexMCPLaunch {
    /// Codex's name for a Tinycast server; `-c` merges into a same-named table of the reader's.
    static func serverName(for handle: String) -> String { serverPrefix + handle }

    /// The handle behind a name Codex reports, or `nil` for a server that is not Tinycast's.
    static func handle(ofServer name: String) -> String? {
        guard name.hasPrefix(serverPrefix), name.count > serverPrefix.count else { return nil }
        return String(name.dropFirst(serverPrefix.count))
    }

    private static let serverPrefix = "tinycast-"

    /// The names `codex mcp list --json` reported, or `nil` for output that is not that list.
    static func foreignNames(listing: String) -> [String]? {
        guard let entries = JSONValue(data: Data(listing.utf8))?.arrayValue else { return nil }
        var names: [String] = []
        for entry in entries {
            guard let name = entry.objectValue?["name"]?.stringValue else { return nil }
            names.append(name)
        }
        return names
    }

    /// A reader's server `-c` cannot switch off: a dot or `=` splits the key it would be named by.
    static func unaddressableName(_ foreignNames: [String]) -> String? {
        foreignNames.first { $0.contains(".") || $0.contains("=") }
    }

    /// A reader's server already named like an armed one of ours, which it would merge into.
    static func takenName(servers: [AIToolServer], foreignNames: [String]) -> String? {
        servers.map { serverName(for: $0.handle) }.first { foreignNames.contains($0) }
    }

    /// `-c` pairs for Tinycast's servers, and every one of the reader's own, disabled by name.
    static func arguments(servers: [AIToolServer], disabling foreignNames: [String]) -> [String] {
        var arguments: [String] = []
        for name in foreignNames {
            arguments += ["-c", "mcp_servers.\(name).enabled=false"]
        }
        for (index, server) in servers.enumerated() {
            let key = "mcp_servers.\(serverName(for: server.handle))"
            arguments += ["-c", "\(key).enabled=true"]
            // Codex runs a tool its server calls read-only unasked; trust is Tinycast's call.
            arguments += ["-c", "\(key).default_tools_approval_mode=\(quoted("prompt"))"]
            switch server.transport {
            case .command(let path, let commandArguments, let environment):
                let launch = command(
                    path: path, arguments: commandArguments, environment: environment,
                    server: index)
                arguments += ["-c", "\(key).command=\(quoted(launch.path))"]
                arguments += ["-c", "\(key).args=\(array(launch.arguments))"]
                let names = forwardedNames(environment).indices.map {
                    variable(server: index, key: $0)
                }
                arguments += ["-c", "\(key).env_vars=\(array(names))"]
            case .url(let url, let headerName, let headerValue):
                arguments += ["-c", "\(key).url=\(quoted(url))"]
                guard !headerValue.isEmpty else { continue }
                let name = variable(server: index, key: 0)
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

    /// The values the overrides name, off argv; `nil` refuses a launch where two would share one.
    static func environment(servers: [AIToolServer]) -> [String: String]? {
        var pairs: [(name: String, value: String)] = []
        for (index, server) in servers.enumerated() {
            switch server.transport {
            case .command(_, _, let environment):
                for (key, name) in forwardedNames(environment).enumerated() {
                    pairs.append((variable(server: index, key: key), environment[name] ?? ""))
                }
            case .url(_, let headerName, let headerValue):
                guard !headerValue.isEmpty else { continue }
                let value = bearerToken(headerName: headerName, headerValue: headerValue)
                pairs.append((variable(server: index, key: 0), value ?? headerValue))
            }
        }
        return distinct(pairs)
    }

    /// One value per variable, or `nil`: a repeated name would hand one server another's secret.
    static func distinct(_ pairs: [(name: String, value: String)]) -> [String: String]? {
        var result: [String: String] = [:]
        for pair in pairs {
            guard result.updateValue(pair.value, forKey: pair.name) == nil else { return nil }
        }
        return result
    }

    /// Codex cannot rename a forwarded variable, so `/bin/sh` moves each to its server's name.
    static func command(
        path: String, arguments: [String], environment: [String: String], server index: Int
    ) -> (path: String, arguments: [String]) {
        let names = forwardedNames(environment)
        guard !names.isEmpty else { return (path, arguments) }
        let derived = names.indices.map { variable(server: index, key: $0) }
        // Read all before any export: a server's own key may be spelled like a derived name.
        let capture = "set -- " + derived.map { "\"$\($0)\"" }.joined(separator: " ") + #" "$@""#
        let exports = names.enumerated().map { key, name in "export \(name)=\"${\(key + 1)}\"" }
        let script =
            ([capture, "unset " + derived.joined(separator: " ")] + exports
            + ["shift \(names.count)", #"exec "$@""#]).joined(separator: "; ")
        return ("/bin/sh", ["-c", script, "tinycast-mcp", path] + arguments)
    }

    /// Only a name `export` accepts can reach the server; any other is not forwarded at all.
    private static func forwardedNames(_ environment: [String: String]) -> [String] {
        environment.keys.sorted().filter(isShellName)
    }

    private static func isShellName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else {
            return false
        }
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    /// Positions rather than a spelling of handle and key, which two servers could share.
    static func variable(server: Int, key: Int) -> String {
        "TC_MCP_\(server)_\(key)"
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

    /// A TOML basic string, escaped per scalar: CRLF is one `Character` and would slip through.
    static func quoted(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                let hex = String(scalar.value, radix: 16, uppercase: true)
                escaped += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"" + escaped + "\""
    }
}

/// The one server request Tinycast answers, whether an MCP tool call may run; all else is declined.
struct CodexElicitation: Equatable, Sendable {
    /// What the reply says. `persist` is never sent: only Settings may change a standing decision.
    enum Action: String, Sendable {
        case accept
        case decline
    }

    let serverName: String
    /// The thread asking, so the answer comes from the chat whose turn made the call.
    let threadID: String?
    let toolName: String
    /// `_meta.tool_name`, when Codex sends it: the only name tied to this call and not the latest.
    let namedTool: String?

    /// `nil` for every other elicitation — a form, a sampling request — which stays declined.
    init?(params: [String: JSONValue]) {
        guard let serverName = params["serverName"]?.stringValue, !serverName.isEmpty else {
            return nil
        }
        let meta = params["_meta"]?.objectValue ?? [:]
        guard meta["codex_approval_kind"]?.stringValue == "mcp_tool_call" else { return nil }
        self.serverName = serverName
        threadID = params["threadId"]?.stringValue
        namedTool = meta["tool_name"]?.stringValue
        toolName =
            namedTool ?? meta["tool_title"]?.stringValue
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
