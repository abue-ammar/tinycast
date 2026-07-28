import Combine
import Foundation

struct CustomCommand: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "custom-command:"

    let id: UUID
    var name: String
    var command: String

    init(id: UUID = UUID(), name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
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

    @discardableResult
    func add(name: String, command: String) throws -> CustomCommand {
        let value = try validated(id: UUID(), name: name, command: command)
        commit(commands + [value])
        return value
    }

    func update(id: UUID, name: String, command: String) throws {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
        let value = try validated(id: id, name: name, command: command)
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

    private func validated(id: UUID, name: String, command: String) throws -> CustomCommand {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw CustomCommandValidationError.emptyName }
        guard !cleanCommand.isEmpty else { throw CustomCommandValidationError.emptyCommand }
        guard !cleanName.contains("\0"), !cleanCommand.contains("\0") else {
            throw CustomCommandValidationError.invalidCharacter
        }
        guard
            !commands.contains(where: {
                $0.id != id && $0.name.compare(cleanName, options: .caseInsensitive) == .orderedSame
            })
        else { throw CustomCommandValidationError.duplicateName }
        return CustomCommand(id: id, name: cleanName, command: cleanCommand)
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
            let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = value.command.trimmingCharacters(in: .whitespacesAndNewlines)
            let foldedName = name.folding(options: [.caseInsensitive], locale: .current)
            guard !name.isEmpty, !command.isEmpty, !name.contains("\0"), !command.contains("\0"),
                ids.insert(value.id).inserted, names.insert(foldedName).inserted
            else { continue }
            result.append(CustomCommand(id: value.id, name: name, command: command))
        }
        return result
    }
}
