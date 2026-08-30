import Foundation

/// The quicklink waiting on its `{argument}` values. docs/features/quicklinks.md
@MainActor
@Observable
final class QuicklinkArgumentSession {
    struct Request {
        let quicklink: Quicklink
        let context: SnippetTemplateEngine.ExpansionContext
        let encoding: SnippetTemplateEngine.ValueEncoding
        let arguments: [SnippetTemplateEngine.MissingArgument]
        var values: [String: String]
        var index: Int
    }

    private(set) var request: Request?

    var isActive: Bool { request != nil }
    var quicklinkName: String? { request?.quicklink.name }

    var current: SnippetTemplateEngine.MissingArgument? {
        guard let request, request.arguments.indices.contains(request.index) else { return nil }
        return request.arguments[request.index]
    }

    /// The options to choose from, or empty when the argument takes free text.
    var options: [String] { current?.options ?? [] }

    /// True when submitting opens rather than advances, which is what the ↵ pill announces.
    var isLastArgument: Bool {
        guard let request else { return false }
        return request.index == request.arguments.count - 1
    }

    var prompt: String { current.map { "\($0.name)…" } ?? PaletteMode.quicklinkArguments.placeholder }

    /// Every argument, in order, paired with what has been entered so far — the form's own rows.
    var progress: [(name: String, value: String?)] {
        guard let request else { return [] }
        return request.arguments.map { ($0.name, request.values[$0.name]) }
    }

    /// `values` holds what a caller filled in already; the form asks only for `arguments`.
    func begin(
        quicklink: Quicklink,
        context: SnippetTemplateEngine.ExpansionContext,
        encoding: SnippetTemplateEngine.ValueEncoding,
        arguments: [SnippetTemplateEngine.MissingArgument],
        values: [String: String] = [:]
    ) {
        request = Request(
            quicklink: quicklink, context: context, encoding: encoding, arguments: arguments,
            values: values, index: 0)
    }

    /// Records `value`, returning the complete set once the last argument is filled.
    func submit(_ value: String) -> [String: String]? {
        guard var request, let argument = current else { return nil }
        request.values[argument.name] = value
        request.index += 1
        self.request = request
        guard request.index >= request.arguments.count else { return nil }
        return request.values
    }

    /// Steps back, returning the held value so the field refills; false at the start.
    func retreat() -> String? {
        guard var request, request.index > 0 else { return nil }
        request.index -= 1
        let previous = request.arguments[request.index].name
        let value = request.values[previous]
        request.values[previous] = nil
        self.request = request
        return value ?? ""
    }

    func cancel() {
        request = nil
    }
}
