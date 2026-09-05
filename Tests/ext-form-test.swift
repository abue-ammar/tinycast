import Foundation
import SwiftUI

/// The form's two pure rules: where a picker's list opens, and what a typed date means.
@main
@MainActor
struct ExtensionFormTests {
    static var failures = 0
    static var passes = 0

    /// Fixed, so a suite run in December agrees with one run in June.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Friday, 4 September 2026, 09:30 UTC.
    static let now = ExtensionFormTests.calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 4, hour: 9, minute: 30))!

    static func main() {
        popoverGeometry()
        popoverPlacement()
        datePresets()
        dateParsing()
        dateSuggestions()
        ExtensionListKeyTests.run(check: check)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Geometry

    static func popoverGeometry() {
        print("\n# popover geometry")

        let pitch = ExtensionFormMetrics.popoverRowHeight + ExtensionFormMetrics.popoverRowSpacing
        check(
            "three rows measure exactly three rows",
            ExtensionFormMetrics.popoverListHeight(rows: 3)
                == pitch * 3 - ExtensionFormMetrics.popoverRowSpacing)
        check("no rows measure nothing", ExtensionFormMetrics.popoverListHeight(rows: 0) == 0)
        check(
            "a long list caps at the visible rows",
            ExtensionFormMetrics.popoverListHeight(rows: 40)
                == ExtensionFormMetrics.popoverRowsMaxHeight)
        check(
            "the cap is a half row, so it reads as scrollable",
            ExtensionFormMetrics.popoverVisibleRows != ExtensionFormMetrics.popoverVisibleRows
                .rounded())
        check(
            "a search row adds its own height",
            ExtensionFormMetrics.popoverHeight(rows: 3, hasSearchField: true)
                - ExtensionFormMetrics.popoverHeight(rows: 3, hasSearchField: false)
                == ExtensionFormMetrics.popoverSearchHeight)
        check(
            "a section heading takes room of its own",
            ExtensionFormMetrics.popoverListHeight(rows: 4, headers: 2)
                - ExtensionFormMetrics.popoverListHeight(rows: 4)
                == (ExtensionFormMetrics.popoverSectionHeaderHeight
                    + ExtensionFormMetrics.popoverRowSpacing) * 2)
        check(
            "and a headed list still caps at the visible rows",
            ExtensionFormMetrics.popoverListHeight(rows: 40, headers: 6)
                == ExtensionFormMetrics.popoverRowsMaxHeight)
        check(
            "an empty list still measures the row it draws, since the panel is sized to this",
            ExtensionFormMetrics.popoverHeight(rows: 0, hasSearchField: false)
                == ExtensionFormMetrics.popoverRowHeight + ExtensionFormMetrics.popoverPadding * 2)
    }

    static func popoverPlacement() {
        print("\n# popover placement")

        let control = CGRect(x: 0, y: 100, width: 360, height: 32)

        let below = ExtensionFormMetrics.placement(
            anchor: control, popoverHeight: 200, containerHeight: 600)
        check("it opens downward when there is room", !below.flipped)
        check(
            "and sits one gap under the control",
            below.y == control.maxY + ExtensionFormMetrics.popoverGap)

        // A control near the bottom of a tall form: no room under it, plenty over it.
        let low = CGRect(x: 0, y: 500, width: 360, height: 32)
        let above = ExtensionFormMetrics.placement(
            anchor: low, popoverHeight: 200, containerHeight: 600)
        check("it flips up when the bottom would cut it off", above.flipped)
        check(
            "and sits one gap over the control",
            above.y == low.minY - ExtensionFormMetrics.popoverGap - 200)

        // Taller than the container either way; showing its start beats showing its middle.
        let cramped = ExtensionFormMetrics.placement(
            anchor: low, popoverHeight: 500, containerHeight: 300)
        check("a list taller than the form still starts on screen", cramped.y >= 0)
        check("and does not claim to have flipped", !cramped.flipped)

        // Exactly enough room below is still room: the rule may not flip on a tie.
        let exact = ExtensionFormMetrics.placement(
            anchor: control, popoverHeight: 100, containerHeight: 238)
        check("a list that exactly fits opens downward", !exact.flipped)
    }

    // MARK: - Dates

    static func datePresets() {
        print("\n# date presets")

        let rows = ExtensionDateExpression.presets(
            now: now, calendar: calendar, includesTime: false)
        check("the first row clears the field", rows.first?.title == "No Date")
        check("and carries no date to clear it with", rows.first?.date == nil)
        check("today, tomorrow and yesterday follow", rows[1].title == "Today")
        check("tomorrow is second", rows[2].title == "Tomorrow")
        check("yesterday is third", rows[3].title == "Yesterday")
        check(
            "tomorrow really is the next day",
            rows[2].date == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        check("the week that follows is named", rows[4].title == "Sunday", rows[4].title)
        check("every dated row states its day", rows.dropFirst().allSatisfy { $0.detail != nil })
    }

    static func dateParsing() {
        print("\n# date expressions")

        let today = calendar.startOfDay(for: now)
        check("today parses", parse("today") == today)
        check(
            "tomorrow parses",
            parse("tomorrow") == calendar.date(byAdding: .day, value: 1, to: today))
        check(
            "yesterday parses",
            parse("yesterday") == calendar.date(byAdding: .day, value: -1, to: today))
        check(
            "in 3 days parses",
            parse("in 3 days") == calendar.date(byAdding: .day, value: 3, to: today))
        check(
            "3 days parses without the preposition",
            parse("3 days") == calendar.date(byAdding: .day, value: 3, to: today))
        check(
            "in 2 weeks parses",
            parse("in 2 weeks") == calendar.date(byAdding: .weekOfYear, value: 2, to: today))

        // 4 September 2026 is a Friday, so Monday is the 7th.
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))
        check("a weekday name means the coming one", parse("monday") == monday)
        check("next monday means the same", parse("next monday") == monday)
        check("a weekday never points backwards", parse("thursday")! > today)

        check(
            "a day and month parse",
            parse("25 dec") == calendar.date(from: DateComponents(year: 2026, month: 12, day: 25)))
        check(
            "and the other way round",
            parse("dec 25") == calendar.date(from: DateComponents(year: 2026, month: 12, day: 25)))
        check(
            "a date already past means next year",
            parse("1 jan") == calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))

        let tomorrowTen = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 5, hour: 10, minute: 0))
        check("tomorrow at 10am parses whole", parse("tomorrow at 10am") == tomorrowTen)
        check("and without the at", parse("tomorrow 10am") == tomorrowTen)
        check(
            "pm is afternoon",
            parse("today at 7pm")
                == calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 19)))
        check(
            "24-hour times parse",
            parse("today at 22:15")
                == calendar.date(
                    from: DateComponents(year: 2026, month: 9, day: 4, hour: 22, minute: 15)))
        check(
            "midnight is not noon",
            parse("today at 12am")
                == calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 0)))

        check("nonsense parses to nothing", parse("wibble") == nil)
        check("an empty expression parses to nothing", parse("") == nil)
        // A bare number is a count without a unit, and reading it as an hour would guess.
        check("a bare number is not a time", parse("10") == nil)
    }

    static func dateSuggestions() {
        print("\n# date suggestions")

        let empty = ExtensionDateExpression.suggestions(
            query: "", now: now, calendar: calendar, includesTime: false)
        check("an empty query offers the presets", empty.first?.title == "No Date")

        let typed = ExtensionDateExpression.suggestions(
            query: "in 3 days", now: now, calendar: calendar, includesTime: false)
        check("what was typed leads the list", typed.first?.title == "in 3 days")
        check(
            "and resolves to the day it names",
            typed.first?.date
                == calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now)))

        let partial = ExtensionDateExpression.suggestions(
            query: "tom", now: now, calendar: calendar, includesTime: false)
        check("a partial word still finds its preset", partial.contains { $0.title == "Tomorrow" })

        let nonsense = ExtensionDateExpression.suggestions(
            query: "zzz", now: now, calendar: calendar, includesTime: false)
        check("an unparsable query offers nothing", nonsense.isEmpty)
    }

    // MARK: - Helpers

    static func parse(_ expression: String) -> Date? {
        ExtensionDateExpression.parse(expression, now: now, calendar: calendar)
    }

    static func check(_ description: String, _ condition: Bool, _ detail: String? = nil) {
        if condition {
            passes += 1
            print("PASS  \(description)")
        } else {
            failures += 1
            print("FAIL  \(description)" + (detail.map { " — \($0)" } ?? ""))
        }
    }
}
