// Standalone test for the launcher matcher — compiles the *real* Foundation-only source (no copy to
// sync): swiftc Smallcast/Core/FuzzyMatch.swift Tools/fuzz-test.swift -o /tmp/fuzz-test && /tmp/fuzz-test

import Foundation

@main
struct FuzzTests {
    static let apps = [
        "Google Chrome", "Chess", "Time Machine", "Safari", "Bluetooth File Exchange",
        "Screenshot", "Screen Sharing", "Visual Studio Code", "Photos", "App Store",
        "System Settings", "Calendar", "Terminal",
    ]

    static var failures = 0

    static func main() {
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

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func rank(_ query: String) -> [String] {
        apps.compactMap { name -> (String, Int)? in
            guard let s = FuzzyMatch.score(query: query, candidate: name) else { return nil }
            return (name, s)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.count < $1.0.count }
        .map(\.0)
    }

    static func check(_ desc: String, _ cond: Bool, _ detail: String = "") {
        if cond {
            print("PASS  \(desc)")
        } else {
            print("FAIL  \(desc)  \(detail)")
            failures += 1
        }
    }
}
