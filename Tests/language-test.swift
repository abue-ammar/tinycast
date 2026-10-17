import Foundation

/// Pins how a stored `AppleLanguages` list reads back, and what each choice launches into.
@main
@MainActor
struct LanguageTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    static func main() {
        print("# a stored list reads back as the choice that wrote it")
        check("nothing stored is English", AppLanguage(storedPreferences: nil) == .english)
        check("an empty list is English", AppLanguage(storedPreferences: []) == .english)
        for language in AppLanguage.allCases {
            check(
                "\(language.rawValue) round-trips",
                AppLanguage(storedPreferences: [language.rawValue]) == language)
        }

        print("# System Settings' regional tags land on the shipped language")
        check("de-DE is German", AppLanguage(storedPreferences: ["de-DE"]) == .german)
        check("pt-BR is Portuguese", AppLanguage(storedPreferences: ["pt-BR"]) == .portuguese)
        check("pt-PT is Portuguese", AppLanguage(storedPreferences: ["pt-PT"]) == .portuguese)
        check(
            "zh-Hans-CN is Simplified Chinese",
            AppLanguage(storedPreferences: ["zh-Hans-CN"]) == .chineseSimplified)
        check("an unshipped language reads as English", AppLanguage(storedPreferences: ["it"]) == .english)

        print("# each choice launches into its own localization")
        let shipped = ["en", "de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"]
        for language in AppLanguage.allCases {
            check(
                "\(language.rawValue) resolves to its bundled localization",
                Bundle.preferredLocalizations(from: shipped, forPreferences: [language.rawValue]).first
                    == language.rawValue)
        }

        print("# every language names itself")
        check(
            "titles are distinct",
            Set(AppLanguage.allCases.map(\.title)).count == AppLanguage.allCases.count)
        check("an unknown raw value is rejected", AppLanguage(rawValue: "klingon") == nil)

        do {
            try checkCatalogs()
        } catch {
            check("catalogs compile and load", false, error.localizedDescription)
        }

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func checkCatalogs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-languages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for catalog in ["Localizable", "InfoPlist"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "xcstringstool", "compile", "Tinycast/Resources/\(catalog).xcstrings",
                "--output-directory", root.path
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                check("\(catalog) compiles", false)
                return
            }
        }

        let windows: [String: (String, String)] = [
            "en": ("1 window", "2 windows"), "de": ("1 Fenster", "2 Fenster"),
            "es": ("1 ventana", "2 ventanas"), "fr": ("1 fenêtre", "2 fenêtres"),
            "ja": ("1個のウインドウ", "2個のウインドウ"), "ko": ("윈도우 1개", "윈도우 2개"),
            "pt": ("1 janela", "2 janelas"), "ru": ("1 окно", "2 окна"),
            "zh-Hans": ("1 个窗口", "2 个窗口")
        ]
        for language in AppLanguage.allCases {
            let code = language.rawValue
            guard let bundle = Bundle(url: root.appendingPathComponent("\(code).lproj")),
                let expected = windows[code]
            else {
                check("\(code) resources exist", false)
                continue
            }
            let locale = Locale(identifier: code)
            let one = 1
            let two = 2
            check(
                "\(code) singular is selected at runtime",
                String(localized: "\(one) windows", bundle: bundle, locale: locale) == expected.0)
            check(
                "\(code) plural is selected at runtime",
                String(localized: "\(two) windows", bundle: bundle, locale: locale) == expected.1)
            let size = "5 MB"
            let reordered = String(
                localized: "Reclaims \(size) from \(two) items.", bundle: bundle, locale: locale)
            check(
                "\(code) mixed string and count arguments survive translation",
                reordered.contains(size) && reordered.contains("2") && !reordered.contains("%@"))
            let privacy = bundle.localizedString(
                forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist")
            check("\(code) camera privacy prompt loads", privacy.contains("Tinycast"))

            if code == "en" || code == "ru" {
                let expectedPair = code == "en" ? "1 window · 2 displays" : "1 окно · 2 дисплея"
                check(
                    "\(code) plural substitutions select each argument independently",
                    String(
                        localized: "\(one) windows · \(two) displays", bundle: bundle, locale: locale)
                        == expectedPair)
                let expectedReverse = code == "en" ? "2 windows · 1 display" : "2 окна · 1 дисплей"
                check(
                    "\(code) the second count can be singular independently",
                    String(
                        localized: "\(two) windows · \(one) displays", bundle: bundle, locale: locale)
                        == expectedReverse)
            }
            if code == "ru" {
                let five = 5
                let twentyOne = 21
                check(
                    "Russian many is selected at runtime",
                    String(localized: "\(five) windows", bundle: bundle, locale: locale) == "5 окон")
                check(
                    "Russian 21 selects one rather than other",
                    String(localized: "\(twentyOne) windows", bundle: bundle, locale: locale) == "21 окно")
            }
        }
    }
}
