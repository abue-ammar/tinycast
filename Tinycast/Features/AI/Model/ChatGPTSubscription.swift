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

        var usesAPIKey: Bool { plan == "apiKey" || plan == "api_key" }

        var planTitle: String {
            switch plan {
            case "free": return "Free"
            case "go": return "Go"
            case "plus": return "Plus"
            case "pro": return "Pro 20x"
            case "prolite": return "Pro 5x"
            case "team": return "Team"
            case "self_serve_business_prolite", "self_serve_business_usage_based", "business":
                return "Business"
            case "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based", "enterprise":
                return "Enterprise"
            case "edu", "edu_plus", "edu_pro": return "Edu"
            case "apiKey", "api_key": return String(localized: "API key")
            default: return String(localized: "Account")
            }
        }
    }

    /// What `account/read` confirmed a turn can run on.
    enum Access: Equatable, Sendable {
        case account(Account)
        /// A custom provider brings its own key, so Codex reports no account and needs none.
        case provider
    }

    struct Effort: Equatable, Identifiable, Sendable {
        let id: String
        let detail: String?

        var title: String {
            switch id {
            case "default": return String(localized: "Default")
            case "none": return String(localized: "None")
            case "minimal": return String(localized: "Minimal")
            case "low": return String(localized: "reasoning-effort-low", defaultValue: "Low")
            case "medium": return String(localized: "reasoning-effort-medium", defaultValue: "Medium")
            case "high": return String(localized: "reasoning-effort-high", defaultValue: "High")
            case "xhigh": return String(localized: "Extra high")
            case "max": return String(localized: "Max")
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
