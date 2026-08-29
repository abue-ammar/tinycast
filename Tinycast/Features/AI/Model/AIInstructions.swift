import Foundation

/// Every turn carries `AIPreamble` then the user's text; turned off, it carries neither.
enum AIInstructions {
    /// The user's own text goes last, so it can qualify the preamble rather than fight it.
    static func compose(userPrompt: String?, isEnabled: Bool) -> String? {
        guard isEnabled else { return nil }
        let trimmed = userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? AIPreamble.text : AIPreamble.text + "\n\n" + trimmed
    }
}
