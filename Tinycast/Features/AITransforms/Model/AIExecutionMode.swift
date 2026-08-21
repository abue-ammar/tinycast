import Foundation

/// Activation modes for executing AI transforms.
enum AIExecutionMode: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case interactive
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interactive: return "Interactive Window"
        case .direct: return "Direct In-Place"
        }
    }

    var subtitle: String {
        switch self {
        case .interactive: return "Preview, refine with follow-up prompts, and insert on ↵."
        case .direct: return "Transform in background and paste directly with toast notifications."
        }
    }
}
