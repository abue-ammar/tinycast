import Foundation
import NaturalLanguage
import Translation

/// `TranslationError` is macOS 26.4 against a 26.0 floor, so failures stay plain `Error` here.
enum TextTranslator {
    enum Failure: LocalizedError, Equatable {
        case undetectableSource
        case unsupported
        case notInstalled(language: String)
        case failed

        var errorDescription: String? {
            switch self {
            case .undetectableSource:
                return String(localized: "The language of the selected text could not be identified.")
            case .unsupported:
                return String(localized: "Apple's translator does not support this language pair.")
            case .notInstalled(let language):
                return String(localized: "\(language) needs to be downloaded before it can be used.")
            case .failed:
                return String(localized: "The text could not be translated.")
            }
        }
    }

    /// `TranslationSession(installedSource:)` needs a language; availability reports only a status.
    static func sourceLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
            return nil
        }
        return Locale.Language(identifier: dominant.rawValue)
    }

    /// Installed pairs only: a missing language is downloaded in System Settings, never from here.
    static func translate(_ text: String, to target: Locale.Language) async throws -> String {
        guard let source = sourceLanguage(of: text) else { throw Failure.undetectableSource }
        guard !source.isEquivalent(to: target) else { return text }
        let availability = LanguageAvailability()
        switch await availability.status(from: source, to: target) {
        case .installed:
            return try await translate(text, from: source, to: target)
        case .supported:
            break
        case .unsupported:
            throw Failure.unsupported
        @unknown default:
            throw Failure.unsupported
        }
        let supported = await availability.supportedLanguages
        let sources = variants(of: source, among: supported)
        let targets = variants(of: target, among: supported)
        if let pair = await installedPair(sources, targets, availability) {
            return try await translate(text, from: pair.source, to: pair.target)
        }
        // Every source spelling already failed, so only a third language can prove the target.
        let partners = supported.filter {
            $0.languageCode != source.languageCode && $0.languageCode != target.languageCode
        }
        let targetIsInstalled = await installedPair(partners, targets, availability) != nil
        throw Failure.notInstalled(language: displayName(of: targetIsInstalled ? source : target))
    }

    private static func translate(
        _ text: String, from source: Locale.Language, to target: Locale.Language
    ) async throws -> String {
        do {
            let session = TranslationSession(installedSource: source, target: target)
            return try await session.translate(text).targetText
        } catch {
            try Task.checkCancellation()
            throw Failure.failed
        }
    }

    /// A download is a locale, so the region a bare code resolves to can miss the one installed.
    private static func installedPair(
        _ sources: [Locale.Language], _ targets: [Locale.Language],
        _ availability: LanguageAvailability
    ) async -> (source: Locale.Language, target: Locale.Language)? {
        for source in sources {
            for target in targets {
                if await availability.status(from: source, to: target) == .installed {
                    return (source, target)
                }
            }
        }
        return nil
    }

    /// Region may move, since one English is another's asset, but a different script is a language.
    private static func variants(
        of language: Locale.Language, among supported: [Locale.Language]
    ) -> [Locale.Language] {
        [language]
            + supported.filter {
                $0.languageCode == language.languageCode && $0.script == language.script
                    && !$0.isEquivalent(to: language)
            }
    }

    /// Minimal, not maximal: the maximal form would spell `es` "Spanish (Latin, Spain)" in a menu.
    static func displayName(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }

    /// The framework's own list, so the picker cannot offer a pair that only fails at press time.
    static func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
            .sorted { displayName(of: $0) < displayName(of: $1) }
    }
}
