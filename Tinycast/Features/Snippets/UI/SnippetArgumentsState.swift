import Observation

/// A class, so the caller can read the `{argument}` values back after the dialog.
@MainActor
@Observable
final class SnippetArgumentsState {
    let arguments: [SnippetTemplateEngine.MissingArgument]
    var texts: [String]
    /// One per argument, an index rather than a value: an `options=` list may repeat one.
    var choices: [Int]
    /// Nil until the dialog turns key, since AppKit's own first-responder pick would win.
    var focusedIndex: Int?

    init(arguments: [SnippetTemplateEngine.MissingArgument]) {
        self.arguments = arguments
        texts = Array(repeating: "", count: arguments.count)
        // An options list has no empty state, so it starts on its first choice.
        choices = Array(repeating: 0, count: arguments.count)
    }

    var values: [String: String] {
        var values: [String: String] = [:]
        for (index, argument) in arguments.enumerated() {
            values[argument.name] =
                argument.options.isEmpty ? texts[index] : argument.options[choices[index]]
        }
        return values
    }

    var asksOnlyForChoices: Bool {
        arguments.allSatisfy { !$0.options.isEmpty }
    }

    var showsNames: Bool {
        arguments.count > 1 || arguments.first?.name != SnippetTemplateEngine.defaultArgumentName
    }

    func focusFirstArgument() {
        focusedIndex = arguments.isEmpty ? nil : 0
    }

    func moveFocus(backwards: Bool) {
        guard let index = focusedIndex, !arguments.isEmpty else { return focusFirstArgument() }
        let step = backwards ? arguments.count - 1 : 1
        focusedIndex = (index + step) % arguments.count
    }

    func moveChoice(at index: Int, by delta: Int) {
        let options = arguments[index].options
        guard !options.isEmpty else { return }
        choices[index] = min(max(choices[index] + delta, 0), options.count - 1)
    }
}
