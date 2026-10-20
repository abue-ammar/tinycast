import Foundation

final class AIEndpointRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let original = task.originalRequest?.url, let redirected = request.url,
            AIEndpointPolicy.permitsRedirect(from: original, to: redirected)
        else { return nil }
        return request
    }
}
