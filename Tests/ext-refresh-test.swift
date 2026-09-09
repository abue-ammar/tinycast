import Foundation

@main
@MainActor
struct ExtensionRefreshTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    static func command(json: [String: Any]) -> ExtensionCommand? {
        ExtensionCommand(json: json)
    }

    static func baseJSON(interval: Any?) -> [String: Any] {
        var json: [String: Any] = [
            "name": "status", "title": "Status", "mode": "no-view"
        ]
        if let interval { json["interval"] = interval }
        return json
    }

    // MARK: - Interval parsing

    static func parseAcceptsAllUnits() {
        expect(ExtensionRefreshPolicy.parse("90s") == 90, "seconds parse")
        expect(ExtensionRefreshPolicy.parse("1m") == 60, "minutes parse")
        expect(ExtensionRefreshPolicy.parse("12h") == 12 * 3600, "hours parse")
        expect(ExtensionRefreshPolicy.parse("1d") == 86400, "days parse")
    }

    static func parseClampsToTheFloor() {
        expect(ExtensionRefreshPolicy.parse("10s") == 60, "a 10s manifest clamps to a minute")
        expect(ExtensionRefreshPolicy.parse("30s") == 60, "a 30s manifest clamps to a minute")
    }

    static func parseRejectsGarbage() {
        expect(ExtensionRefreshPolicy.parse(nil) == nil, "a missing interval is no schedule")
        expect(ExtensionRefreshPolicy.parse("soon") == nil, "words are rejected")
        expect(ExtensionRefreshPolicy.parse("1w") == nil, "weeks are rejected")
        expect(ExtensionRefreshPolicy.parse("m") == nil, "a bare unit is rejected")
        expect(ExtensionRefreshPolicy.parse("0m") == nil, "zero is rejected")
        expect(ExtensionRefreshPolicy.parse("-5m") == nil, "negatives are rejected")
    }

    static func manifestCarriesTheInterval() {
        let parsed = command(json: baseJSON(interval: "1m"))
        expect(parsed?.interval == 60, "the manifest interval parses")
        expect(parsed?.intervalRaw == "1m", "the raw text survives for Settings")
        expect(command(json: baseJSON(interval: nil))?.interval == nil, "no key means no schedule")
        expect(
            command(json: baseJSON(interval: "weekly"))?.interval == nil,
            "garbage means no schedule, not a crash")
    }

    // MARK: - Schedulability

    static func onlyNoViewSchedules() {
        expect(
            ExtensionRefreshPolicy.isSchedulable(mode: .noView, interval: 60),
            "no-view with an interval schedules")
        expect(
            !ExtensionRefreshPolicy.isSchedulable(mode: .noView, interval: nil),
            "no-view without an interval never wakes the loop")
        expect(
            !ExtensionRefreshPolicy.isSchedulable(mode: .view, interval: 60),
            "a view interval never schedules")
        expect(
            !ExtensionRefreshPolicy.isSchedulable(mode: .menuBar, interval: 60),
            "a menu-bar interval parses but never schedules")
    }

    // MARK: - Due dates and backoff

    static func firstRunIsImmediatelyDue() {
        let now = Date()
        let due = ExtensionRefreshPolicy.nextDue(
            lastRun: nil, now: now, interval: 60, consecutiveFailures: 0, entryID: "extension:a/b")
        expect(due == now, "a command that never ran is due now")
    }

    static func dueFollowsTheInterval() {
        let now = Date()
        let lastRun = now.addingTimeInterval(-120)
        let due = ExtensionRefreshPolicy.nextDue(
            lastRun: lastRun, now: now, interval: 60, consecutiveFailures: 0,
            entryID: "extension:a/b")
        expect(
            due.timeIntervalSince(lastRun) >= 60 && due.timeIntervalSince(lastRun) <= 66,
            "due is one interval past the run, plus phase")
    }

    static func failuresBackOffExponentially() {
        expect(
            ExtensionRefreshPolicy.effectiveInterval(60, consecutiveFailures: 0) == 60,
            "no failures means the bare interval")
        expect(
            ExtensionRefreshPolicy.effectiveInterval(60, consecutiveFailures: 3) == 480,
            "three failures octuple the wait")
        expect(
            ExtensionRefreshPolicy.effectiveInterval(60, consecutiveFailures: 99)
                == ExtensionRefreshPolicy.maximumInterval,
            "backoff caps at a day")
    }

    static func jitterIsStableAndBounded() {
        let first = ExtensionRefreshPolicy.jitter(entryID: "extension:coffee/status", interval: 60)
        let second = ExtensionRefreshPolicy.jitter(entryID: "extension:coffee/status", interval: 60)
        expect(first == second, "the phase is stable across launches")
        expect(first >= 0 && first < 6, "a minute interval phases within six seconds")
        let hourly = ExtensionRefreshPolicy.jitter(entryID: "extension:coffee/status", interval: 3600)
        expect(hourly >= 0 && hourly <= 300, "the phase caps at five minutes")
    }

    static func timeoutStaysInsideTheInterval() {
        let minute = ExtensionRefreshPolicy.timeout(interval: 60)
        expect(minute <= 60, "a hung minute command dies before its successor is due")
        expect(minute >= 15, "even a tight command gets fifteen seconds")
        expect(ExtensionRefreshPolicy.timeout(interval: 3600) == 120, "long intervals cap the wait")
    }

    // MARK: - Subtitles and launch types

    static func overrideWinsOverManifest() {
        expect(
            ExtensionRefreshPolicy.displaySubtitle(
                manifest: "Coffee", override: "✔ Caffeinated", ownerTitle: "Coffee")
                == "✔ Caffeinated",
            "the live subtitle wins")
        expect(
            ExtensionRefreshPolicy.displaySubtitle(
                manifest: "Coffee", override: nil, ownerTitle: "Something Else") == "Coffee",
            "clearing falls back to the manifest")
    }

    static func ownerRestatementIsDropped() {
        expect(
            ExtensionRefreshPolicy.displaySubtitle(
                manifest: "Coffee", override: nil, ownerTitle: "Coffee") == nil,
            "a subtitle restating the extension is dropped")
        expect(
            ExtensionRefreshPolicy.displaySubtitle(
                manifest: "coffee", override: nil, ownerTitle: "Coffee") == nil,
            "the comparison ignores case")
        expect(
            ExtensionRefreshPolicy.displaySubtitle(manifest: nil, override: nil, ownerTitle: "Coffee")
                == nil,
            "no subtitle stays no subtitle")
    }

    static func indicatorNamesTheState() {
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: false, backgroundEnabled: false, lastError: nil) == nil,
            "an unschedulable command shows nothing")
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: true, backgroundEnabled: true, lastError: nil) == .active,
            "an enabled schedule shows the active dot")
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: true, backgroundEnabled: false, lastError: nil) == .idle,
            "a switched-off schedule shows the dimmed dot")
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: true, backgroundEnabled: true, lastError: "Timed out.")
                == .failed("Timed out."),
            "an error replaces the dot until the next success")
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: true, backgroundEnabled: true,
                lastError: "TypeError: x\n    at foo\n    at bar") == .failed("TypeError: x"),
            "a JS stack is cut to its headline before it reaches the row")
    }

    static func launchTypesMatchTheJSContract() {
        expect(
            ExtensionLaunchType.background.rawValue == "background",
            "background matches @raycast/api LaunchType.Background")
        expect(
            ExtensionLaunchType.userInitiated.rawValue == "userInitiated",
            "userInitiated matches LaunchType.UserInitiated")
    }

    static func main() {
        parseAcceptsAllUnits()
        parseClampsToTheFloor()
        parseRejectsGarbage()
        manifestCarriesTheInterval()
        onlyNoViewSchedules()
        firstRunIsImmediatelyDue()
        dueFollowsTheInterval()
        failuresBackOffExponentially()
        jitterIsStableAndBounded()
        timeoutStaysInsideTheInterval()
        overrideWinsOverManifest()
        ownerRestatementIsDropped()
        indicatorNamesTheState()
        launchTypesMatchTheJSContract()

        print(failures == 0 ? "Extension refresh tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
