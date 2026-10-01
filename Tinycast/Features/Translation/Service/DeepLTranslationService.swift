import Foundation

final class DeepLTranslationService: Sendable {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        session = URLSession(
            configuration: configuration, delegate: RedirectDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    nonisolated func languages(plan: DeepLPlan, apiKey: String) async throws -> [TranslationLanguage] {
        try Task.checkCancellation()
        let url = plan.baseURL.appending(path: "v3/languages")
            .appending(queryItems: [URLQueryItem(name: "resource", value: "translate_text")])
        var request = request(url: url, apiKey: apiKey)
        request.httpMethod = "GET"
        return try DeepLTranslationAPI.languages(from: await data(for: request))
    }

    nonisolated func translate(
        _ input: TranslationRequest, plan: DeepLPlan, apiKey: String
    ) async throws -> TranslationResult {
        try Task.checkCancellation()
        if let source = input.sourceLanguage,
            TranslationLanguages.matches(source, input.targetLanguage)
        {
            return TranslationResult(text: input.text, detectedSourceLanguage: source)
        }
        var request = request(url: plan.baseURL.appending(path: "v2/translate"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try DeepLTranslationAPI.requestBody(for: input)
        return try DeepLTranslationAPI.result(from: await data(for: request))
    }

    private func request(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            try Task.checkCancellation()
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet: throw DeepLTranslationAPI.Failure.offline
            case .timedOut: throw DeepLTranslationAPI.Failure.timedOut
            default: throw DeepLTranslationAPI.Failure.network
            }
        } catch {
            try Task.checkCancellation()
            throw DeepLTranslationAPI.Failure.network
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw DeepLTranslationAPI.Failure.network
        }
        guard response.statusCode == 200 else {
            throw DeepLTranslationAPI.failure(for: response.statusCode)
        }
        return data
    }

    private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
