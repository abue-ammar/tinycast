import Foundation
import Testing

@testable import Tinycast

struct LocalizedResourceTests {
    static let languages = ["en", "de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"]

    struct Resource: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let value: LocalizedStringResource
    }

    static let resources: [Resource] = {
        let name = "Notes"
        return [
            Resource(testDescription: "a translated key", value: "Cancel"),
            Resource(testDescription: "a key the catalog lacks", value: "Tinycast missing key"),
            Resource(
                testDescription: "a contextual key",
                value: LocalizedStringResource("apple-shortcuts-section", defaultValue: "Shortcuts")),
            Resource(
                testDescription: "a contextual key the catalog lacks",
                value: LocalizedStringResource("tinycast-missing-key", defaultValue: "Cancel")),
            Resource(testDescription: "an interpolated key", value: "Customize \(name)"),
            Resource(testDescription: "a literal percent sign", value: "Set Volume to 25%")
        ] + [1, 2, 5].map { Resource(testDescription: "a plural of \($0)", value: "\($0) hidden items") }
    }()

    @Test(arguments: languages)
    func theAppBundleLocalizesEachLanguage(_ language: String) {
        #expect(Bundle.main.localizations.contains(language))
        #expect(Bundle.main.url(forResource: language, withExtension: "lproj") != nil)
    }

    /// Each language's own table stands in for a process running in that language.
    @Test(arguments: languages, resources)
    func resolvingMatchesStringLocalized(_ language: String, _ resource: Resource) throws {
        let table = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
        let bundle = try #require(Bundle(url: table))
        var value = resource.value
        value.locale = Locale(identifier: language)
        #expect(value.resolved(in: bundle) == String(localized: value))
    }
}
