import Foundation
import Testing

@testable import Tinycast

struct LocalizedResourceTests {
    static let languages = ["en", "de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"]

    /// Built per language, since a resource's bundle and locale are fixed when it is made.
    struct Resource: CustomTestStringConvertible, Sendable {
        let testDescription: String
        var key: StaticString?
        let value: String.LocalizationValue

        func resource(in table: URL, language: String) -> LocalizedStringResource {
            let locale = Locale(identifier: language)
            guard let key else {
                return LocalizedStringResource(value, locale: locale, bundle: .atURL(table))
            }
            return LocalizedStringResource(key, defaultValue: value, locale: locale, bundle: .atURL(table))
        }
    }

    static let resources: [Resource] = {
        let name = "Notes"
        return [
            Resource(testDescription: "a translated key", value: "Cancel"),
            Resource(testDescription: "a key the catalog lacks", value: "Tinycast missing key"),
            Resource(testDescription: "a contextual key", key: "apple-shortcuts-section", value: "Shortcuts"),
            Resource(
                testDescription: "a contextual key the catalog lacks", key: "tinycast-missing-key",
                value: "Cancel"),
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
        let value = resource.resource(in: table, language: language)
        #expect(value.resolved() == String(localized: value))
    }
}
