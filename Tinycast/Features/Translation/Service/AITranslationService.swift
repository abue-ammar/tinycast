import Foundation

enum AITranslationService {
    static func translate(
        _ request: TranslationRequest, using provider: any AIProvider
    ) async throws -> TranslationResult {
        try Task.checkCancellation()
        if let source = request.sourceLanguage,
            TranslationLanguages.matches(source, request.targetLanguage)
        {
            return TranslationResult(text: request.text, detectedSourceLanguage: source)
        }

        let aiRequest = AIRequest(
            instructions: TranslationPrompt.instructions(
                source: request.sourceLanguage, target: request.targetLanguage),
            messages: [AIMessage(role: .user, text: request.text)],
            webSearch: false, tools: [])
        var text = ""
        for try await event in provider.stream(aiRequest) {
            try Task.checkCancellation()
            guard case .text(let delta) = event else { continue }
            text += delta
        }
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.responseFailed("The model returned no translation.")
        }
        let source = request.sourceLanguage
            ?? TextTranslator.sourceLanguage(of: request.text)?.minimalIdentifier
        try Task.checkCancellation()
        return TranslationResult(text: text, detectedSourceLanguage: source)
    }
}
