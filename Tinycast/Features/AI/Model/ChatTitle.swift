import Foundation

/// A chat's name as its model or harness gives it, once the first answer exists to name it by.
enum ChatTitle {
    static let maxLength = 60
    /// Enough of the first exchange to name it, never a whole pasted document.
    static let excerptLength = 800

    static let instructions = """
        Name this conversation in three to six words. Reply with the title only: no quotes, no \
        trailing punctuation, no preamble.
        """

    /// The first question, and its answer once there is one: named on send, it has only the first.
    static func description(of session: ChatSession) -> String? {
        guard let question = session.messages.first(where: { $0.role == .user }),
            !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let asked = "User: \(question.text.prefix(excerptLength))"
        guard
            let answer = session.messages.first(where: {
                $0.role == .assistant && $0.state == .complete && !$0.text.isEmpty
            })
        else { return asked }
        return asked + "\nAssistant: \(ChatChoices.split(answer.text).text.prefix(excerptLength))"
    }

    /// A model asked for a title still wraps it in quotes, a heading or a full stop now and then.
    static func sanitize(_ raw: String) -> String? {
        let firstLine = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var title = firstLine
        if let label = title.firstMatch(of: #/^(?i:title)\s*:\s*/#) {
            title.removeSubrange(label.range)
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "#*_\"'“”‘’` "))
        while let last = title.last, ".:;,!".contains(last) { title.removeLast() }
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !title.isEmpty else { return nil }
        return title.count > maxLength ? String(title.prefix(maxLength - 1)) + "…" : title
    }
}
