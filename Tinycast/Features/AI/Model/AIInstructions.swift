import Foundation

/// What every chat request carries ahead of the transcript: `AIPreamble`, then whatever the user
/// has written in Settings. The preamble is not shown in the pane — it is the app talking about
/// itself, not a setting — and `AIPreamble.swift` is the single copy of it.
///
/// Turned off, a turn carries no instructions at all. The preamble is billed on every turn and
/// shapes every answer, so opting out has to reach it too, not only the half the user typed.
enum AIInstructions {
    /// The user's own text goes last, so it can qualify the preamble rather than fight it.
    static func compose(userPrompt: String?, isEnabled: Bool) -> String? {
        guard isEnabled else { return nil }
        let trimmed = userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? AIPreamble.text : AIPreamble.text + "\n\n" + trimmed
    }
}
