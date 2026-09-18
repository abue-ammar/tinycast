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

    /// Cursor's CLI has no empty-MCP-config flag, so the person enabling it has to be told.
    var isolationCaveat: String? {
        switch self {
        case .cursor: return "Ask mode · your Cursor MCP servers still apply"
        case .codex, .claude, .grok, .openCode: return nil
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

    static let claude: [InstalledAIModel] = [
        InstalledAIModel(id: "sonnet", name: "Claude Sonnet", efforts: claudeEfforts),
        InstalledAIModel(id: "opus", name: "Claude Opus", efforts: claudeEfforts),
        InstalledAIModel(id: "haiku", name: "Claude Haiku")
    ]

    private static let claudeEfforts = ["low", "medium", "high", "xhigh", "max"].map {
        ChatGPTSubscription.Effort(id: $0, detail: nil)
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
