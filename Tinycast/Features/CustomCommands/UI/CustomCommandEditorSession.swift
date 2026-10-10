import SwiftUI

@MainActor
@Observable
final class CustomCommandEditorSession {
    enum Field: Hashable {
        case name, icon, command, workingDirectory, chooseDirectory, addArgument
        case argumentName(UUID), argumentOptional(UUID), removeArgument(UUID)
        case rootSearch, shellEnvironment, confirmation, successConfirmation, output
    }

    struct ArgumentDraft: Identifiable {
        let id = UUID()
        var name: String
        var isOptional: Bool
    }

    let original: CustomCommand?
    let id: UUID
    var name: String
    var shellCommand: String
    var workingDirectory: String
    var iconSymbol: String?
    var arguments: [ArgumentDraft]
    var showsInRootSearch: Bool
    var loadsShellEnvironment: Bool
    var requiresConfirmation: Bool
    var showsConfirmation: Bool
    var showsOutput: Bool
    var selection: TextSelection?
    var focusedField: Field = .name
    var errorMessage: String?

    init(command: CustomCommand?) {
        original = command
        id = command?.id ?? UUID()
        name = command?.name ?? ""
        shellCommand = command?.command ?? ""
        workingDirectory = command?.workingDirectory ?? ""
        iconSymbol = command?.iconSymbol
        arguments = (command?.arguments ?? []).map {
            ArgumentDraft(name: $0.name, isOptional: $0.isOptional)
        }
        showsInRootSearch = command?.showsInRootSearch ?? true
        loadsShellEnvironment = command?.loadsShellEnvironment ?? false
        requiresConfirmation = command?.requiresConfirmation ?? false
        showsConfirmation = command?.showsConfirmation ?? false
        showsOutput = command?.showsOutput ?? false
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !shellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func draft() -> CustomCommand {
        CustomCommand(
            id: id, name: name, command: shellCommand, isEnabled: original?.isEnabled ?? true,
            showsInRootSearch: showsInRootSearch,
            loadsShellEnvironment: loadsShellEnvironment, requiresConfirmation: requiresConfirmation,
            showsConfirmation: showsConfirmation,
            arguments: arguments.map { CustomCommandArgument(name: $0.name, isOptional: $0.isOptional) },
            showsOutput: showsOutput, workingDirectory: workingDirectory, iconSymbol: iconSymbol)
    }

    var focusOrder: [Field] {
        [.name, .icon, .command, .workingDirectory, .chooseDirectory]
            + arguments.flatMap { [.argumentName($0.id), .argumentOptional($0.id), .removeArgument($0.id)] }
            + (arguments.count < CustomCommandArgument.limit ? [.addArgument] : [])
            + [.rootSearch, .shellEnvironment, .confirmation, .successConfirmation, .output]
    }

    func advanceFocus(backwards: Bool) {
        let fields = focusOrder
        let index = fields.firstIndex(of: focusedField) ?? 0
        focusedField = fields[(index + (backwards ? fields.count - 1 : 1)) % fields.count]
    }

    func addArgument() {
        guard arguments.count < CustomCommandArgument.limit else { return }
        let argument = ArgumentDraft(name: "", isOptional: false)
        arguments.append(argument)
        focusedField = .argumentName(argument.id)
    }

    func removeArgument(id: UUID) {
        guard let index = arguments.firstIndex(where: { $0.id == id }) else { return }
        let removedFields: [Field] = [.argumentName(id), .argumentOptional(id), .removeArgument(id)]
        arguments.remove(at: index)
        if removedFields.contains(focusedField) {
            focusedField =
                arguments.isEmpty
                ? .addArgument : .argumentName(arguments[min(index, arguments.count - 1)].id)
        }
    }
}
