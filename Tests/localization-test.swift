import AppKit
import SwiftUI

@main
struct LocalizationTests {
    @MainActor static func main() throws {
        if CommandLine.arguments.contains("--check-live") {
            checkLiveLanguage()
            return
        }
        if CommandLine.arguments.contains("--set-language") {
            AppLanguage(rawValue: CommandLine.arguments[2])!.save(to: .standard)
            return
        }
        if CommandLine.arguments.contains("--check") {
            try checkLanguage()
            return
        }
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "com.tinycast.localization-test.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        defer { try? files.removeItem(at: root) }
        let contents = root.appendingPathComponent("Localization.app/Contents")
        let resources = contents.appendingPathComponent("Resources")
        let executable = contents.appendingPathComponent("MacOS/localization-test")
        try files.createDirectory(at: resources, withIntermediateDirectories: true)
        try files.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(atPath: CommandLine.arguments[0], toPath: executable.path)
        let info = [
            "CFBundleExecutable": "localization-test", "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": domain
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        for table in ["Localizable", "InfoPlist"] {
            try run(
                "/usr/bin/xcrun",
                [
                    "xcstringstool", "compile", "--output-directory", resources.path,
                    "Tinycast/Resources/\(table).xcstrings"
                ])
        }
        for language in ["en", "zh-Hans", "fr"] {
            try run(executable.path, ["--check", language, "-AppleLanguages", "(\(language))"])
        }
        for language in ["zh-Hans", "en"] {
            try run(executable.path, ["--set-language", language])
            try run(executable.path, ["--check", language])
        }
        try run(executable.path, ["--set-language", "system"])
        try run(executable.path, ["--check-live"])
        precondition(AppLanguage.selection(in: .standard, domain: domain) == .system)
        checkPreferences()
        print("Localization resources, interpolation, fallback and settings navigation passed")
    }

    @MainActor static func checkLiveLanguage() {
        let domain = Bundle.main.bundleIdentifier!
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        AppLanguage.english.save(to: .standard)
        let rendered = RenderedCopy()
        let host = NSHostingView(rootView: LiveCopy(rendered: rendered).localizationEnvironment())
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let navigation = SettingsNavigationState(tab: .general)
        let chrome = SettingsToolbarController(navigation: navigation)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        chrome.install(in: window)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let identity = rendered.identity
        for language in [AppLanguage.simplifiedChinese, .english, .simplifiedChinese, .system] {
            language.save(to: .standard)
            let locale = AppLocalization.locale
            let chinese = locale.identifier == "zh-Hans"
            let expectedChoice = chinese ? "跟随系统" : "System"
            let deadline = Date().addingTimeInterval(2)
            repeat {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                host.layoutSubtreeIfNeeded()
            } while (rendered.locale != locale.identifier
                || pickerChoices(in: host).count != 2
                || !pickerChoices(in: host).contains(expectedChoice)
                || !pickerChoices(in: host).contains("English")
                || window.title != (chinese ? "通用" : "General")) && Date() < deadline
            precondition(rendered.locale == locale.identifier, "Mounted view must update its locale")
            precondition(rendered.identity == identity, "Language changes must preserve SwiftUI state")
            precondition(rendered.title == (chinese ? "设置" : "Settings"))
            precondition(
                window.title == (chinese ? "通用" : "General"),
                "Actual title: \(window.title), language: \(locale.identifier)")
            precondition(
                pickerChoices(in: host).count == 2 && pickerChoices(in: host).contains(expectedChoice)
                    && pickerChoices(in: host).contains("English"),
                "Native picker choices: \(pickerChoices(in: host)), expected \(expectedChoice) and English")
            precondition(
                String(localized: "Lock Screen", bundle: .appLanguage) == (chinese ? "锁定屏幕" : "Lock Screen"))
            let count = 3
            precondition(
                String(localized: "\(count) API connections", bundle: .appLanguage)
                    == (chinese ? "3 个 API 连接" : "3 API connections"))
            for query in ["Language", "语言"] {
                let result = SettingsSearchCatalog.results(for: query).first
                precondition(result?.target == .row(.generalAppearance, "Language"))
                precondition(result?.localizedTitle == (chinese ? "语言" : "Language"))
            }
        }
    }

    @MainActor static func pickerChoices(in view: NSView) -> [String] {
        if let popup = view as? NSPopUpButton {
            return popup.titleOfSelectedItem.map { [$0] } ?? []
        }
        return view.subviews.flatMap { pickerChoices(in: $0) }
    }

    @MainActor final class RenderedCopy {
        var locale = ""
        var title = ""
        var identity: UUID?
    }

    struct LiveCopy: View {
        @Environment(\.locale) private var locale
        @State private var identity = UUID()
        @State private var draft = "User draft"
        @State private var appearance = AppAppearance.system
        @State private var language = AppLanguage.english
        let rendered: RenderedCopy

        var body: some View {
            let title = String(localized: "Settings", bundle: .appLanguage)
            record(title)
            return VStack {
                Text("Settings")
                Text(title)
                TextField("Draft", text: $draft)
                VStack {
                    Group {
                        Picker("Theme", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .id("Theme-\(locale.identifier)")
                        Picker("Language", selection: $language) {
                            ForEach(AppLanguage.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .id("Language-\(locale.identifier)")
                    }
                }
            }
        }

        private func record(_ title: String) {
            rendered.locale = locale.identifier
            rendered.title = title
            rendered.identity = identity
        }
    }

    static func checkPreferences() {
        let domain = "com.tinycast.language-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.register(defaults: ["AppleLanguages": ["zh-Hans"]])
        let inheritedLanguages = defaults.stringArray(forKey: "AppleLanguages")
        precondition(AppLanguage.selection(in: defaults, domain: domain) == .system)
        AppLanguage.english.save(to: defaults)
        precondition(AppLanguage.selection(in: defaults, domain: domain) == .english)
        defaults.set(["zh-Hans-CN"], forKey: "AppleLanguages")
        precondition(AppLanguage.selection(in: defaults, domain: domain) == .simplifiedChinese)
        AppLanguage.system.save(to: defaults)
        precondition(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil)
        precondition(defaults.stringArray(forKey: "AppleLanguages") == inheritedLanguages)
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "Failed: \(arguments)")
    }

    static func checkLanguage() throws {
        let chinese = CommandLine.arguments[2] == "zh-Hans"
        precondition(Bundle.main.localizations.contains("zh-Hans"))
        precondition(String(localized: "Settings") == (chinese ? "设置" : "Settings"))
        precondition(String(localized: "Clipboard History") == (chinese ? "剪贴板历史" : "Clipboard History"))
        precondition(String(localized: "Lock Screen") == (chinese ? "锁定屏幕" : "Lock Screen"))
        precondition(String(localized: "Left Half") == (chinese ? "左半屏" : "Left Half"))
        let count = 3
        precondition(
            String(localized: "\(count) API connections")
                == (chinese ? "3 个 API 连接" : "3 API connections"))
        let remaining = 75
        precondition(String(localized: "\(remaining)% left") == (chinese ? "剩余 75%" : "75% left"))
        let name = "Clipboard History"
        precondition(
            String(localized: "Open \(name)") == (chinese ? "打开 Clipboard History" : "Open Clipboard History")
        )
        let permission = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        precondition(permission?.contains(chinese ? "摄像头" : "camera") == true)
        for tab in SettingsTab.allCases {
            let title = String(localized: String.LocalizationValue(tab.title))
            let result = SettingsSearchCatalog.results(for: title).first
            precondition(result?.tab == tab, "Search for \(title) must reach \(tab)")
        }
        for query in chinese ? ["主题", "Theme"] : ["Theme"] {
            let result = SettingsSearchCatalog.results(for: query).first
            precondition(result?.target == .row(.generalAppearance, "Theme"))
            precondition(result?.title == "Theme", "Search identity must stay stable")
            precondition(result?.localizedTitle == (chinese ? "主题" : "Theme"))
        }
        precondition(SettingsAnchor.generalAppearance.title == "Appearance")
        for query in ["语言", "Language", "简体中文", "English"] {
            precondition(
                SettingsSearchCatalog.results(for: query).first?.target
                    == .row(.generalAppearance, "Language"))
        }
    }
}
