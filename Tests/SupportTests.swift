import Foundation

@main
@MainActor
struct SupportTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        waitsOutTheWholeInterval()
        comesDueOnlyOnceTheIntervalHasPassed()
        survivesAClockThatMovedBackwards()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static let interval = SupportReminderSchedule.interval
    private static let anchor = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func waitsOutTheWholeInterval() {
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor) == interval,
            "a fresh anchor waits a full interval")
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor + interval / 2)
                == interval / 2,
            "half an interval in, half an interval is left")
    }

    static func comesDueOnlyOnceTheIntervalHasPassed() {
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor + interval - 1) == 1,
            "one second short is not yet due")
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor + interval) == 0,
            "due exactly at the interval")
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor + interval * 10) == 0,
            "long overdue is due now, never a negative wait")
    }

    /// A clock moved backwards must not park the ask past one interval, however far back it went.
    static func survivesAClockThatMovedBackwards() {
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor - 1) == interval,
            "a second before the anchor still waits exactly one interval")
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor - interval * 10) == interval,
            "a decade before the anchor waits one interval, not eleven")
    }
}
