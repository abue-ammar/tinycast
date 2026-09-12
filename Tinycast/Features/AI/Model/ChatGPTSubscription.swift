import Foundation

enum ChatGPTSubscription {
    enum Phase: Equatable, Sendable {
        case idle
        case starting
        case signedOut
        case connected
        case unavailable(String)
        case failed(String)

        var isUnavailable: Bool {
            if case .unavailable = self { return true }
            return false
        }
    }

    struct Account: Equatable, Sendable {
        let email: String?
        let plan: String

        var planTitle: String {
            switch plan {
            case "free": return "Free"
            case "go": return "Go"
            case "plus": return "Plus"
            case "pro": return "Pro"
            case "prolite": return "Pro Lite"
            case "team": return "Team"
            case "self_serve_business_usage_based", "business": return "Business"
            case "enterprise_cbp_usage_based", "enterprise": return "Enterprise"
            case "edu": return "Edu"
            case "apiKey", "api_key": return "API key"
            default: return "Account"
            }
        }
    }

    struct Effort: Equatable, Identifiable, Sendable {
        let id: String
        let detail: String?

        var title: String {
            switch id {
            case "xhigh": return "Extra high"
            case "minimal": return "Minimal"
            default: return id.prefix(1).uppercased() + id.dropFirst()
            }
        }
    }

    struct Model: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let efforts: [Effort]
        let defaultEffort: String?
        let isDefault: Bool

        func resolvedEffort(_ preferred: String?) -> String? {
            guard !efforts.isEmpty else { return nil }
            if let preferred, efforts.contains(where: { $0.id == preferred }) { return preferred }
            if let defaultEffort, efforts.contains(where: { $0.id == defaultEffort }) {
                return defaultEffort
            }
            return efforts.first?.id
        }
    }

    struct UsageWindow: Equatable, Sendable {
        let usedPercent: Int
        let durationMinutes: Int?
        let resetsAt: Date?

        var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
    }

    struct RateLimits: Equatable, Sendable {
        let primary: UsageWindow?
        let secondary: UsageWindow?
    }
}
