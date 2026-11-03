import Foundation

/// How long an app may sit in the background before Auto Quit closes it.
enum AutoQuitMinutes: Int, CaseIterable, Codable, Identifiable, Sendable {
    case one = 1
    case three = 3
    case five = 5
    case ten = 10
    case fifteen = 15

    static let fallback = AutoQuitMinutes.three

    var id: Int { rawValue }

    var duration: TimeInterval { TimeInterval(rawValue * 60) }

    var title: String { String(localized: "\(rawValue) minutes") }
}

/// One app Auto Quit may close. A nil duration follows the default, so editing the default retimes it.
struct AutoQuitRule: Codable, Equatable, Identifiable, Sendable {
    var bundleID: String
    var minutes: AutoQuitMinutes?
    var id: String { bundleID }
}

/// What the clock can see. The monitor fills it; nothing here reads the clock or the workspace.
struct AutoQuitSnapshot: Equatable, Sendable {
    var rules: [AutoQuitRule]
    var defaultMinutes: AutoQuitMinutes
    var armedAt: [String: Date]
    var now: Date
    var recording: Bool
    var playing: Set<String>
    var frontmost: String?
    var ownBundleID: String
}

struct AutoQuitDecision: Equatable, Sendable {
    /// Bundle IDs to quit, in rule order.
    var quit: [String]
    /// The soonest deadline still ahead. Nil while nothing is counting.
    var nextWake: Date?
}

/// Who quits, and when. Finder and this app never do, even if a rule names them.
enum AutoQuitSchedule {
    static let finderBundleID = "com.apple.finder"
    static let mediaPlayers: Set<String> = ["com.apple.Music", "com.spotify.client"]

    static func isExcluded(_ bundleID: String, ownBundleID: String) -> Bool {
        bundleID == finderBundleID || bundleID == ownBundleID
    }

    static func minutes(for rule: AutoQuitRule, defaultMinutes: AutoQuitMinutes) -> AutoQuitMinutes {
        rule.minutes ?? defaultMinutes
    }

    /// First rule wins. An empty id, a duplicate, Finder or this app is dropped.
    static func normalized(_ rules: [AutoQuitRule], ownBundleID: String) -> [AutoQuitRule] {
        var seen: Set<String> = []
        return rules.filter { rule in
            let id = rule.bundleID
            guard !id.isEmpty, !isExcluded(id, ownBundleID: ownBundleID), seen.insert(id).inserted
            else { return false }
            return true
        }
    }

    /// A regular background app starts now; an accessory app keeps only a deadline it already has.
    static func reconcile(
        armedAt: [String: Date], rules: [AutoQuitRule], running: Set<String>,
        runningRegular: Set<String>, frontmost: String?, ownBundleID: String, now: Date
    ) -> [String: Date] {
        var next: [String: Date] = [:]
        for rule in normalized(rules, ownBundleID: ownBundleID) {
            let id = rule.bundleID
            guard id != frontmost else { continue }
            if let existing = armedAt[id], running.contains(id) {
                next[id] = existing
            } else if runningRegular.contains(id) {
                next[id] = now
            }
        }
        return next
    }

    static func decide(_ snapshot: AutoQuitSnapshot) -> AutoQuitDecision {
        guard !snapshot.recording else { return AutoQuitDecision(quit: [], nextWake: nil) }
        var quit: [String] = []
        var nextWake: Date?
        var seen: Set<String> = []
        for rule in normalized(snapshot.rules, ownBundleID: snapshot.ownBundleID) {
            let id = rule.bundleID
            guard seen.insert(id).inserted, id != snapshot.frontmost, !snapshot.playing.contains(id),
                let armed = snapshot.armedAt[id]
            else { continue }
            let deadline =
                armed.addingTimeInterval(minutes(for: rule, defaultMinutes: snapshot.defaultMinutes).duration)
            if deadline <= snapshot.now {
                quit.append(id)
            } else if nextWake.map({ deadline < $0 }) ?? true {
                nextWake = deadline
            }
        }
        return AutoQuitDecision(quit: quit, nextWake: nextWake)
    }
}

extension AutoQuitMinutes: SettingsFileRawValue {}

extension AutoQuitRule: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let bundleID = settingsJSON["bundleID"]?.string, !bundleID.isEmpty else { return nil }
        if let minutesJSON = settingsJSON["minutes"], minutesJSON != .null {
            guard let minutes = AutoQuitMinutes(settingsJSON: minutesJSON) else { return nil }
            self.init(bundleID: bundleID, minutes: minutes)
        } else {
            self.init(bundleID: bundleID, minutes: nil)
        }
    }

    var settingsJSON: SettingsFileJSON {
        .object([
            "bundleID": .string(bundleID),
            "minutes": minutes?.settingsJSON ?? .null
        ])
    }
}
