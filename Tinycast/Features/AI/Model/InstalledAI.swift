import Foundation

enum InstalledAIKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude
    case grok
    case openCode
    case cursor

    /// Claude, Grok, OpenCode and Cursor — Codex uses its app-server instead.
    static let managedCLIKinds: [InstalledAIKind] = [.claude, .grok, .openCode, .cursor]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .grok: return "Grok"
        case .openCode: return "OpenCode"
        case .cursor: return "Cursor"
        }
    }

    var command: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .grok: return "grok"
        case .openCode: return "opencode"
        case .cursor: return "agent"
        }
    }

    var installURL: URL {
        switch self {
        case .codex: return URL(string: "https://developers.openai.com/codex/cli")!
        case .claude: return URL(string: "https://code.claude.com/docs/en/setup")!
        case .grok: return URL(string: "https://x.ai/cli")!
        case .openCode: return URL(string: "https://opencode.ai/docs")!
        case .cursor: return URL(string: "https://cursor.com/docs/cli/overview")!
        }
    }

    /// Installs that put their command outside every shared `bin` the locator already walks.
    var extraExecutablePaths: [String] {
        switch self {
        case .claude: return [".claude/local/claude"]
        case .grok: return [".grok/bin/grok"]
        case .codex, .openCode, .cursor: return []
        }
    }

    var source: AIModelSource {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .grok: return .grok
        case .openCode: return .openCode
        case .cursor: return .cursor
        }
    }

    /// What the Providers row says: Cursor keeps the reader's MCP; a managed policy owns Claude's.
    func isolationCaveat(hasManagedMCPPolicy: Bool) -> String? {
        switch self {
        case .cursor: return "Ask mode · your Cursor MCP servers still apply"
        case .claude:
            return hasManagedMCPPolicy
                ? "MCP on this route is managed by your organization" : nil
        case .codex, .grok, .openCode: return nil
        }
    }

    var signInCommand: String {
        switch self {
        case .codex: return "codex login"
        case .claude: return "claude auth login"
        case .grok: return "grok login"
        case .openCode: return "opencode auth login"
        case .cursor: return "agent login"
        }
    }
}

extension AIModelSource {
    /// The installed command behind this source, or `nil` for the two routes Tinycast reaches itself.
    var installedKind: InstalledAIKind? {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .grok: return .grok
        case .openCode: return .openCode
        case .cursor: return .cursor
        case .appleIntelligence, .api: return nil
        }
    }
}

struct InstalledAIModel: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let efforts: [ChatGPTSubscription.Effort]

    init(id: String, name: String, efforts: [ChatGPTSubscription.Effort] = []) {
        self.id = id
        self.name = name
        self.efforts = efforts
    }

    func resolvedEffort(_ preferred: String?) -> String? {
        guard !efforts.isEmpty else { return nil }
        if let preferred, efforts.contains(where: { $0.id == preferred }) { return preferred }
        if efforts.contains(where: { $0.id == "high" }) { return "high" }
        return efforts.first?.id
    }

    /// What Claude's `initialize` control request asks for; the answer is its own `/model` list.
    static let claudeInitializeRequest =
        #"{"type":"control_request","request_id":"tinycast-models","request":{"subtype":"initialize"}}"#
        + "\n"

    static let claudeTitleRequestID = "tinycast-title"

    /// Claude Code's own session namer, asked without persisting anything to its history.
    static func claudeTitleRequest(_ description: String) -> String? {
        let request: [String: Any] = [
            "type": "control_request", "request_id": claudeTitleRequestID,
            "request": [
                "subtype": "generate_session_title", "description": description,
                "persist": false
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
            let line = String(bytes: data, encoding: .utf8)
        else { return nil }
        return line + "\n"
    }

    static func claudeTitle(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let response = object["response"] as? [String: Any],
                response["request_id"] as? String == claudeTitleRequestID,
                let payload = response["response"] as? [String: Any],
                let title = payload["title"] as? String
            else { continue }
            return title
        }
        return nil
    }

    /// The CLI's own picker, one row per resolved model: `default` only restates another entry.
    static func claudeCatalog(_ output: String) -> [InstalledAIModel] {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["type"] as? String == "control_response",
                let response = object["response"] as? [String: Any],
                let payload = response["response"] as? [String: Any],
                let entries = payload["models"] as? [[String: Any]]
            else { continue }
            var models: [InstalledAIModel] = []
            var resolved = Set<String>()
            for entry in entries {
                guard let id = entry["value"] as? String, !id.isEmpty, id != "default" else {
                    continue
                }
                let target = entry["resolvedModel"] as? String ?? id
                guard resolved.insert(target).inserted else { continue }
                models.append(
                    InstalledAIModel(
                        id: id, name: claudeName(entry, fallback: id),
                        efforts: (entry["supportedEffortLevels"] as? [String] ?? []).map {
                            ChatGPTSubscription.Effort(id: $0, detail: nil)
                        }))
            }
            return models
        }
        return []
    }

    /// "Opus 5.5 · Best for everyday…" names the version the alias points at today.
    private static func claudeName(_ entry: [String: Any], fallback: String) -> String {
        let described = (entry["description"] as? String)?
            .components(separatedBy: " · ").first?
            .trimmingCharacters(in: .whitespaces)
        let name = described.flatMap { $0.isEmpty ? nil : $0 }
            ?? entry["displayName"] as? String ?? fallback
        return name.hasPrefix("Claude") ? name : "Claude " + name
    }

    /// `/effort` advertises these four; a model only honours the ones it supports.
    private static let grokEfforts = ["low", "medium", "high", "xhigh"].map {
        ChatGPTSubscription.Effort(id: $0, detail: nil)
    }

    static func grokCatalog(_ output: String) -> [InstalledAIModel] {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var models: [InstalledAIModel] = []
        var seen = Set<String>()
        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("*") || line.hasPrefix("-") else { continue }
            let rest = line.drop(while: { $0 == "*" || $0 == "-" || $0.isWhitespace })
            let token = rest.split(whereSeparator: { $0.isWhitespace || $0 == "(" }).first
            guard let token, !token.isEmpty else { continue }
            let id = String(token)
            guard seen.insert(id).inserted else { continue }
            models.append(InstalledAIModel(id: id, name: id, efforts: grokEfforts))
        }
        return models
    }

    static func openCodeCatalog(_ output: String) -> [InstalledAIModel] {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var entries: [(String, [String])] = []
        var id: String?
        var objectLines: [String] = []

        func appendEntry() {
            guard let id else { return }
            let data = Data(objectLines.joined(separator: "\n").utf8)
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let variants = object?["variants"] as? [String: Any] ?? [:]
            entries.append((id, variants.keys.sorted(by: effortOrder)))
        }

        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw == line, line.contains("/"), !line.hasPrefix("{") {
                appendEntry()
                id = line
                objectLines = []
            } else if id != nil {
                objectLines.append(raw)
            }
        }
        appendEntry()
        return entries.map { id, efforts in
            InstalledAIModel(
                id: id, name: id,
                efforts: efforts.map { ChatGPTSubscription.Effort(id: $0, detail: nil) })
        }
    }

    /// `agent --list-models` lines look like `composer-2.5 - Composer 2.5`.
    static func cursorCatalog(_ output: String) -> [InstalledAIModel] {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var models: [InstalledAIModel] = []
        var seen = Set<String>()
        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.range(of: " - ") else { continue }
            let id = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            let name = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !name.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            models.append(InstalledAIModel(id: id, name: name))
        }
        return models
    }

    private static func effortOrder(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
        let left = order.firstIndex(of: lhs) ?? order.endIndex
        let right = order.firstIndex(of: rhs) ?? order.endIndex
        return left == right ? lhs < rhs : left < right
    }
}

struct InstalledAIStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case checking
        case ready
        case signInRequired
        case notInstalled
        case failed(String)
    }

    var phase: Phase = .idle
    var version: String?
    var executable: URL?
    var models: [InstalledAIModel] = []

    var isReady: Bool { phase == .ready && executable != nil && !models.isEmpty }
}
