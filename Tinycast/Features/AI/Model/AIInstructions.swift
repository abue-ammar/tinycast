import Foundation

/// A turn carries `AIPreamble` then the user's text; off, or on device, it carries neither.
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

    /// A preset's text always rides, even on device; the preamble still follows its own switch.
    static func compose(
        presetInstructions: String, preambleEnabled: Bool, offersChoices: Bool,
        model: AIModelSelection?
    ) -> String? {
        let trimmed = presetInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preambleEnabled, model?.isOnDevice != true else {
            return trimmed.isEmpty ? nil : trimmed
        }
        return compose(
            userPrompt: trimmed, isEnabled: true, offersChoices: offersChoices, model: model)
    }
}
