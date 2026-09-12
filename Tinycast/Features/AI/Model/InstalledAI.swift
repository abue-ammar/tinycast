import Foundation

enum InstalledAIKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude
    case openCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .openCode: return "OpenCode"
        }
    }

    var command: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .openCode: return "opencode"
        }
    }

    var installURL: URL {
        switch self {
        case .codex: return URL(string: "https://developers.openai.com/codex/cli")!
        case .claude: return URL(string: "https://code.claude.com/docs/en/setup")!
        case .openCode: return URL(string: "https://opencode.ai/docs")!
        }
    }

    /// The one install that puts its command outside every shared `bin` the locator already walks.
    var extraExecutablePaths: [String] {
        self == .claude ? [".claude/local/claude"] : []
    }

    var source: AIModelSource {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .openCode: return .openCode
        }
    }

    var signInCommand: String {
        switch self {
        case .codex: return "codex login"
        case .claude: return "claude auth login"
        case .openCode: return "opencode auth login"
        }
    }
}

extension AIModelSource {
    /// The installed command behind this source, or `nil` for the two routes Tinycast reaches itself.
    var installedKind: InstalledAIKind? {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .openCode: return .openCode
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
