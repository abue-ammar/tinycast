// Standalone test for the launcher matcher (run: swift Tools/fuzz-test.swift); keep in sync with FuzzyMatch in Tinycast/Core/AppIndex.swift.

import Foundation

enum FuzzyMatch {
    static func score(query: String, candidate: String) -> Int? {
        let q = normalized(query)
        let c = normalized(candidate)
        guard !q.isEmpty else { return 0 }

        if c == q { return 100_000 }
        if c.hasPrefix(q) { return 90_000 - c.count }

        if let range = c.range(of: q) {
            let atWordStart = isWordStart(c, range.lowerBound)
            return (atWordStart ? 80_000 : 70_000) - c.count
        }

        return subsequenceScore(Array(q), Array(c))
    }

    private static func normalized(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    private static func isWordStart(_ s: String, _ index: String.Index) -> Bool {
        if index == s.startIndex { return true }
        let before = s[s.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    private static func subsequenceScore(_ q: [Character], _ c: [Character]) -> Int? {
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            var bonus = 1
            if ci == prev + 1 {
                run += 1
                bonus += run * 3
            } else {
                run = 0
            }
            if ci == 0 {
                bonus += 12
            } else {
                let b = c[ci - 1]
                if !b.isLetter && !b.isNumber { bonus += 8 }
            }
            score += bonus
            prev = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        return score
    }
}

let apps = [
    "Google Chrome", "Chess", "Time Machine", "Safari", "Bluetooth File Exchange",
    "Screenshot", "Screen Sharing", "Visual Studio Code", "Photos", "App Store",
    "System Settings", "Calendar", "Terminal", "WhatsApp", "Wick",
]

func rank(_ query: String, boosts: [String: Int] = [:]) -> [String] {
    apps.compactMap { name -> (String, Int)? in
        guard let s = FuzzyMatch.score(query: query, candidate: name) else { return nil }
        return (name, s + boosts[name, default: 0])
    }
    .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.count < $1.0.count }
    .map(\.0)
}

var failures = 0
func check(_ desc: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        print("PASS  \(desc)")
    } else {
        print("FAIL  \(desc)  \(detail)")
        failures += 1
    }
}

let chrome = rank("chrome")
check("'chrome' top is Google Chrome", chrome.first == "Google Chrome", "got \(chrome)")
check("'chrome' does not include Chess", !chrome.contains("Chess"), "got \(chrome)")

let ch = rank("ch")
check("'ch' includes Google Chrome", ch.contains("Google Chrome"), "got \(ch)")
check("'ch' includes Chess", ch.contains("Chess"))
check(
    "'ch' ranks Chess (prefix) above Chrome",
    ch.firstIndex(of: "Chess")! < ch.firstIndex(of: "Google Chrome")!, "got \(ch)")

check("'saf' top is Safari", rank("saf").first == "Safari", "got \(rank("saf"))")
check("'tm' includes Time Machine", rank("tm").contains("Time Machine"), "got \(rank("tm"))")
check(
    "'code' includes Visual Studio Code", rank("code").contains("Visual Studio Code"),
    "got \(rank("code"))")
check("'terminal' exact top", rank("terminal").first == "Terminal")
check("'xyz' matches nothing", rank("xyz").isEmpty, "got \(rank("xyz"))")

let defaultW = rank("w")
check(
    "shorter Wick wins the default prefix tie",
    defaultW.firstIndex(of: "Wick")! < defaultW.firstIndex(of: "WhatsApp")!,
    "got \(defaultW)")
let learnedW = rank("w", boosts: ["WhatsApp": 2_100])
check(
    "learned boost promotes WhatsApp within the prefix tier",
    learnedW.firstIndex(of: "WhatsApp")! < learnedW.firstIndex(of: "Wick")!,
    "got \(learnedW)")
let markedWhatsApp = "\u{200E}WhatsApp"
check(
    "invisible format mark does not demote WhatsApp's prefix match",
    FuzzyMatch.score(query: "w", candidate: markedWhatsApp)
        == FuzzyMatch.score(query: "w", candidate: "WhatsApp"))
check(
    "learned marked WhatsApp can outrank Wick",
    FuzzyMatch.score(query: "w", candidate: markedWhatsApp)! + 2_100
        > FuzzyMatch.score(query: "w", candidate: "Wick")!)

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
