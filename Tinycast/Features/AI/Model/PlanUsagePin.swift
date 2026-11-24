import Foundation

enum PlanUsagePin: Equatable, Sendable {
    case automatic
    case window(PlanUsage.Provider, id: String)

    struct Target: Equatable, Sendable {
        let provider: PlanUsage.Provider
        let window: PlanUsage.Window
    }

    init(rawValue: String?) {
        guard let rawValue, let separator = rawValue.firstIndex(of: ":"),
            let provider = PlanUsage.Provider(rawValue: String(rawValue[..<separator]))
        else {
            self = .automatic
            return
        }
        self = .window(provider, id: String(rawValue[rawValue.index(after: separator)...]))
    }

    var rawValue: String? {
        guard case .window(let provider, let id) = self else { return nil }
        return "\(provider.rawValue):\(id)"
    }

    func effective(in usage: [PlanUsage.Provider: PlanUsage]) -> PlanUsagePin {
        guard case .window(let provider, let id) = self, usage[provider]?.window(id: id) == nil
        else { return self }
        return .automatic
    }

    func target(in usage: [PlanUsage.Provider: PlanUsage]) -> Target? {
        if case .window(let provider, let id) = self, let window = usage[provider]?.window(id: id) {
            return Target(provider: provider, window: window)
        }
        let targets = PlanUsage.Provider.allCases.flatMap { provider in
            (usage[provider]?.windows ?? []).map { Target(provider: provider, window: $0) }
        }
        return targets.max { $0.window.usedPercent < $1.window.usedPercent }
    }
}
