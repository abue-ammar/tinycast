import Foundation

/// A turn carries `AIPreamble` then the user's or a preset's text; on device it carries neither.
enum AIInstructions {
    /// The user's own text goes last, so it can qualify the preamble rather than fight it.
    static func compose(
        userPrompt: String?, isEnabled: Bool, offersChoices: Bool, model: AIModelSelection?
    ) -> String? {
        guard isEnabled, model?.isOnDevice != true else { return nil }
        let trimmed = userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [AIPreamble.text, offersChoices ? AIPreamble.choices : "", trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// A preset's text rides even with the system prompt off; the preamble keeps its own switch.
    static func compose(
        presetInstructions: String, preambleEnabled: Bool, offersChoices: Bool,
        model: AIModelSelection?
    ) -> String? {
        guard model?.isOnDevice != true else { return nil }
        let trimmed = presetInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preambleEnabled else { return trimmed.isEmpty ? nil : trimmed }
        return compose(
            userPrompt: trimmed, isEnabled: true, offersChoices: offersChoices, model: model)
    }
}
