import Foundation

enum AppLocalization {
    static var locale: Locale {
        locale(preferences: UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? ["en"])
    }

    static func locale(preferences: [String]) -> Locale {
        let language =
            Bundle.preferredLocalizations(
                from: ["en", "zh-Hans"], forPreferences: preferences
            ).first ?? "en"
        return Locale(identifier: language)
    }

    static func bundle(for locale: Locale, in bundle: Bundle = .main) -> Bundle {
        guard let path = bundle.path(forResource: locale.identifier, ofType: "lproj"),
            let localized = Bundle(path: path)
        else { return bundle }
        return localized
    }
}

extension Bundle {
    static var appLanguage: Bundle {
        AppLocalization.bundle(for: AppLocalization.locale)
    }
}
