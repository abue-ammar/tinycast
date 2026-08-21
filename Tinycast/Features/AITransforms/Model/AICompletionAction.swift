import Foundation

/// Action taken when an AI transform completes execution.
enum AICompletionAction: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case overwriteSelection = "overwrite"
    case copyToClipboard = "copy"
    case both = "both"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwriteSelection: return "Overwrite Selection"
        case .copyToClipboard: return "Copy to Clipboard"
        case .both: return "Both (Replace & Copy)"
        }
    }

    var subtitle: String {
        switch self {
        case .overwriteSelection: return "Replaces the highlighted text in place in the active application."
        case .copyToClipboard:
            return "Copies the transformed output to your clipboard without modifying selection."
        case .both: return "Replaces the selection in place and preserves a copy on your clipboard."
        }
    }
}
