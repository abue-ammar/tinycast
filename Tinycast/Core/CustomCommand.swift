import Combine
import Foundation

struct CustomCommand: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "custom-command:"

    let id: UUID
    var name: String
    var command: String
    /// Sources the user's shell config so aliases, functions and `PATH` resolve; opt-in because a heavy `.zshrc` costs far more than the command itself.
    var loadsShellEnvironment: Bool
    var requiresConfirmation: Bool

    init(
        id: UUID = UUID(), name: String, command: String,
        loadsShellEnvironment: Bool = false, requiresConfirmation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.loadsShellEnvironment = loadsShellEnvironment
        self.requiresConfirmation = requiresConfirmation
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
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
final class CustomCommandStore: ObservableObject {
    private static let defaultsKey = "customCommands"

    private let defaults: UserDefaults
    @Published private(set) var commands: [CustomCommand]
    var onChange: (([CustomCommand]) -> Void)?

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

    // Takes a whole draft rather than a parameter per field so adding an option doesn't churn every call site.
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

    /// Replaces the complete set during native-backup import, dropping invalid and duplicate records from hand-edited files.
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
