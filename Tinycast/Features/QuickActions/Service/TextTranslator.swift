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
                return "The language of the selected text could not be identified."
            case .unsupported:
                return "Apple's translator does not support this language pair."
            case .notInstalled(let language):
                return "\(language) needs to be downloaded before it can be used."
            case .failed:
                return "The text could not be translated."
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

    /// Installed pairs only: fetching one needs SwiftUI's `translationTask`, which the panel owns.
    static func translate(_ text: String, to target: Locale.Language) async throws -> String {
        guard let source = sourceLanguage(of: text) else { throw Failure.undetectableSource }
        guard !source.isEquivalent(to: target) else { return text }
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw Failure.notInstalled(language: displayName(of: target))
        case .unsupported:
            throw Failure.unsupported
        @unknown default:
            throw Failure.unsupported
        }
        do {
            let session = TranslationSession(installedSource: source, target: target)
            return try await session.translate(text).targetText
        } catch {
            throw Failure.failed
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
