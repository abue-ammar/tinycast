import Foundation

extension PlanUsage {
    enum ResetOutcome: String, Sendable {
        case reset
        case alreadyRedeemed
        case nothingToReset
        case noCredit

        var message: String {
            switch self {
            case .reset, .alreadyRedeemed: return String(localized: "ChatGPT limits reset")
            case .nothingToReset: return String(localized: "Nothing to reset yet")
            case .noCredit: return String(localized: "No resets available")
            }
        }
    }

    private static let codexLimitID = "codex"

    init?(codex response: [String: JSONValue]) {
        var limits = (response["rateLimitsByLimitId"]?.objectValue ?? [:]).compactMapValues(\.objectValue)
        if limits.isEmpty, let general = response["rateLimits"]?.objectValue {
            limits[Self.codexLimitID] = general
        }
        let ordered = limits.sorted { lhs, rhs in
            if (lhs.key == Self.codexLimitID) != (rhs.key == Self.codexLimitID) {
                return lhs.key == Self.codexLimitID
            }
            return lhs.key < rhs.key
        }
        let windows = ordered.flatMap { id, limit in
            let name = id == Self.codexLimitID ? nil : limit["limitName"]?.stringValue ?? id
            return ["primary", "secondary"].compactMap { slot in
                Self.codexWindow(limit[slot], id: "\(id)/\(slot)", slot: slot, limitName: name)
            }
        }
        guard !windows.isEmpty else { return nil }
        let planType = (limits[Self.codexLimitID] ?? ordered.first?.value)?["planType"]?.stringValue
        self.init(
            plan: planType.map { ChatGPTSubscription.Account(email: nil, plan: $0).planTitle },
            windows: windows,
            resetCredits: response["rateLimitResetCredits"]?.objectValue?["availableCount"]?.intValue
                ?? 0)
    }

    private static func codexWindow(
        _ value: JSONValue?, id: String, slot: String, limitName: String?
    ) -> Window? {
        guard let object = value?.objectValue, let used = object["usedPercent"]?.doubleValue else {
            return nil
        }
        let minutes = object["windowDurationMins"]?.intValue.flatMap { $0 > 0 ? $0 : nil }
        let title =
            minutes.map(windowTitle(minutes:))
            ?? (slot == "primary"
                ? String(localized: "Primary window") : String(localized: "Secondary window"))
        let resetsAt = object["resetsAt"]?.doubleValue.flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
        }
        return Window(
            id: id, title: limitName.map { "\($0) · \(title)" } ?? title, usedPercent: used,
            duration: minutes.map { TimeInterval($0 * 60) }, resetsAt: resetsAt)
    }
}
