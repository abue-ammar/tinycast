import Foundation

enum TranslationLanguages {
    private static let aiCodes = [
        "en", "en-US", "en-GB", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "it",
        "pt-BR", "pt-PT", "ru", "ar", "hi", "nl", "pl", "tr", "uk", "vi", "th", "id", "sv",
        "da", "fi", "nb", "cs", "el", "he", "ro", "hu"
    ]

    static func normalized(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    static func matches(_ first: String, _ second: String) -> Bool {
        normalized(first) == normalized(second)
    }

    static func ai(locale: Locale) -> [TranslationLanguage] {
        sorted(aiCodes.map {
            TranslationLanguage(
                id: $0, name: locale.localizedString(forIdentifier: $0) ?? $0,
                usableAsSource: true, usableAsTarget: true)
        }, locale: locale)
    }

    static func localized(
        _ languages: [TranslationLanguage], locale: Locale
    ) -> [TranslationLanguage] {
        sorted(languages.map {
            TranslationLanguage(
                id: $0.id, name: locale.localizedString(forIdentifier: $0.id) ?? $0.name,
                usableAsSource: $0.usableAsSource, usableAsTarget: $0.usableAsTarget)
        }, locale: locale)
    }

    static func supports(_ request: TranslationRequest, in languages: [TranslationLanguage]) -> Bool {
        guard languages.contains(where: {
            $0.usableAsTarget && matches($0.id, request.targetLanguage)
        }) else { return false }
        guard let source = request.sourceLanguage else { return true }
        return languages.contains { $0.usableAsSource && matches($0.id, source) }
    }

    static func swapped(
        source: String?, target: String, detectedSource: String?,
        in languages: [TranslationLanguage]
    ) -> (source: String, target: String)? {
        guard let oldSource = source ?? detectedSource else { return nil }
        let sources = languages.filter(\.usableAsSource)
        let targets = languages.filter(\.usableAsTarget)
        let baseTarget = String(normalized(target).prefix { $0 != "-" })
        guard let newSource = sources.first(where: { matches($0.id, target) })
            ?? sources.first(where: { matches($0.id, baseTarget) })
        else { return nil }
        let targetAliases = ["en": "en-US", "pt": "pt-PT", "zh": "zh-Hans", "no": "nb", "nb": "no"]
        let newTarget = targets.first { matches($0.id, oldSource) }
            ?? targetAliases[normalized(oldSource)].flatMap { alias in
                targets.first { matches($0.id, alias) }
            }
        guard let newTarget else { return nil }
        return (newSource.id, newTarget.id)
    }

    private static func sorted(
        _ languages: [TranslationLanguage], locale: Locale
    ) -> [TranslationLanguage] {
        languages.sorted {
            let order = $0.name.compare($1.name, options: [.caseInsensitive], locale: locale)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
