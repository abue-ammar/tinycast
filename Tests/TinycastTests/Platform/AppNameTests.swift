import Foundation
import Testing

@testable import Tinycast

struct AppNameTests {
    @Test(arguments: ["", "   ", "\n\t"])
    func blankDisplayNamesAreAbsent(_ name: String) {
        #expect(AppDisplayName.named(name) == nil)
    }

    @Test func namesRequireATrimmedString() {
        #expect(AppDisplayName.named(nil) == nil)
        #expect(AppDisplayName.named(42) == nil)
        #expect(AppDisplayName.named("  Paw  ") == "Paw")
    }

    @Test(
        arguments: [
            (["CFBundleDisplayName": "", "CFBundleName": "RapidAPI"], "RapidAPI"),
            (["CFBundleDisplayName": "Shown", "CFBundleName": "Internal"], "Shown"),
            (["CFBundleDisplayName": " ", "CFBundleName": ""], nil),
            (
                [
                    "CFBundleDisplayName-macos": "Image Playground", "CFBundleDisplayName": "Playground",
                    "CFBundleName": "Image Playground"
                ], "Image Playground"
            ),
            (["CFBundleDisplayName-macos": "", "CFBundleDisplayName": "Playground"], "Playground"),
            (["CFBundleDisplayName": "Shown", "CFBundleName-macos": "Internal"], "Shown")
        ] as [([String: String], String?)])
    func infoLooksForTheBestUsableName(_ info: [String: String], _ expected: String?) {
        #expect(AppDisplayName.inInfo(info) == expected)
    }

    @Test(arguments: [
        (
            "RapidAPI.app",
            [
                "CFBundleDisplayName": "", "CFBundleName": "RapidAPI",
                "CFBundleIdentifier": "com.luckymarmot.Paw"
            ], "RapidAPI"
        ),
        ("Mystery.app", ["CFBundleIdentifier": "com.example.mystery"], "Mystery"),
        (
            "Ghost.app",
            [
                "CFBundleDisplayName": "  ", "CFBundleName": "",
                "CFBundleIdentifier": "com.example.ghost"
            ], "Ghost"
        )
    ])
    func installedNamesFallBackThroughThePlistToTheFilename(
        _ filename: String, _ info: [String: String], _ expected: String
    ) throws {
        let scratch = try ScratchDirectory("app-name")
        let url = scratch.url.appending(path: filename)
        try writePlist(info, to: url.appending(path: "Contents/Info.plist"))
        let bundle = try #require(Bundle(url: url))
        #expect(bundle.installedAppName == expected)
    }

    @Test(arguments: [
        (
            ["zh-Hans-US"],
            [
                "zh-Hans-US", "zh_Hans_US", "zh-Hans", "zh_Hans", "zh-US", "zh_US", "zh-CN", "zh_CN", "zh",
                "en"
            ]
        ),
        (
            ["zh-Hant-HK"],
            [
                "zh-Hant-HK", "zh_Hant_HK", "zh-Hant", "zh_Hant", "zh-HK", "zh_HK", "zh-TW", "zh_TW", "zh",
                "en"
            ]
        ),
        (["pt-BR"], ["pt-BR", "pt_BR", "pt", "en"]),
        (["nb-NO"], ["nb-NO", "nb_NO", "nb", "no", "en"]),
        (["nb"], ["nb", "no", "en"]),
        (["nb-NO", "nb", "no"], ["nb-NO", "nb_NO", "nb", "no", "en"]),
        (["nn-NO"], ["nn-NO", "nn_NO", "nn", "en"])
    ])
    func resourceLookupUsesPreferredTagsAndTheirOrderedAliases(_ preferred: [String], _ expected: [String]) {
        #expect(BundleLocalization.indexedLanguages(preferred) == expected)
    }

    @Test(arguments: [
        ("zh-Hans-CN", "zh_CN"), ("zh-Hans-HK", "zh_CN"), ("zh-Hant-CN", "zh_TW"),
        ("zh-Hans", "zh_CN"), ("zh-Hant-TW", "zh_TW")
    ])
    func chineseScriptVariantsFindTheirTable(_ language: String, _ region: String) {
        #expect(BundleLocalization.indexedLanguages([language]).contains(region))
    }

    @Test(arguments: [("zh-Hans-HK", "zh_HK"), ("zh-Hant-CN", "zh_CN"), ("zh-Hant-TW", "zh_CN")])
    func chineseVariantsSkipARegionFromTheOtherScript(_ language: String, _ region: String) {
        #expect(!BundleLocalization.indexedLanguages([language]).contains(region))
    }

    @Test func englishIsTheLastSearchableName() {
        #expect(BundleLocalization.indexedLanguages(["zh-Hans-CN"]).last == "en")
    }

    @Test(arguments: [
        (["nb-NO"], "en", ["Kalkulator", "Calculator"]),
        (["de-DE", "nb-NO"], "en", ["Rechner", "Kalkulator", "Calculator"]),
        (["en-US"], "en", ["Calculator"]),
        (["nb-NO"], "no", ["Kalkulator"]), (["nb-NO"], "nb", ["Kalkulator"]),
        (["no"], "no", ["Kalkulator"])
    ])
    func loctableNamesRespectPreferenceAndDevelopmentRegion(
        _ preferred: [String], _ region: String, _ expected: [String]
    ) throws {
        let scratch = try ScratchDirectory("calculator-name")
        let url = try localizedBundle("Calculator.app", in: scratch, table: calculatorTable)
        #expect(names(of: url, preferred: preferred, region: region) == expected)
    }

    @Test(arguments: [
        (["nb-NO", "de-DE"], "no", ["Notater", "Notizen"]),
        (["de-DE", "nb-NO"], "nb", ["Notizen", "Notater"])
    ])
    func anUntranslatedDevelopmentNameRanksInItsPreferredPosition(
        _ preferred: [String], _ region: String, _ expected: [String]
    ) throws {
        let scratch = try ScratchDirectory("norwegian-base")
        let url = try localizedBundle("Notater.app", in: scratch, table: ["de": ["CFBundleName": "Notizen"]])
        #expect(names(of: url, preferred: preferred, region: region) == expected)
    }

    @Test(arguments: [
        ("NorwegianStrings.app", "no", "Norsk navn", ["nb-NO"], ["Norsk navn", "NorwegianStrings"]),
        ("WeChat.app", "zh-Hans", "微信", ["zh-Hans-US", "en-US"], ["微信", "WeChat"])
    ])
    func resourceFoldersCanSupplyNamesWithoutALoctable(
        _ filename: String, _ folder: String, _ name: String, _ preferred: [String], _ expected: [String]
    ) throws {
        let scratch = try ScratchDirectory("app-name-strings")
        let url = scratch.url.appending(path: filename)
        try writeDisplayName(name, language: folder, in: url)
        #expect(names(of: url, preferred: preferred) == expected)
    }

    @Test(arguments: [
        (["nb-NO"], "en", ["Bokmål-kalkulator", "Kalkulator", "Calculator"]),
        (["nb-NO"], "no", ["Bokmål-kalkulator", "Kalkulator"]),
        (["no", "nb"], "nb", ["Kalkulator", "Bokmål-kalkulator"])
    ])
    func explicitBokmalStringsAndTheNorwegianTableFollowLanguageOrder(
        _ preferred: [String], _ region: String, _ expected: [String]
    ) throws {
        let scratch = try ScratchDirectory("bokmal-strings")
        let url = try localizedBundle("Calculator.app", in: scratch, table: calculatorTable)
        try writeDisplayName("Bokmål-kalkulator", language: "nb", in: url)
        #expect(names(of: url, preferred: preferred, region: region) == expected)
    }

    @Test(arguments: [(["nb-NO"], "no"), (["no", "nb"], "nb")])
    func aBokmalTranslationSuppressesDevelopmentFallbackAcrossTheAlias(
        _ preferred: [String], _ region: String
    ) throws {
        let scratch = try ScratchDirectory("bokmal-only")
        let url = try localizedBundle(
            "BokmalOnly.app", in: scratch, table: ["nb": ["CFBundleName": "Bokmålsnavn"]])
        #expect(names(of: url, preferred: preferred, region: region) == ["Bokmålsnavn"])
    }

    @Test(arguments: [
        ("zh-Hans-CN", ["活动监视器", "Activity Monitor"]),
        ("zh-Hans-US", ["活动监视器", "Activity Monitor"]),
        ("zh-Hant-US", ["活動監視器", "Activity Monitor"]),
        ("en-US", ["Activity Monitor"])
    ])
    func loctableUsesThePreferredChineseScriptOutsideItsRegion(
        _ preferred: String, _ expected: [String]
    ) throws {
        let scratch = try ScratchDirectory("activity-monitor")
        let url = try localizedBundle(
            "Activity Monitor.app", in: scratch,
            table: [
                "zh_CN": ["CFBundleName": "活动监视器"],
                "zh_TW": ["CFBundleName": "活動監視器"],
                "en": ["CFBundleName": "Activity Monitor"]
            ])
        #expect(names(of: url, preferred: [preferred]) == expected)
    }

    @Test(
        arguments: [
            (["en-US", "ru-RU"], "en", ["Tips", "Советы"]),
            (["ru-RU"], "en", ["Советы", "Tips"]),
            (["en-US", "ru-RU"], "English", ["Tips", "Советы"]),
            (["en-US", "ru-RU"], nil, ["Советы", "Tips"])
        ] as [([String], String?, [String])])
    func theFilenameFillsInForAnUntranslatedDevelopmentLanguage(
        _ preferred: [String], _ region: String?, _ expected: [String]
    ) throws {
        let scratch = try ScratchDirectory("tips-name")
        let url = try localizedBundle(
            "Tips.app", in: scratch,
            table: [
                "ru": ["CFBundleName": "Советы"], "de": ["CFBundleName": "Tipps"]
            ])
        let indexed = names(of: url, preferred: preferred, region: region)
        #expect(indexed == expected)
        #expect(!indexed.contains("Tipps"))
    }

    @Test func aRegionalSpellingDoesNotDisplaceTheFilename() throws {
        let scratch = try ScratchDirectory("print-center")
        let url = try localizedBundle(
            "Print Center.app", in: scratch, table: ["en_GB": ["CFBundleName": "Print Centre"]])
        let first = try #require(names(of: url, preferred: ["en-US"]).first)
        #expect(first == "Print Center")
    }

    @Test(arguments: [
        (
            "VoiceMemos.app", ["en": ["CFBundleName": "Voice Memos"], "ru": ["CFBundleName": "Диктофон"]],
            ["Voice Memos", "Диктофон"]
        ),
        ("TrackpadExtension.appex", ["en": ["CFBundleDisplayName": "Trackpad"]], ["Trackpad"])
    ])
    func aTranslatedDevelopmentNameDisplacesTheFilename(
        _ filename: String, _ table: [String: [String: String]], _ expected: [String]
    ) throws {
        let scratch = try ScratchDirectory("translated-development")
        let url = try localizedBundle(filename, in: scratch, table: table)
        #expect(names(of: url, preferred: ["en-US", "ru-RU"]) == expected)
    }

    private var calculatorTable: [String: [String: String]] {
        ["no": ["CFBundleDisplayName": "Kalkulator"], "de": ["CFBundleDisplayName": "Rechner"]]
    }

    private func localizedBundle(
        _ filename: String, in scratch: ScratchDirectory, table: [String: [String: String]]
    ) throws -> URL {
        let url = scratch.url.appending(path: filename)
        try writePlist(table, to: url.appending(path: "Contents/Resources/InfoPlist.loctable"))
        return url
    }

    private func writeDisplayName(_ name: String, language: String, in app: URL) throws {
        let folder = app.appending(path: "Contents/Resources/\(language).lproj")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("\"CFBundleDisplayName\" = \"\(name)\";\n".utf8)
            .write(to: folder.appending(path: "InfoPlist.strings"))
    }

    private func writePlist(_ plist: Any, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
    }

    private func names(of url: URL, preferred: [String], region: String? = "en") -> [String] {
        BundleLocalization.names(
            for: url, base: url.deletingPathExtension().lastPathComponent,
            developmentRegion: region, languages: BundleLocalization.indexedLanguages(preferred))
    }
}
