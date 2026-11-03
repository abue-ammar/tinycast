import Foundation

@main
@MainActor
struct AutoQuitTests {
    static var failures = 0
    static var passes = 0
    static let own = "com.tinycast.app"

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        durations()
        normalizedRules()
        deadlines()
        holds()
        reconcileArms()
        settingsJSON()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func durations() {
        expect(AutoQuitMinutes.fallback == .three, "a new install waits 3 minutes")
        expect(
            AutoQuitMinutes.allCases.map(\.rawValue) == [1, 3, 5, 10, 15],
            "the choices are 1, 3, 5, 10 and 15 minutes")
        expect(
            AutoQuitSchedule.minutes(for: AutoQuitRule(bundleID: "com.slack", minutes: nil), defaultMinutes: .ten)
                == .ten,
            "a nil duration follows the default")
        expect(
            AutoQuitSchedule.minutes(for: AutoQuitRule(bundleID: "com.slack", minutes: .one), defaultMinutes: .ten)
                == .one,
            "an override keeps its own duration")
    }

    static func normalizedRules() {
        let rules = AutoQuitSchedule.normalized(
            [
                AutoQuitRule(bundleID: "com.slack", minutes: nil),
                AutoQuitRule(bundleID: "", minutes: .one),
                AutoQuitRule(bundleID: AutoQuitSchedule.finderBundleID, minutes: .one),
                AutoQuitRule(bundleID: own, minutes: .one),
                AutoQuitRule(bundleID: "com.slack", minutes: .five),
                AutoQuitRule(bundleID: "com.apple.MobileSMS", minutes: .one)
            ], ownBundleID: own)
        expect(
            rules.map(\.bundleID) == ["com.slack", "com.apple.MobileSMS"],
            "blanks, Finder, Tinycast and duplicates drop")
        expect(rules[0].minutes == nil, "the first duplicate is the one that stays")
    }

    static func deadlines() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let slack = AutoQuitRule(bundleID: "com.slack", minutes: nil)
        let messages = AutoQuitRule(bundleID: "com.apple.MobileSMS", minutes: .one)
        let armed = ["com.slack": start, "com.apple.MobileSMS": start]

        let waiting = decide(rules: [slack], armedAt: ["com.slack": start], now: start.addingTimeInterval(179))
        expect(waiting.quit.isEmpty, "one second early is not a quit")
        expect(
            waiting.nextWake == start.addingTimeInterval(180),
            "the wake is the 3 minute mark")

        let due = decide(rules: [slack], armedAt: ["com.slack": start], now: start.addingTimeInterval(180))
        expect(due.quit == ["com.slack"], "the deadline itself quits")
        expect(due.nextWake == nil, "a quit that is due has no later wake")

        let sooner = decide(
            rules: [slack], defaultMinutes: .one, armedAt: ["com.slack": start],
            now: start.addingTimeInterval(60))
        expect(sooner.quit == ["com.slack"], "changing the default retimes an app that follows it")

        let pinned = decide(
            rules: [AutoQuitRule(bundleID: "com.slack", minutes: .five)], defaultMinutes: .one,
            armedAt: ["com.slack": start], now: start.addingTimeInterval(60))
        expect(pinned.quit.isEmpty, "an override ignores a new default")
        expect(
            pinned.nextWake == start.addingTimeInterval(300),
            "the override still wakes at its own mark")

        let both = decide(
            rules: [slack, messages], armedAt: armed, now: start.addingTimeInterval(180))
        expect(
            both.quit == ["com.slack", "com.apple.MobileSMS"],
            "due apps quit in rule order")

        let idle = decide(rules: [slack], now: start)
        expect(idle.quit.isEmpty && idle.nextWake == nil, "an app that was never armed does not quit")

        let duplicate = decide(
            rules: [slack, AutoQuitRule(bundleID: "com.slack", minutes: .one)],
            armedAt: ["com.slack": start], now: start.addingTimeInterval(61))
        expect(duplicate.quit.isEmpty, "a repeated rule does not replace the first duration")
    }

    static func holds() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let now = start.addingTimeInterval(600)
        let rules = [
            AutoQuitRule(bundleID: "com.slack", minutes: nil),
            AutoQuitRule(bundleID: "com.apple.Music", minutes: nil)
        ]
        let armed = ["com.slack": start, "com.apple.Music": start, "com.apple.finder": start, own: start]

        let recording = decide(rules: rules, armedAt: armed, now: now, recording: true)
        expect(recording.quit.isEmpty && recording.nextWake == nil, "a recording pauses every clock")

        let playing = decide(rules: rules, armedAt: armed, now: now, playing: ["com.apple.Music"])
        expect(playing.quit == ["com.slack"], "playback holds only the player")
        expect(playing.nextWake == nil, "a player that is held is not given a wake")

        let front = decide(rules: rules, armedAt: armed, now: now, frontmost: "com.slack")
        expect(front.quit == ["com.apple.Music"], "the frontmost app is not quit")

        let excluded = decide(
            rules: rules + [
                AutoQuitRule(bundleID: AutoQuitSchedule.finderBundleID, minutes: .one),
                AutoQuitRule(bundleID: own, minutes: .one)
            ], armedAt: armed, now: now)
        expect(
            excluded.quit == ["com.slack", "com.apple.Music"],
            "Finder and Tinycast stay even when a rule and a deadline both name them")
    }

    static func reconcileArms() {
        let now = Date(timeIntervalSinceReferenceDate: 20_000)
        let earlier = now.addingTimeInterval(-40)
        let slack = AutoQuitRule(bundleID: "com.slack", minutes: nil)
        let menu = AutoQuitRule(bundleID: "com.example.menu", minutes: .five)
        let rules = [slack, menu, AutoQuitRule(bundleID: AutoQuitSchedule.finderBundleID, minutes: .one)]

        let fresh = AutoQuitSchedule.reconcile(
            armedAt: [:], rules: rules, running: ["com.slack", "com.example.menu", "com.apple.finder"],
            runningRegular: ["com.slack", "com.apple.finder"], frontmost: nil, ownBundleID: own, now: now)
        expect(fresh == ["com.slack": now], "a regular background app starts now, and a menu-bar app does not")

        let kept = AutoQuitSchedule.reconcile(
            armedAt: ["com.slack": earlier, "com.example.menu": earlier], rules: rules,
            running: ["com.slack", "com.example.menu"], runningRegular: ["com.slack"], frontmost: nil,
            ownBundleID: own, now: now)
        expect(
            kept == ["com.slack": earlier, "com.example.menu": earlier],
            "an existing deadline survives, including one a deactivate armed")

        let focused = AutoQuitSchedule.reconcile(
            armedAt: ["com.slack": earlier], rules: [slack], running: ["com.slack"],
            runningRegular: ["com.slack"], frontmost: "com.slack", ownBundleID: own, now: now)
        expect(focused.isEmpty, "the frontmost app is not armed")

        let gone = AutoQuitSchedule.reconcile(
            armedAt: ["com.slack": earlier], rules: [slack], running: [], runningRegular: [],
            frontmost: nil, ownBundleID: own, now: now)
        expect(gone.isEmpty, "an app that has quit is dropped")
    }

    static func settingsJSON() {
        let following = AutoQuitRule(bundleID: "com.slack", minutes: nil)
        expect(AutoQuitRule(settingsJSON: following.settingsJSON) == following, "a default rule round-trips")
        let custom = AutoQuitRule(bundleID: "com.apple.MobileSMS", minutes: .one)
        expect(AutoQuitRule(settingsJSON: custom.settingsJSON) == custom, "an override round-trips")
        expect(
            AutoQuitRule(settingsJSON: .object(["bundleID": "com.slack"])) == following,
            "a missing duration follows the default")
        expect(
            AutoQuitRule(settingsJSON: .object(["bundleID": "", "minutes": .null])) == nil,
            "a blank bundle id is rejected")
        expect(
            AutoQuitRule(settingsJSON: .object(["bundleID": "com.slack", "minutes": 2])) == nil,
            "a duration outside the list is rejected")
        let mixed = SettingsFileJSON.array([
            following.settingsJSON,
            .object(["bundleID": "com.slack", "minutes": 4])
        ])
        expect([AutoQuitRule](settingsJSON: mixed) == nil, "one bad rule rejects the list")
        let list = SettingsFileJSON.array([following.settingsJSON, custom.settingsJSON])
        expect(
            [AutoQuitRule](settingsJSON: list) == [following, custom],
            "a list of rules round-trips")
    }

    static func decide(
        rules: [AutoQuitRule], defaultMinutes: AutoQuitMinutes = .three,
        armedAt: [String: Date] = [:], now: Date, recording: Bool = false,
        playing: Set<String> = [], frontmost: String? = nil
    ) -> AutoQuitDecision {
        AutoQuitSchedule.decide(
            AutoQuitSnapshot(
                rules: rules, defaultMinutes: defaultMinutes, armedAt: armedAt, now: now,
                recording: recording, playing: playing, frontmost: frontmost, ownBundleID: own))
    }
}
