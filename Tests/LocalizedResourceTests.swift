import Foundation

@main
@MainActor
struct LocalizedResourceTests {
    static var failures = 0
    static var passes = 0
    static let languageVariable = "TINYCAST_RESOLVED_LANGUAGE"

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    static func main() {
        if let language = ProcessInfo.processInfo.environment[languageVariable] {
            checkResolution(in: language)
            exit(failures == 0 ? 0 : 1)
        }
        do {
            try checkEachLanguage()
        } catch {
            check("each language runs", false, error.localizedDescription)
        }
        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// `resolved()` reads `Bundle.main`, so each language runs a copy that sits beside the tables.
    private static func checkEachLanguage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-resolved-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = [
            "xcstringstool", "compile", "Tinycast/Resources/Localizable.xcstrings",
            "--output-directory", root.path
        ]
        try compile.run()
        compile.waitUntilExit()
        guard compile.terminationStatus == 0, let executable = Bundle.main.executableURL else {
            check("Localizable compiles", false)
            return
        }
        let copy = root.appendingPathComponent(executable.lastPathComponent)
        try FileManager.default.copyItem(at: executable, to: copy)

        for language in ["en", "de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"] {
            let process = Process()
            process.executableURL = copy
            process.arguments = ["-AppleLanguages", "(\(language))"]
            process.environment = ProcessInfo.processInfo.environment.merging([languageVariable: language]) {
                $1
            }
            try process.run()
            process.waitUntilExit()
            check("\(language) resolves like String(localized:)", process.terminationStatus == 0)
        }
    }

    private static func checkResolution(in language: String) {
        check(
            "\(language) is the bundle's localization",
            Bundle.main.preferredLocalizations.first == language)
        let name = "Notes"
        var resources: [(label: String, resource: LocalizedStringResource)] = [
            ("a translated key", "Cancel"),
            ("a key the catalog lacks", "Tinycast harness key"),
            (
                "a contextual key",
                LocalizedStringResource("apple-shortcuts-section", defaultValue: "Shortcuts")
            ),
            (
                "a contextual key the catalog lacks",
                LocalizedStringResource("tinycast-harness-key", defaultValue: "Cancel")
            ),
            ("an interpolated key", "Customize \(name)"),
            ("a literal percent sign", "Set Volume to 25%")
        ]
        for count in [1, 2, 5] {
            resources.append(("a plural of \(count)", "\(count) hidden items"))
        }
        for (label, resource) in resources {
            let expected = String(localized: resource)
            let resolved = resource.resolved()
            check("\(language) \(label)", resolved == expected, "\(resolved) instead of \(expected)")
        }
    }
}
