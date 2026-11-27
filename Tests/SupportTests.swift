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
        findsGivingWeekEveryYear()
        asksOnceInGivingWeek()

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

    static func findsGivingWeekEveryYear() {
        let iso = ISO8601DateFormatter()
        for (year, start) in [
            (2026, "2026-11-26T05:00:00Z"), (2027, "2027-11-25T05:00:00Z"),
            (2028, "2028-11-23T05:00:00Z"), (2030, "2030-11-28T05:00:00Z")
        ] {
            expect(
                SupportReminderSchedule.givingWeek(in: year).start == iso.date(from: start),
                "giving week \(year) opens on Thanksgiving, the fourth Thursday of November")
        }
        expect(
            SupportReminderSchedule.givingWeek(in: 2026).end == iso.date(from: "2026-12-02T08:00:00Z"),
            "giving week closes when Giving Tuesday ends on the US west coast")
    }

    static func asksOnceInGivingWeek() {
        let week = SupportReminderSchedule.givingWeek(in: 2026)
        let inside = week.start + 3600
        expect(
            SupportReminderSchedule.isGivingWeekAskDue(since: week.start - interval * 2, now: inside),
            "an anchor older than a month is due inside the week")
        expect(
            !SupportReminderSchedule.isGivingWeekAskDue(since: week.start - interval / 3, now: inside),
            "a showing in the last month keeps the week quiet")
        expect(
            !SupportReminderSchedule.isGivingWeekAskDue(since: week.start + 60, now: inside),
            "a showing inside the week settles it, so it never asks twice")
        expect(
            !SupportReminderSchedule.isGivingWeekAskDue(
                since: week.start - interval * 2, now: week.start - 1),
            "nothing is due before the week opens")
        expect(
            !SupportReminderSchedule.isGivingWeekAskDue(since: week.start - interval * 2, now: week.end + 1),
            "nothing is due once the week has closed")
    }
}
