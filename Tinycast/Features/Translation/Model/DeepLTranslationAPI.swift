import Foundation

enum DeepLTranslationAPI {
    enum Failure: LocalizedError, Equatable, Sendable {
        case tooLong
        case invalidTranslation
        case invalidLanguages
        case invalidKey
        case rateLimited
        case quotaExceeded
        case unavailable
        case rejected(Int)
        case offline
        case timedOut
        case network

        var errorDescription: String? {
            switch self {
            case .tooLong:
                "Text is too long for DeepL."
            case .invalidTranslation:
                "DeepL returned an invalid translation."
            case .invalidLanguages:
                "DeepL returned an invalid language list."
            case .invalidKey:
                "DeepL rejected the API key. Check the key and Free/Pro account type."
            case .rateLimited:
                "DeepL rate limit reached. Try again later."
            case .quotaExceeded:
                "DeepL character quota exceeded."
            case .unavailable:
                "DeepL is temporarily unavailable."
            case .rejected(let statusCode):
                "DeepL rejected the request (HTTP \(statusCode))."
            case .offline:
                "No internet connection."
            case .timedOut:
                "DeepL took too long to respond."
            case .network:
                "The network request to DeepL failed."
            }
        }
    }

    private static let maximumRequestBodyBytes = 131_072

    static func requestBody(for request: TranslationRequest) throws -> Data {
        var body: [String: Any] = [
            "text": [request.text],
            "target_lang": request.targetLanguage,
            "preserve_formatting": true
        ]
        if let source = request.sourceLanguage { body["source_lang"] = source }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard data.count <= maximumRequestBodyBytes else { throw Failure.tooLong }
        return data
    }

    static func result(from data: Data) throws -> TranslationResult {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Failure.invalidTranslation
        }
        guard response.translations.count == 1, let translation = response.translations.first,
            !translation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !translation.detectedSourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw Failure.invalidTranslation }
        return TranslationResult(
            text: translation.text, detectedSourceLanguage: translation.detectedSourceLanguage)
    }

    static func languages(from data: Data) throws -> [TranslationLanguage] {
        let entries: [Language]
        do {
            entries = try JSONDecoder().decode([Language].self, from: data)
        } catch {
            throw Failure.invalidLanguages
        }
        guard entries.contains(where: \.usableAsSource), entries.contains(where: \.usableAsTarget)
        else { throw Failure.invalidLanguages }
        var identifiers = Set<String>()
        return try entries.map { entry in
            guard !entry.lang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                identifiers.insert(TranslationLanguages.normalized(entry.lang)).inserted
            else { throw Failure.invalidLanguages }
            return TranslationLanguage(
                id: entry.lang, name: entry.name, usableAsSource: entry.usableAsSource,
                usableAsTarget: entry.usableAsTarget)
        }
    }

    static func failure(for statusCode: Int) -> Failure {
        switch statusCode {
        case 401, 403: .invalidKey
        case 413: .tooLong
        case 429: .rateLimited
        case 456: .quotaExceeded
        case 500...599: .unavailable
        default: .rejected(statusCode)
        }
    }

    private struct Response: Decodable {
        let translations: [Translation]
    }

    private struct Translation: Decodable {
        let text: String
        let detectedSourceLanguage: String

        enum CodingKeys: String, CodingKey {
            case text
            case detectedSourceLanguage = "detected_source_language"
        }
    }

    private struct Language: Decodable {
        let lang: String
        let name: String
        let usableAsSource: Bool
        let usableAsTarget: Bool

        enum CodingKeys: String, CodingKey {
            case lang, name
            case usableAsSource = "usable_as_source"
            case usableAsTarget = "usable_as_target"
        }
    }
}
