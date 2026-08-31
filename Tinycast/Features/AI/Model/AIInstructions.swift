import Foundation

/// Every turn carries `AIPreamble` then the user's text; turned off, it carries neither.
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
            let year = Calendar.current.component(.year, from: now)
            preamble += "\n\nCurrent date: \(dateStr). The current year is \(year). Always refer to this current date/year when asked about today, latest news, current events, or recent time periods."
        }
        return trimmed.isEmpty ? preamble : preamble + "\n\n" + trimmed
    }
}
