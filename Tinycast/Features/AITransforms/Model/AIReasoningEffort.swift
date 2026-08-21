import Foundation

/// Normalized reasoning effort levels supported across modern reasoning-capable LLMs (o3-mini, Gemini 2.5/3.7, DeepSeek-R1, etc.).
enum AIReasoningEffort: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Off (Fast)"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// The wire string passed to OpenAI-compatible endpoints (`reasoning_effort`).
    var wireValue: String? {
        switch self {
        case .none: return nil
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }
}
