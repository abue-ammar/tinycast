import Foundation

struct PlanUsage: Equatable, Sendable {
    enum Provider: String, CaseIterable, Sendable {
        case claude
        case chatGPT

        var title: String {
            switch self {
            case .claude: return "Claude"
            case .chatGPT: return "ChatGPT"
            }
        }

        var brand: AIBrand {
            switch self {
            case .claude: return .claude
            case .chatGPT: return .openAI
            }
        }
    }

    enum Reading: Equatable, Sendable {
        case usage(PlanUsage)
        case unavailable
        case failed
    }

    struct ResetCredit: Equatable, Sendable {
        let id: String
        let availableCount: Int
    }

    enum Level: Comparable, Sendable {
        case normal
        case high
        case critical

        static let highPercent = 80.0
        static let criticalPercent = 95.0

        init(usedPercent: Double) {
            if usedPercent >= Self.criticalPercent {
                self = .critical
            } else if usedPercent >= Self.highPercent {
                self = .high
            } else {
                self = .normal
            }
        }
    }

    struct Window: Equatable, Identifiable, Sendable {
        /// Early in a window one burst would project an exhaustion that never comes.
        static let minimumPaceElapsed = 0.1

        let id: String
        let title: String
        let usedPercent: Double
        let duration: TimeInterval?
        let resetsAt: Date?

        init(id: String, title: String, usedPercent: Double, duration: TimeInterval?, resetsAt: Date?) {
            self.id = id
            self.title = title
            self.usedPercent = min(max(usedPercent, 0), 100)
            self.duration = duration
            self.resetsAt = resetsAt
        }

        var level: Level { Level(usedPercent: usedPercent) }
        var fraction: Double { usedPercent / 100 }

        func elapsedFraction(at now: Date) -> Double? {
            guard let duration, duration > 0, let resetsAt else { return nil }
            let elapsed = duration - resetsAt.timeIntervalSince(now)
            return min(max(elapsed / duration, 0), 1)
        }

        func exhaustion(at now: Date) -> Date? {
            guard let duration, let resetsAt, let elapsed = elapsedFraction(at: now),
                elapsed >= Self.minimumPaceElapsed, usedPercent > 0, usedPercent < 100
            else { return nil }
            let rate = usedPercent / (elapsed * duration)
            let exhaustion = now.addingTimeInterval((100 - usedPercent) / rate)
            return exhaustion < resetsAt ? exhaustion : nil
        }
    }

    static let fiveHours: TimeInterval = 5 * 3_600
    static let week: TimeInterval = 7 * 86_400

    let plan: String?
    let windows: [Window]
    let resetCredit: ResetCredit?

    func window(id: String) -> Window? {
        windows.first { $0.id == id }
    }

    static func windowTitle(minutes: Int) -> String {
        let day = 1_440
        if minutes == 7 * day { return String(localized: "Weekly") }
        if minutes.isMultiple(of: day) { return String(localized: "\(minutes / day)-day") }
        if minutes.isMultiple(of: 60) { return String(localized: "\(minutes / 60)-hour") }
        return String(localized: "\(minutes)-minute")
    }
}
