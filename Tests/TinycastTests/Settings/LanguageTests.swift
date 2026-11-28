import Foundation
import Testing

@testable import Tinycast

/// Pins how a stored `AppleLanguages` list reads back, and what each choice launches into.
struct LanguageTests {
    struct Reading: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let stored: [String]?
        var system: [String] = []
        let language: AppLanguage
    }

    struct ContextualLabel: CustomTestStringConvertible, Sendable {
        let key: String
        let source: String
        var overrides: [String: String] = [:]

        var testDescription: String { key }
    }

    static let readings = [
        Reading(testDescription: "nothing stored", stored: nil, language: .english),
        Reading(testDescription: "an empty list", stored: [], language: .english),
        Reading(testDescription: "a fresh installation", stored: nil, system: ["fr-FR"], language: .french),
        Reading(
            testDescription: "an unsupported system language", stored: nil, system: ["it-IT", "fr-FR"],
            language: .english),
        Reading(
            testDescription: "a stored choice over the system", stored: ["de"], system: ["fr-FR"],
            language: .german),
        Reading(testDescription: "an empty stored choice", stored: [], system: ["fr-FR"], language: .english),
        Reading(testDescription: "de-DE", stored: ["de-DE"], language: .german),
        Reading(testDescription: "pt-BR", stored: ["pt-BR"], language: .portuguese),
        Reading(testDescription: "pt-PT", stored: ["pt-PT"], language: .portuguese),
        Reading(testDescription: "zh-Hans-CN", stored: ["zh-Hans-CN"], language: .chineseSimplified),
        Reading(testDescription: "an unshipped language", stored: ["it"], language: .english)
    ]

    static let windows: [(AppLanguage, String, String)] = [
        (.english, "1 window", "2 windows"), (.german, "1 Fenster", "2 Fenster"),
        (.spanish, "1 ventana", "2 ventanas"), (.french, "1 fenêtre", "2 fenêtres"),
        (.japanese, "1個のウインドウ", "2個のウインドウ"), (.korean, "윈도우 1개", "윈도우 2개"),
        (.portuguese, "1 janela", "2 janelas"), (.russian, "1 окно", "2 окна"),
        (.chineseSimplified, "1 个窗口", "2 个窗口")
    ]

    static let rootSearchTerms: [(key: String, french: String)] = [
        ("Pop to Root Search", "Revenir à la recherche principale"),
        ("Pop to root", "Revenir à la recherche principale"),
        ("Close window and pop to root", "Fermer la fenêtre et revenir à la recherche principale"),
        ("Hidden from root search", "Masqué de la recherche principale"),
        ("Hide from Root Search", "Masquer de la recherche principale"),
        ("Show in root search", "Afficher dans la recherche principale")
    ]

    static let contextualLabels = [
        ContextualLabel(
            key: "applications-empty", source: "Nothing here yet.",
            overrides: ["fr": "Aucune application à afficher."]),
        ContextualLabel(
            key: "system-settings-empty", source: "Nothing here yet.",
            overrides: ["fr": "Aucun réglage système à afficher."]),
        ContextualLabel(
            key: "system-actions-empty", source: "Nothing here yet.",
            overrides: ["fr": "Aucune action système à afficher."]),
        ContextualLabel(
            key: "commands-empty", source: "Nothing here yet.",
            overrides: ["fr": "Aucune commande à afficher."]),
        ContextualLabel(
            key: "apple-shortcuts-empty", source: "Nothing here yet.",
            overrides: ["fr": "Aucun raccourci à afficher."]),
        ContextualLabel(
            key: "snippets-use-default-folder", source: "Use Default",
            overrides: ["fr": "Utiliser le dossier par défaut"]),
        ContextualLabel(
            key: "notes-use-default-folder", source: "Use Default",
            overrides: ["fr": "Utiliser le dossier par défaut"]),
        ContextualLabel(key: "dictation-model-installed", source: "Installed", overrides: ["fr": "Installé"]),
        ContextualLabel(
            key: "dictation-language-auto", source: "Auto", overrides: ["fr": "Détection automatique"]),
        ContextualLabel(
            key: "ai-installed-tools", source: "Installed", overrides: ["fr": "Outils installés"]),
        ContextualLabel(
            key: "extensions-installed-section", source: "Installed",
            overrides: ["fr": "Extensions installées"]),
        ContextualLabel(
            key: "extensions-install-section", source: "Install", overrides: ["fr": "Installation"]),
        ContextualLabel(key: "unit-category-time", source: "Time", overrides: ["fr": "Durée"]),
        ContextualLabel(key: "window-position-center", source: "Center", overrides: ["fr": "Centre"]),
        ContextualLabel(key: "ai-pinned-conversations", source: "Pinned", overrides: ["fr": "Épinglées"]),
        ContextualLabel(key: "ai-system-prompt-on", source: "On", overrides: ["fr": "Activées"]),
        ContextualLabel(key: "ai-system-prompt-off", source: "Off", overrides: ["fr": "Désactivées"]),
        ContextualLabel(key: "ai-web-search-on", source: "On", overrides: ["fr": "Activée"]),
        ContextualLabel(key: "ai-web-search-off", source: "Off", overrides: ["fr": "Désactivée"]),
        ContextualLabel(key: "reasoning-effort-low", source: "Low", overrides: ["es": "Bajo", "pt": "Baixo"]),
        ContextualLabel(
            key: "reasoning-effort-medium", source: "Medium",
            overrides: ["es": "Medio", "fr": "Moyen", "pt": "Médio"]),
        ContextualLabel(
            key: "reasoning-effort-high", source: "High",
            overrides: ["es": "Alto", "fr": "Élevé", "pt": "Alto"]),
        ContextualLabel(
            key: "emoji-skin-tone-light", source: "Light",
            overrides: ["fr": "Claire", "ja": "明るい", "ko": "밝은 피부색", "ru": "Светлый"]),
        ContextualLabel(
            key: "emoji-skin-tone-medium", source: "Medium",
            overrides: [
                "es": "Medio", "ja": "中間", "ko": "중간 피부색", "pt": "Médio", "ru": "Средний", "zh-Hans": "中等"
            ]),
        ContextualLabel(
            key: "emoji-skin-tone-dark", source: "Dark",
            overrides: ["fr": "Foncée", "ja": "濃い", "ko": "어두운 피부색", "ru": "Тёмный"])
    ]

    static let frenchLabels = [
        ("Medium", "Moyenne"), ("High", "Élevée"), ("Light", "Clair"), ("Dark", "Sombre"), ("Time", "Heure"),
        ("Center", "Centrer"), ("Pinned", "Épinglés"), ("On", "Activé"), ("Off", "Désactivé"),
        ("Untitled", "Sans titre")
    ]

    // MARK: Reading a stored list

    @Test(arguments: readings)
    func aStoredListReadsBackAsItsChoice(_ reading: Reading) {
        #expect(
            AppLanguage(storedPreferences: reading.stored, systemPreferences: reading.system)
                == reading.language)
    }

    @Test(arguments: AppLanguage.allCases)
    func aFreshInstallationSupportsEachLanguage(_ language: AppLanguage) {
        #expect(AppLanguage(storedPreferences: nil, systemPreferences: [language.rawValue]) == language)
    }

    @Test(arguments: AppLanguage.allCases)
    func eachLanguageRoundTrips(_ language: AppLanguage) {
        #expect(AppLanguage(storedPreferences: [language.rawValue]) == language)
    }

    @Test(arguments: AppLanguage.allCases)
    func eachChoiceLaunchesIntoItsOwnLocalization(_ language: AppLanguage) {
        let shipped = ["en", "de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"]
        #expect(
            Bundle.preferredLocalizations(from: shipped, forPreferences: [language.rawValue]).first
                == language.rawValue)
    }

    @Test func everyLanguageNamesItselfDistinctly() {
        #expect(Set(AppLanguage.allCases.map(\.title)).count == AppLanguage.allCases.count)
    }

    @Test func anUnknownRawValueIsRejected() {
        #expect(AppLanguage(rawValue: "klingon") == nil)
    }

    // MARK: The shipped catalogs

    @Test(arguments: windows)
    func pluralFormsAreSelectedAtRuntime(_ language: AppLanguage, _ one: String, _ two: String) throws {
        let bundle = try Self.strings(for: language)
        let locale = Locale(identifier: language.rawValue)
        let (single, pair) = (1, 2)
        #expect(String(localized: "\(single) windows", bundle: bundle, locale: locale) == one)
        #expect(String(localized: "\(pair) windows", bundle: bundle, locale: locale) == two)
    }

    @Test(arguments: AppLanguage.allCases)
    func mixedStringAndCountArgumentsSurviveTranslation(_ language: AppLanguage) throws {
        let bundle = try Self.strings(for: language)
        let size = "5 MB"
        let count = 2
        let text = String(
            localized: "Reclaims \(size) from \(count) items.", bundle: bundle,
            locale: Locale(identifier: language.rawValue))
        #expect(text.contains(size))
        #expect(text.contains("2"))
        #expect(!text.contains("%@"))
    }

    @Test(arguments: AppLanguage.allCases)
    func theCameraPrivacyPromptLoads(_ language: AppLanguage) throws {
        let prompt = try Self.strings(for: language)
            .localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist")
        #expect(prompt.contains("Tinycast"))
    }

    @Test(arguments: [AppLanguage.english, .french], rootSearchTerms)
    func rootSearchTerminologyIsPreserved(
        _ language: AppLanguage, _ term: (key: String, french: String)
    ) throws {
        let label = try Self.strings(for: language).localizedString(forKey: term.key, value: nil, table: nil)
        #expect(label == (language == .french ? term.french : term.key))
    }

    @Test(arguments: AppLanguage.allCases, contextualLabels)
    func aContextualKeyResolvesInItsContext(_ language: AppLanguage, _ label: ContextualLabel) throws {
        let bundle = try Self.strings(for: language)
        let expected =
            label.overrides[language.rawValue]
            ?? bundle.localizedString(forKey: label.source, value: nil, table: nil)
        #expect(bundle.localizedString(forKey: label.key, value: nil, table: nil) == expected)
    }

    @Test(arguments: frenchLabels)
    func aFrenchLabelResolvesInItsContext(_ key: String, _ french: String) throws {
        #expect(try Self.strings(for: .french).localizedString(forKey: key, value: nil, table: nil) == french)
    }

    @Test(arguments: [(0, "message envoyé"), (1, "message envoyé"), (2, "messages envoyés")])
    func theFrenchContextAnnouncementAgreesWithItsCount(_ count: Int, _ suffix: String) throws {
        let fill = "50 %"
        let announcement = String(
            localized: "Context \(fill), \(count) of \(count) messages sent",
            bundle: try Self.strings(for: .french),
            locale: Locale(identifier: "fr"))
        #expect(announcement.hasSuffix(suffix))
    }

    @Test(arguments: [
        (AppLanguage.english, "1 window · 2 displays", "2 windows · 1 display"),
        (.russian, "1 окно · 2 дисплея", "2 окна · 1 дисплей")
    ])
    func pluralSubstitutionsSelectEachArgumentIndependently(
        _ language: AppLanguage, _ secondPlural: String, _ secondSingular: String
    ) throws {
        let bundle = try Self.strings(for: language)
        let locale = Locale(identifier: language.rawValue)
        let (single, pair) = (1, 2)
        #expect(
            String(localized: "\(single) windows · \(pair) displays", bundle: bundle, locale: locale)
                == secondPlural)
        #expect(
            String(localized: "\(pair) windows · \(single) displays", bundle: bundle, locale: locale)
                == secondSingular)
    }

    @Test(arguments: [(5, "5 окон"), (21, "21 окно")])
    func russianSelectsManyAndOneByItsOwnRules(_ count: Int, _ expected: String) throws {
        let text = String(
            localized: "\(count) windows", bundle: try Self.strings(for: .russian),
            locale: Locale(identifier: "ru"))
        #expect(text == expected)
    }

    /// The app's own compiled tables for one language, which stand in for a launch into it.
    private static func strings(for language: AppLanguage) throws -> Bundle {
        let table = try #require(Bundle.main.url(forResource: language.rawValue, withExtension: "lproj"))
        return try #require(Bundle(url: table))
    }
}
