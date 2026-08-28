import Foundation

/// The custom command waiting on its argument values, filled one at a time in the palette's own
/// search field. docs/features/custom-commands.md
@MainActor
@Observable
final class CustomCommandArgumentSession {
    private struct Request {
        let command: CustomCommand
        /// Positional and append-only: `values[0]` is the command's `$1`.
        var values: [String]
    }

    private var request: Request?

    var isActive: Bool { request != nil }
    var command: CustomCommand? { request?.command }

    /// The argument being asked for; nil once every one has an answer.
    var current: CustomCommandArgument? {
        guard let request, request.command.arguments.indices.contains(request.values.count) else {
            return nil
        }
        return request.command.arguments[request.values.count]
    }

    /// True when submitting runs rather than advances, which is what the ↵ pill announces.
    var isLastArgument: Bool {
        guard let request else { return false }
        return request.values.count == request.command.arguments.count - 1
    }

    /// Nil once nothing is pending, which leaves the mode's own placeholder in the search field.
    var prompt: String? { current.map { "\($0.name)…" } }

    /// Every argument in order, paired with what has been entered so far — the form's own rows.
    var progress: [(argument: CustomCommandArgument, value: String?)] {
        guard let request else { return [] }
        return request.command.arguments.enumerated().map { index, argument in
            (argument, index < request.values.count ? request.values[index] : nil)
        }
    }

    func begin(command: CustomCommand) {
        request = Request(command: command, values: [])
    }

    /// Records `value`, returning the command and its full argument list once the last one lands.
    func submit(_ value: String) -> (command: CustomCommand, values: [String])? {
        guard var request, current != nil else { return nil }
        request.values.append(value)
        self.request = request
        guard request.values.count == request.command.arguments.count else { return nil }
        return (request.command, request.values)
    }

    /// Steps back, returning the held value so the field refills; nil at the first argument.
    func retreat() -> String? {
        guard var request, !request.values.isEmpty else { return nil }
        let previous = request.values.removeLast()
        self.request = request
        return previous
    }

    func cancel() {
        request = nil
    }
}
