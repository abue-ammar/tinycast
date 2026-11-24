import Foundation

@main
@MainActor
struct PlanUsageTests {
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

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    static let english = Locale(identifier: "en_US")
    static let now = Date(timeIntervalSince1970: 1_795_500_000)

    static func main() {
        claudeAnswersWithItsWindows()
        claudeWithoutPlanLimitsIsUnavailable()
        claudeErrorsAndSilenceAreFailures()
        claudeModelLimitsReplaceTheirFallbacks()
        claudeIsAnsweredOnlyByAWholeLine()
        codexAnswersWithItsWindowsAndResets()
        codexNamesEveryLimitButTheGeneralOne()
        codexFallsBackToItsSingleLimit()
        levelsFollowTheThresholds()
        paceProjectsOnlyARealExhaustion()
        pinsRoundTripAndFallBackToTheFullest()
        alertsFireOnCrossingsAndResets()
        entriesNoteOnlyOldOrUnrefreshedNumbers()
        formatsReadNaturally()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Claude

    static func claudeLine(_ payload: String, id: String = PlanUsage.claudeRequestID) -> String {
        #"{"type":"control_response","response":{"subtype":"success","request_id":"\#(id)","response":\#(payload)}}"#
            + "\n"
    }

    static func claudeAnswersWithItsWindows() {
        let payload = """
            {"subscription_type":"pro","rate_limits_available":true,"rate_limits":{\
            "five_hour":{"utilization":45,"resets_at":"2026-11-24T23:00:00.179639+00:00"},\
            "seven_day":{"utilization":75.5,"resets_at":"2026-11-25T08:00:00+00:00"},\
            "seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null}}
            """
        let output = #"{"type":"system","subtype":"init"}"# + "\n" + claudeLine(payload)
        guard case .usage(let usage) = PlanUsage.claude(output) else {
            return expect(false, "a Claude answer reads as usage")
        }
        expect(usage.plan == "Pro", "the plan is title-cased")
        expect(usage.windows.map(\.id) == ["five_hour", "seven_day"], "windows in Claude's order")
        expect(usage.windows.map(\.title) == ["5-hour", "Weekly"], "windows say what they are")
        expect(usage.windows[1].usedPercent == 75.5, "a fractional percentage survives")
        let reset = usage.windows[0].resetsAt?.timeIntervalSince1970 ?? 0
        expect(abs(reset - 1_795_561_200) < 1, "microsecond reset times parse")
        expect(usage.windows[0].duration == PlanUsage.fiveHours, "the 5-hour window knows its span")
        expect(usage.resetCredits == 0, "Claude grants no resets")
    }

    static func claudeWithoutPlanLimitsIsUnavailable() {
        let output = claudeLine(#"{"rate_limits_available":false,"rate_limits":null}"#)
        expect(PlanUsage.claude(output) == .unavailable, "an API key login has no limits to show")
    }

    static func claudeErrorsAndSilenceAreFailures() {
        let error =
            #"{"type":"control_response","response":{"subtype":"error","request_id":"tinycast-usage","error":"nope"}}"#
        expect(PlanUsage.claude(error + "\n") == .failed, "an error answer is a failure")
        expect(PlanUsage.claude("") == .failed, "no answer is a failure")
        let other = claudeLine(#"{"rate_limits_available":true}"#, id: "someone-else")
        expect(PlanUsage.claude(other) == .failed, "another request's answer is not ours")
        let empty = claudeLine(#"{"rate_limits_available":true,"rate_limits":{}}"#)
        expect(PlanUsage.claude(empty) == .failed, "limits with no windows are a failure")
    }

    static func claudeModelLimitsReplaceTheirFallbacks() {
        let payload = """
            {"rate_limits_available":true,"rate_limits":{\
            "seven_day":{"utilization":10},\
            "model_scoped":[{"display_name":"Opus","utilization":30},\
            {"display_name":" ","utilization":5},{"display_name":"Fable"}],\
            "seven_day_opus":{"utilization":99},"seven_day_sonnet":{"utilization":20}}}
            """
        guard case .usage(let usage) = PlanUsage.claude(claudeLine(payload)) else {
            return expect(false, "model limits read as usage")
        }
        expect(
            usage.windows.map(\.title) == ["Weekly", "Opus weekly", "Sonnet weekly"],
            "a scoped model replaces its fallback, a nameless or unmeasured one is skipped")
        expect(usage.window(id: "model:opus")?.usedPercent == 30, "the scoped figure wins")
        expect(usage.plan == nil, "no subscription type, no plan")
    }

    static func claudeIsAnsweredOnlyByAWholeLine() {
        let line = claudeLine(#"{"rate_limits_available":true}"#)
        expect(!PlanUsage.claudeAnswered(String(line.dropLast(10))), "half a line waits")
        expect(PlanUsage.claudeAnswered(line), "a whole line answers")
        expect(!PlanUsage.claudeAnswered(#"{"type":"system"}"# + "\n"), "another line does not")
    }

    // MARK: - Codex

    static func codexResponse(_ json: String) -> [String: JSONValue] {
        JSONValue(data: Data(json.utf8))?.objectValue ?? [:]
    }

    static func codexAnswersWithItsWindowsAndResets() {
        let limit = """
            {"limitId":"codex","limitName":null,"planType":"plus",\
            "primary":{"usedPercent":66,"windowDurationMins":300,"resetsAt":1795558348},\
            "secondary":{"usedPercent":55,"windowDurationMins":10080,"resetsAt":1795814198}}
            """
        let response = codexResponse(
            """
            {"rateLimits":\(limit),"rateLimitsByLimitId":{"codex":\(limit)},\
            "rateLimitResetCredits":{"availableCount":2,"credits":[]}}
            """)
        guard let usage = PlanUsage(codex: response) else {
            return expect(false, "a Codex answer reads as usage")
        }
        expect(usage.plan == "Plus", "the plan reads as ChatGPT names it")
        expect(usage.windows.map(\.title) == ["5-hour", "Weekly"], "windows named by their span")
        expect(usage.windows.map(\.usedPercent) == [66, 55], "percentages carried")
        expect(
            usage.windows[1].resetsAt == Date(timeIntervalSince1970: 1_795_814_198),
            "reset times are Unix seconds")
        expect(usage.windows[1].duration == PlanUsage.week, "a week is a week")
        expect(usage.resetCredits == 2, "free resets are counted")
    }

    static func codexNamesEveryLimitButTheGeneralOne() {
        let response = codexResponse(
            """
            {"rateLimitsByLimitId":{\
            "spark":{"limitName":"Spark","primary":{"usedPercent":5,"windowDurationMins":1440}},\
            "codex":{"primary":{"usedPercent":1,"windowDurationMins":90},\
            "secondary":{"usedPercent":2}}}}
            """)
        let titles = PlanUsage(codex: response)?.windows.map(\.title)
        expect(
            titles == ["90-minute", "Secondary window", "Spark · 1-day"],
            "the general limit leads, the others carry their names")
    }

    static func codexFallsBackToItsSingleLimit() {
        let single = codexResponse(#"{"rateLimits":{"primary":{"usedPercent":12}}}"#)
        expect(
            PlanUsage(codex: single)?.windows.map(\.title) == ["Primary window"],
            "an answer without the per-limit map still reads")
        expect(PlanUsage(codex: codexResponse("{}")) == nil, "no windows is no usage")
    }

    // MARK: - Windows

    static func window(
        _ used: Double, id: String = "w", duration: TimeInterval? = PlanUsage.week,
        resetsIn: TimeInterval? = nil
    ) -> PlanUsage.Window {
        PlanUsage.Window(
            id: id, title: id, usedPercent: used, duration: duration,
            resetsAt: resetsIn.map { now.addingTimeInterval($0) })
    }

    static func levelsFollowTheThresholds() {
        expect(window(79.9).level == .normal, "under 80% is comfortable")
        expect(window(80).level == .high, "80% is high")
        expect(window(95).level == .critical, "95% is critical")
        expect(window(140).usedPercent == 100, "an overshoot is clamped")
        expect(window(-3).fraction == 0, "a negative reading is clamped")
    }

    static func paceProjectsOnlyARealExhaustion() {
        let week = PlanUsage.week
        let ahead = window(60, resetsIn: week * 0.6)
        expect(
            abs((ahead.elapsedFraction(at: now) ?? 0) - 0.4) < 0.000_1,
            "elapsed is the share of the window gone")
        let exhaustion = ahead.exhaustion(at: now)
        expect(exhaustion != nil, "60% used at 40% of the week runs out early")
        expect(
            abs((exhaustion?.timeIntervalSince(now) ?? 0) - week * 0.4 * 40 / 60) < 1,
            "the projection keeps the pace so far")
        expect(window(20, resetsIn: week * 0.5).exhaustion(at: now) == nil, "behind pace lasts")
        expect(window(5, resetsIn: week * 0.95).exhaustion(at: now) == nil, "too early to tell")
        expect(window(100, resetsIn: week * 0.5).exhaustion(at: now) == nil, "already spent")
        expect(window(50, duration: nil, resetsIn: 60).elapsedFraction(at: now) == nil, "no span")
        expect(window(50).elapsedFraction(at: now) == nil, "no reset time")
    }

    // MARK: - Pin

    static func pinsRoundTripAndFallBackToTheFullest() {
        let pinned = PlanUsagePin.window(.chatGPT, id: "codex/primary")
        expect(PlanUsagePin(rawValue: pinned.rawValue) == pinned, "a pin round-trips")
        expect(PlanUsagePin(rawValue: nil) == .automatic, "nothing stored is automatic")
        expect(PlanUsagePin(rawValue: "gemini:x") == .automatic, "an unknown provider is ignored")
        expect(PlanUsagePin.automatic.rawValue == nil, "automatic stores nothing")

        let usage: [PlanUsage.Provider: PlanUsage] = [
            .claude: PlanUsage(
                plan: nil, windows: [window(40, id: "a"), window(70, id: "b")], resetCredits: 0),
            .chatGPT: PlanUsage(plan: nil, windows: [window(70, id: "c")], resetCredits: 0)
        ]
        let fullest = PlanUsagePin.automatic.target(in: usage)
        expect(
            fullest?.provider == .claude && fullest?.window.id == "b",
            "automatic follows the fullest, the first on a tie")
        let chosen = PlanUsagePin.window(.claude, id: "a")
        expect(chosen.target(in: usage)?.window.id == "a", "a pin is followed")
        expect(chosen.effective(in: usage) == chosen, "a present pin is in force")
        let gone = PlanUsagePin.window(.chatGPT, id: "missing")
        expect(gone.target(in: usage)?.window.id == "b", "a missing pin follows the fullest")
        expect(gone.effective(in: usage) == .automatic, "a missing pin is not in force")
        expect(PlanUsagePin.automatic.target(in: [:]) == nil, "nothing read, nothing followed")
    }

    // MARK: - Alerts

    static func usage(_ windows: PlanUsage.Window...) -> PlanUsage {
        PlanUsage(plan: nil, windows: windows, resetCredits: 0)
    }

    static func alertsFireOnCrossingsAndResets() {
        let policy = PlanUsageAlertPolicy.self
        expect(
            policy.alert(for: .claude, from: nil, to: usage(window(97))) == nil,
            "the first read compares with nothing")
        let high = policy.alert(for: .claude, from: usage(window(70)), to: usage(window(81)))
        expect(high?.kind == .reached(.high), "crossing 80% is noticed")
        expect(high?.message == "Claude w limit at 81%", "the notice names the window")
        expect(
            policy.alert(for: .claude, from: usage(window(81)), to: usage(window(90))) == nil,
            "staying high says nothing more")
        let both = policy.alert(
            for: .chatGPT, from: usage(window(70, id: "a"), window(90, id: "b")),
            to: usage(window(85, id: "a"), window(96, id: "b")))
        expect(both?.kind == .reached(.critical), "the most severe crossing wins")
        let reset = policy.alert(for: .chatGPT, from: usage(window(88)), to: usage(window(4)))
        expect(reset?.kind == .reset, "a nearly spent window emptying is a reset")
        expect(reset?.message == "ChatGPT w limit reset", "the reset names the window")
        expect(
            policy.alert(for: .claude, from: usage(window(88)), to: usage(window(60))) == nil,
            "a small fall is not a reset")
        expect(
            policy.alert(for: .claude, from: usage(window(40)), to: usage(window(2))) == nil,
            "a comfortable window resetting is not news")
        expect(
            policy.alert(for: .claude, from: usage(window(70, id: "a")), to: usage(window(90, id: "b")))
                == nil,
            "a window seen for the first time has nothing to cross")
    }

    // MARK: - Entries and text

    static func entriesNoteOnlyOldOrUnrefreshedNumbers() {
        let read = usage(window(10))
        let fresh = PlanUsageEntry(usage: read, updatedAt: now.addingTimeInterval(-60))
        expect(fresh.note(at: now) == nil, "fresh numbers need no note")
        let old = PlanUsageEntry(usage: read, updatedAt: now.addingTimeInterval(-16 * 60))
        expect(old.note(at: now) == .updated(ago: 16 * 60), "old numbers say how old")
        var failed = fresh
        failed.failed = true
        expect(failed.note(at: now) == .refreshFailed, "a failed refresh is said")
        expect(PlanUsageEntry(failed: true).note(at: now) == nil, "no numbers, no note")
    }

    static func formatsReadNaturally() {
        expect(PlanUsageFormat.duration(3 * 86_400 + 3_700, locale: english) == "3d 1h", "days")
        expect(PlanUsageFormat.duration(2 * 3_600 + 14 * 60, locale: english) == "2h 14m", "hours")
        expect(PlanUsageFormat.duration(20, locale: english) == "1m", "never zero minutes")
        expect(PlanUsageFormat.percent(45.4, locale: english) == "45%", "whole percentages")
        let today = now.addingTimeInterval(3_600)
        let soon = now.addingTimeInterval(3 * 86_400)
        let later = now.addingTimeInterval(20 * 86_400)
        // The system puts a narrow no-break space before the meridiem.
        let format = { (date: Date) in
            PlanUsageFormat.resetTime(date, now: now, calendar: utc, locale: english)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        expect(format(today) == "7:00 AM", "a reset today is a time")
        expect(format(soon) == "Fri 6:00 AM", "a reset this week names the day")
        expect(format(later) == "Dec 14", "a later reset is a date")
    }
}
