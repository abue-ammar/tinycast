import Foundation

enum PlanUsageAlertPolicy {
    struct Alert: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case reached(PlanUsage.Level)
            case reset
        }

        let kind: Kind
        let message: String
    }

    /// The first read after launch has nothing to compare, so a limit already high stays quiet.
    static func alert(
        for provider: PlanUsage.Provider, from old: PlanUsage?, to new: PlanUsage
    ) -> Alert? {
        guard let old else { return nil }
        var reached: (level: PlanUsage.Level, window: PlanUsage.Window)?
        var reset: PlanUsage.Window?
        for window in new.windows {
            guard let previous = old.window(id: window.id) else { continue }
            if window.level > previous.level, window.level > reached?.level ?? .normal {
                reached = (window.level, window)
            } else if previous.level > .normal, window.usedPercent < previous.usedPercent / 2,
                reset == nil
            {
                reset = window
            }
        }
        if let reached {
            let percent = Int(reached.window.usedPercent.rounded())
            return Alert(
                kind: .reached(reached.level),
                message: String(
                    localized: "\(provider.title) \(reached.window.title) limit at \(percent)%"))
        }
        return reset.map {
            Alert(
                kind: .reset,
                message: String(localized: "\(provider.title) \($0.title) limit reset"))
        }
    }
}
