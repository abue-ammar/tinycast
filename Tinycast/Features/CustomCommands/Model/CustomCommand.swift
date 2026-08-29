import Foundation

/// Values are passed positionally, so what the user types is never re-parsed by zsh.
struct CustomCommandArgument: Codable, Hashable, Sendable {
    var name: String
    /// An optional argument may be submitted empty; a required one holds ↵ until it has a value.
    var isOptional: Bool

    init(name: String, isOptional: Bool = false) {
        self.name = name
        self.isOptional = isOptional
    }

    /// A blank name is dropped rather than rejected, so an import can't lose the whole command.
    static func sanitized(_ arguments: [CustomCommandArgument]) -> [CustomCommandArgument] {
        arguments.compactMap { argument in
            var cleaned = argument
            cleaned.name = argument.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0") else { return nil }
            return cleaned
        }
    }
}

struct CustomCommand: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "custom-command:"
    /// One glyph for every custom command, so every surface reads as the same thing.
    static let sfSymbol = "terminal"

    let id: UUID
    var name: String
    var command: String
    /// Sources the shell config so aliases resolve; opt-in, a heavy one costing more.
    var loadsShellEnvironment: Bool
    var requiresConfirmation: Bool
    var showsConfirmation: Bool
    /// Prompted for in order before the run; empty for the commands that take no input.
    var arguments: [CustomCommandArgument]
    /// Captures what the command prints and opens the output window once it exits.
    var showsOutput: Bool
    /// Kept abbreviated, so a `~` path survives a home directory that moves.
    var workingDirectory: String?
    /// The launcher glyph; nil falls back to the shared terminal symbol.
    var iconSymbol: String?

    init(
        id: UUID = UUID(), name: String, command: String,
        loadsShellEnvironment: Bool = false, requiresConfirmation: Bool = false,
        showsConfirmation: Bool = false, arguments: [CustomCommandArgument] = [],
        showsOutput: Bool = false, workingDirectory: String? = nil, iconSymbol: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.loadsShellEnvironment = loadsShellEnvironment
        self.requiresConfirmation = requiresConfirmation
        self.showsConfirmation = showsConfirmation
        self.arguments = arguments
        self.showsOutput = showsOutput
        self.workingDirectory = workingDirectory
        self.iconSymbol = iconSymbol
    }

    /// The glyph every surface draws for this command.
    var symbol: String { iconSymbol ?? Self.sfSymbol }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    // Hand-written, so an added field keeps stored commands and older backups readable.
    private enum CodingKeys: String, CodingKey {
        case id, name, command, loadsShellEnvironment, requiresConfirmation, showsConfirmation
        case arguments, showsOutput, workingDirectory, iconSymbol
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        loadsShellEnvironment =
            try container.decodeIfPresent(Bool.self, forKey: .loadsShellEnvironment) ?? false
        requiresConfirmation =
            try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
        showsConfirmation =
            try container.decodeIfPresent(Bool.self, forKey: .showsConfirmation) ?? false
        arguments =
            try container.decodeIfPresent([CustomCommandArgument].self, forKey: .arguments) ?? []
        showsOutput = try container.decodeIfPresent(Bool.self, forKey: .showsOutput) ?? false
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
    }
}

extension String {
    /// Trimmed, and nil when that leaves nothing — an empty optional field means "unset", not "".
    fileprivate var cleanedPathComponent: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("\0") ? nil : trimmed
    }
}

enum CustomCommandValidationError: LocalizedError {
    case emptyName
    case emptyCommand
    case duplicateName
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the command."
        case .emptyCommand: return "Enter a command to run."
        case .duplicateName: return "A custom command with this name already exists."
        case .invalidCharacter: return "Names and commands cannot contain null characters."
        }
    }
}

@MainActor
@Observable
final class CustomCommandStore {
    private static let defaultsKey = "customCommands"

    private let defaults: UserDefaults
    private(set) var commands: [CustomCommand]
    @ObservationIgnored var onChange: (([CustomCommand]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([CustomCommand].self, from: $0) } ?? []
        commands = Self.sanitized(decoded)
        if commands != decoded { persist() }
    }

    func command(id: UUID) -> CustomCommand? {
        commands.first { $0.id == id }
    }

    func command(entryID: String) -> CustomCommand? {
        CustomCommand.id(fromEntryID: entryID).flatMap(command)
    }

    // Takes a whole draft, so adding an option doesn't churn every call site.
    @discardableResult
    func add(_ draft: CustomCommand) throws -> CustomCommand {
        let value = try validated(draft)
        commit(commands + [value])
        return value
    }

    func update(_ draft: CustomCommand) throws {
        guard let index = commands.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = commands
        updated[index] = value
        commit(updated)
    }

    @discardableResult
    func remove(id: UUID) -> CustomCommand? {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = commands
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    /// Replaces the whole set on backup import, dropping invalid and duplicate records.
    @discardableResult
    func replace(with newCommands: [CustomCommand]) -> Int {
        let updated = Self.sanitized(newCommands)
        commit(updated)
        return updated.count
    }

    private func validated(_ draft: CustomCommand) throws -> CustomCommand {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        value.arguments = CustomCommandArgument.sanitized(draft.arguments)
        value.workingDirectory = draft.workingDirectory?.cleanedPathComponent
        value.iconSymbol = draft.iconSymbol?.cleanedPathComponent
        guard !value.name.isEmpty else { throw CustomCommandValidationError.emptyName }
        guard !value.command.isEmpty else { throw CustomCommandValidationError.emptyCommand }
        guard !value.name.contains("\0"), !value.command.contains("\0") else {
            throw CustomCommandValidationError.invalidCharacter
        }
        guard
            !commands.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw CustomCommandValidationError.duplicateName }
        return value
    }

    private func commit(_ updated: [CustomCommand]) {
        guard updated != commands else { return }
        commands = updated
        persist()
        onChange?(updated)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [CustomCommand]) -> [CustomCommand] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [CustomCommand] = []
        for value in values {
            // Copy-and-clean rather than rebuild, so a new option can never be dropped on import.
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.command = value.command.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.arguments = CustomCommandArgument.sanitized(value.arguments)
            cleaned.workingDirectory = value.workingDirectory?.cleanedPathComponent
            cleaned.iconSymbol = value.iconSymbol?.cleanedPathComponent
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: .current)
            guard !cleaned.name.isEmpty, !cleaned.command.isEmpty, !cleaned.name.contains("\0"),
                !cleaned.command.contains("\0"), ids.insert(cleaned.id).inserted,
                names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result
    }
}
