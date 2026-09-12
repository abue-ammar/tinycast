import Foundation

final class AIModelDiscoveryService: Sendable {
    /// One session per process, not per editor sheet; cacheless so no response is cached on disk.
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    func models(
        provider: AIProviderKind, baseURL: URL, apiKey: String
    ) async throws -> [AIModelDiscovery.Model] {
        let query = try AIModelDiscovery.query(
            provider: provider, baseURL: baseURL, apiKey: apiKey,
            appTitle: Bundle.main.appDisplayName)
        let (data, response) = try await Self.session.data(for: query.request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw AIModelDiscovery.DiscoveryError.unavailable
        }
        switch response.statusCode {
        case 200:
            do {
                return try AIModelDiscovery.decode(data, shape: query.responseShape)
            } catch {
                throw AIModelDiscovery.DiscoveryError.malformedResponse
            }
        case 401, 403:
            throw AIModelDiscovery.DiscoveryError.rejectedKey
        case 404, 405, 501:
            throw AIModelDiscovery.DiscoveryError.unsupported
        default:
            throw AIModelDiscovery.DiscoveryError.unavailable
        }
    }
}
