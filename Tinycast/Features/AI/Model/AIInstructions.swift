import Foundation

/// What every chat request carries ahead of the transcript: `AIPreamble`, then whatever the user
/// has written in Settings. The preamble is not shown in the pane — it is the app talking about
/// itself, not a setting — and `AIPreamble.swift` is the single copy of it.
///
/// Turned off, a turn carries no instructions at all. The preamble is billed on every turn and
/// shapes every answer, so opting out has to reach it too, not only the half the user typed.
enum AIInstructions {
    /// The user's own text goes last, so it can qualify the preamble rather than fight it.
    static func compose(userPrompt: String?, isEnabled: Bool, now: Date? = nil) -> String? {
        guard isEnabled else { return nil }
        let trimmed = userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var preamble = AIPreamble.text
        if let now {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            formatter.locale = Locale(identifier: "en_US")
            let dateStr = formatter.string(from: now)
            preamble += "\n\nCurrent date: \(dateStr)."
        }
        return trimmed.isEmpty ? preamble : preamble + "\n\n" + trimmed
    }
}
