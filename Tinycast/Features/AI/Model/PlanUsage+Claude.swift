import Foundation

extension PlanUsage {
    static let claudeRequestID = "tinycast-usage"

    static let claudeRequest =
        #"{"type":"control_request","request_id":"tinycast-usage","request":{"subtype":"get_usage"}}"#
        + "\n"

    /// A whole line: the request ID arrives before the windows, so a chunk may split them.
    static func claudeAnswered(_ output: String) -> Bool {
        output.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
            .contains { $0.contains(claudeRequestID) }
    }

    static func claude(_ output: String) -> Reading {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = JSONValue(data: Data(line.utf8))?.objectValue,
                object["type"]?.stringValue == "control_response",
                let response = object["response"]?.objectValue,
                response["request_id"]?.stringValue == claudeRequestID
            else { continue }
            return response["response"]?.objectValue.map(claudeReading) ?? .failed
        }
        return .failed
    }

    private static func claudeReading(_ payload: [String: JSONValue]) -> Reading {
        guard payload["rate_limits_available"]?.boolValue == true else { return .unavailable }
        guard let limits = payload["rate_limits"]?.objectValue else { return .failed }
        var windows = [
            claudeWindow(
                limits["five_hour"], id: "five_hour", title: windowTitle(minutes: 300),
                duration: fiveHours),
            claudeWindow(
                limits["seven_day"], id: "seven_day", title: String(localized: "Weekly"),
                duration: week)
        ].compactMap(\.self)
        var scopedModels = Set<String>()
        for entry in limits["model_scoped"]?.arrayValue ?? [] {
            let name =
                entry.objectValue?["display_name"]?.stringValue?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty,
                let window = claudeWindow(
                    entry, id: "model:\(name.lowercased())",
                    title: String(localized: "\(name) weekly"), duration: week)
            else { continue }
            windows.append(window)
            scopedModels.insert(name.lowercased())
        }
        for (key, name) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")]
        where !scopedModels.contains(name.lowercased()) {
            if let window = claudeWindow(
                limits[key], id: key, title: String(localized: "\(name) weekly"), duration: week)
            {
                windows.append(window)
            }
        }
        guard !windows.isEmpty else { return .failed }
        let plan = InstalledAIAccount(email: nil, plan: payload["subscription_type"]?.stringValue)
        return .usage(PlanUsage(plan: plan.planTitle, windows: windows, resetCredits: 0))
    }

    private static func claudeWindow(
        _ value: JSONValue?, id: String, title: String, duration: TimeInterval
    ) -> Window? {
        guard let object = value?.objectValue, let used = object["utilization"]?.doubleValue else {
            return nil
        }
        let resetsAt = object["resets_at"]?.stringValue.flatMap {
            try? Date($0, strategy: Date.ISO8601FormatStyle())
        }
        return Window(
            id: id, title: title, usedPercent: used, duration: duration, resetsAt: resetsAt)
    }
}
