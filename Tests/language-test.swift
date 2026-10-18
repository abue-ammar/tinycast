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
        let contextualLabels: [(key: String, source: String, overrides: [String: String])] = [
            ("applications-empty", "Nothing here yet.", ["fr": "Aucune application à afficher."]),
            ("system-settings-empty", "Nothing here yet.", ["fr": "Aucun réglage système à afficher."]),
            ("system-actions-empty", "Nothing here yet.", ["fr": "Aucune action système à afficher."]),
            ("commands-empty", "Nothing here yet.", ["fr": "Aucune commande à afficher."]),
            ("apple-shortcuts-empty", "Nothing here yet.", ["fr": "Aucun raccourci à afficher."]),
            ("snippets-use-default-folder", "Use Default", ["fr": "Utiliser le dossier par défaut"]),
            ("notes-use-default-folder", "Use Default", ["fr": "Utiliser le dossier par défaut"]),
            ("dictation-model-installed", "Installed", ["fr": "Installé"]),
            ("dictation-language-auto", "Auto", ["fr": "Détection automatique"]),
            ("ai-installed-tools", "Installed", ["fr": "Outils installés"]),
            ("extensions-installed-section", "Installed", ["fr": "Extensions installées"]),
            ("extensions-install-section", "Install", ["fr": "Installation"]),
            ("unit-category-time", "Time", ["fr": "Durée"]),
            ("window-position-center", "Center", ["fr": "Centre"]),
            ("onboarding-open-launcher", "App Launcher", ["fr": "Ouvrir le lanceur"]),
            ("ai-pinned-conversations", "Pinned", ["fr": "Épinglées"]),
            ("ai-system-prompt-on", "On", ["fr": "Activées"]),
            ("ai-system-prompt-off", "Off", ["fr": "Désactivées"]),
            ("ai-web-search-on", "On", ["fr": "Activée"]),
            ("ai-web-search-off", "Off", ["fr": "Désactivée"]),
            ("reasoning-effort-low", "Low", ["es": "Bajo", "pt": "Baixo"]),
            ("reasoning-effort-medium", "Medium", ["es": "Medio", "fr": "Moyen", "pt": "Médio"]),
            ("reasoning-effort-high", "High", ["es": "Alto", "fr": "Élevé", "pt": "Alto"]),
            (
                "emoji-skin-tone-light", "Light",
                [
                    "fr": "Claire", "ja": "明るい", "ko": "밝은 피부색", "ru": "Светлый"
                ]
            ),
            (
                "emoji-skin-tone-medium", "Medium",
                [
                    "es": "Medio", "ja": "中間", "ko": "중간 피부색", "pt": "Médio", "ru": "Средний",
                    "zh-Hans": "中等"
                ]
            ),
            (
                "emoji-skin-tone-dark", "Dark",
                [
                    "fr": "Foncée", "ja": "濃い", "ko": "어두운 피부색", "ru": "Тёмный"
                ]
            )
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

            if code == "en" || code == "fr" {
                for (key, french) in [
                    "Pop to Root Search": "Revenir à la recherche principale",
                    "Pop to root": "Revenir à la recherche principale",
                    "Close window and pop to root": "Fermer la fenêtre et revenir à la recherche principale",
                    "Hidden from root search": "Masqué de la recherche principale",
                    "Hide from Root Search": "Masquer de la recherche principale",
                    "Show in root search": "Afficher dans la recherche principale"
                ] {
                    check(
                        "\(code) root-search terminology is preserved for \(key)",
                        bundle.localizedString(forKey: key, value: nil, table: nil)
                            == (code == "fr" ? french : key))
                }
            }

            for label in contextualLabels {
                let expected =
                    label.overrides[code]
                    ?? bundle.localizedString(forKey: label.source, value: nil, table: nil)
                check(
                    "\(code) contextual label \(label.key)",
                    bundle.localizedString(forKey: label.key, value: nil, table: nil) == expected)
            }
            if code == "fr" {
                for (key, expected) in [
                    "Medium": "Moyenne", "High": "Élevée", "Light": "Clair", "Dark": "Sombre",
                    "Time": "Heure", "Center": "Centrer", "Pinned": "Épinglés",
                    "On": "Activé", "Off": "Désactivé", "Untitled": "Sans titre"
                ] {
                    check(
                        "French label \(key) resolves in its context",
                        bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
                }
                let fill = "50 %"
                for count in [0, 1, 2] {
                    let announcement = String(
                        localized: "Context \(fill), \(count) of \(count) messages sent",
                        bundle: bundle, locale: locale)
                    let suffix = count > 1 ? "messages envoyés" : "message envoyé"
                    check("French context announcement agrees for \(count)", announcement.hasSuffix(suffix))
                }
            }

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
