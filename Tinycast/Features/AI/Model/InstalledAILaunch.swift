import Foundation

/// What the reader set for one installed tool: where its command is and what it is launched with.
struct InstalledAIOverride: Codable, Equatable, Sendable {
    /// Empty leaves finding the command to `ExecutableLocator`.
    var commandPath = ""
    /// Names only, in the reader's order; a value is often a key, so values live in the Keychain.
    var environmentNames: [String] = []

    var isEmpty: Bool { commandPath.isEmpty && environmentNames.isEmpty }
}

/// One variable as the reader edits it: the name from settings, the value from the Keychain.
struct InstalledAIVariable: Equatable, Sendable {
    var name: String
    var value: String
}

/// Where the variables' values are kept, behind closures so a harness needs no Keychain.
struct InstalledAIEnvironmentStore: Sendable {
    /// Throws when the values cannot be read, so an editor never takes that for none being set.
    var values: @Sendable (InstalledAIKind) throws -> [String: String]
    var save: @Sendable ([String: String], InstalledAIKind) throws -> Void

    /// Holds nothing and keeps nothing, for a store built without one.
    static let none = InstalledAIEnvironmentStore(values: { _ in [:] }, save: { _, _ in })
}

/// An override resolved for one launch: the path checked, the variables' values read.
struct InstalledAILaunch: Equatable, Sendable {
    enum Command: Equatable, Sendable {
        /// No path was set, so the command is looked up the way a Terminal would find it.
        case automatic
        case executable(URL)
        /// A path was set and nothing runnable is there; the lookup is not a fallback for it.
        case missing(path: String)
    }

    var commandPath = ""
    var environment: [String: String] = [:]

    init(commandPath: String = "", environment: [String: String] = [:]) {
        self.commandPath = commandPath
        self.environment = environment
    }

    /// The set path wins or fails: falling back would hide the mistake the path was set to fix.
    func command(
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Command {
        let trimmed = commandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .automatic }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), isExecutable(expanded) else {
            return .missing(path: trimmed)
        }
        return .executable(URL(fileURLWithPath: expanded))
    }

    /// What a launch inherits: the app's variables under the reader's, minus those Tinycast sets.
    func inherited(
        for kind: InstalledAIKind,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let mine = environment.filter {
            Self.isVariableName($0.key) && !kind.isManagedVariable($0.key)
        }
        return base.merging(mine) { _, new in new }
    }

    static func missingCommandMessage(_ path: String) -> String {
        "Nothing can be run at \(path). Check the command path."
    }

    nonisolated static func isVariableName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else {
            return false
        }
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}

extension InstalledAIKind {
    /// Set on every chat launch to keep the tool inside the chat; a reader's value never wins.
    var managedEnvironment: [String: String] {
        switch self {
        case .claude:
            return ["CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1", "ENABLE_CLAUDEAI_MCP_SERVERS": "false"]
        case .openCode:
            return [
                "OPENCODE_CONFIG_CONTENT": Self.openCodeConfiguration,
                "OPENCODE_AUTO_SHARE": "false",
                "OPENCODE_DISABLE_AUTOUPDATE": "true"
            ]
        case .grok:
            return ["GROK_DISABLE_AUTOUPDATER": "1", "GROK_AGENT_DASHBOARD": "0"]
        case .cursor, .codex:
            return [:]
        }
    }

    /// `NO_COLOR` keeps output parseable; `TC_MCP_` names carry Tinycast's MCP secrets to Codex.
    func isManagedVariable(_ name: String) -> Bool {
        name == "NO_COLOR" || name.hasPrefix("TC_MCP_") || managedEnvironment[name] != nil
    }

    private static let openCodeConfiguration = """
        {"permission":"deny","share":"disabled","agent":{"build":{"permission":"deny"},\
        "plan":{"permission":"deny"}}}
        """
}
