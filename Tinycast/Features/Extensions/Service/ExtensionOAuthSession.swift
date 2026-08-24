import AppKit
import Foundation

struct ExtensionOAuthAuthorizeOptions: Sendable {
    let url: URL
    let state: String?
}

struct ExtensionOAuthAuthorizeResult: Sendable {
    let authorizationCode: String
    let accessToken: String?
    let state: String?
}

/// Manages an OAuth 2.0 PKCE authorization session for extensions.
/// Opens authorization URLs in the default browser and captures `raycast://oauth` and `tinycast://oauth`
/// redirect callbacks to complete the authentication flow.
@MainActor
final class ExtensionOAuthSession: NSObject {
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var expectedState: String?

    // Active session registry for callback dispatch.
    private static weak var activeSession: ExtensionOAuthSession?

    enum OAuthError: LocalizedError {
        case invalidURL(String)
        case canceled
        case failed(String)
        case stateMismatch

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): return "Invalid authorization URL: \(url)"
            case .canceled: return "Authentication was canceled."
            case .failed(let message): return message
            case .stateMismatch: return "OAuth state mismatch. Please try authenticating again."
            }
        }
    }

    /// Handle deep links coming from NSApplicationDelegate (e.g. raycast://oauth?code=...)
    @discardableResult
    static func handleCallbackURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
            scheme == "raycast" || scheme == "tinycast"
        else { return false }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        guard host == "oauth" || host == "redirect" || path.contains("oauth") || path.contains("redirect") else {
            return false
        }

        guard let active = activeSession else { return false }
        active.receiveCallback(url: url)
        return true
    }

    func authorize(options: ExtensionOAuthAuthorizeOptions) async throws -> ExtensionOAuthAuthorizeResult {
        let params = try await authorize(url: options.url, expectedState: options.state)
        let code = params["code"] ?? ""
        let token = params["access_token"]
        let state = params["state"]
        return ExtensionOAuthAuthorizeResult(authorizationCode: code, accessToken: token, state: state)
    }

    func authorize(
        url: URL,
        expectedState: String? = nil,
        callbackScheme: String = "raycast"
    ) async throws -> [String: String] {
        if continuation != nil {
            cancel()
        }

        self.expectedState = expectedState
        Self.activeSession = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let opened = NSWorkspace.shared.open(url)
            if !opened {
                self.finish(error: OAuthError.failed("Failed to open authorization URL in default browser."))
            }
        }
    }

    private func receiveCallback(url: URL) {
        let params = Self.parseCallback(url: url)
        if let error = params["error"] {
            let desc = params["error_description"] ?? error
            finish(error: OAuthError.failed(desc))
            return
        }

        if let expected = expectedState, !expected.isEmpty,
            let received = params["state"], !received.isEmpty,
            received != expected
        {
            finish(error: OAuthError.stateMismatch)
            return
        }

        finish(result: params)
    }

    private func finish(result: [String: String]? = nil, error: Error? = nil) {
        Self.activeSession = nil

        if let continuation = self.continuation {
            self.continuation = nil
            if let error {
                continuation.resume(throwing: error)
            } else if let result {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: OAuthError.canceled)
            }
        }
    }

    func cancel() {
        finish(error: OAuthError.canceled)
    }

    // MARK: - URL Parsing

    static func parseCallback(url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        var result: [String: String] = [:]
        if let queryItems = components.queryItems {
            for item in queryItems {
                result[item.name] = item.value ?? ""
            }
        }
        // Handle fragment for implicit / hash callbacks: raycast://oauth#code=...
        if let fragment = components.fragment, !fragment.isEmpty {
            let pairs = fragment.split(separator: "&")
            for pair in pairs {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0])
                    let val = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                    result[key] = val
                }
            }
        }
        return result
    }
}
