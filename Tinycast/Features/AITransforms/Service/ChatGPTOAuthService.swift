import AppKit
import CryptoKit
import Foundation
import Network

/// Manages OAuth 2.0 PKCE authentication for ChatGPT Plus / Pro / Team subscriptions.
@MainActor
@Observable
final class ChatGPTOAuthService {
    static let shared = ChatGPTOAuthService()

    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authorizeURL = "https://auth.openai.com/oauth/authorize"
    static let tokenURL = "https://auth.openai.com/oauth/token"
    static let redirectURI = "http://localhost:1455/auth/callback"
    static let scopes = "openid profile email offline_access"
    static let defaultBaseURL = "https://chatgpt.com/backend-api/codex"

    enum AuthState: Equatable {
        case unauthenticated
        case authenticating
        case authenticated(email: String?)
        case failed(String)
    }

    private(set) var state: AuthState = .unauthenticated

    private static let accessTokenKey = "ai.oauth.chatgpt.access-token"
    private static let refreshTokenKey = "ai.oauth.chatgpt.refresh-token"
    private static let expiresAtKey = "ai.oauth.chatgpt.expires-at"
    private static let emailKey = "ai.oauth.chatgpt.email"
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var codeVerifier: String?
    @ObservationIgnored private var authStateCode: String?
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    init() {
        if hasValidTokens() {
            let email = SecretStore.secret(account: Self.emailKey)
            state = .authenticated(email: email)
        }
    }

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    func startAuthFlow() {
        cancel()
        state = .authenticating

        let verifier = Self.generateRandomString(length: 64)
        let challenge = Self.sha256Base64URL(verifier)
        let stateCode = Self.generateRandomString(length: 32)
        self.codeVerifier = verifier
        self.authStateCode = stateCode

        do {
            try startLoopbackListener()
        } catch {
            state = .failed("Could not start local auth listener on port 1455: \(error.localizedDescription)")
            return
        }

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: stateCode),
            URLQueryItem(name: "id_token_add_organizations", value: "true")
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        } else {
            state = .failed("Could not construct authorization URL.")
        }
    }

    func signOut() {
        cancel()
        SecretStore.setSecret(nil, account: Self.accessTokenKey)
        SecretStore.setSecret(nil, account: Self.refreshTokenKey)
        SecretStore.setSecret(nil, account: Self.expiresAtKey)
        SecretStore.setSecret(nil, account: Self.emailKey)
        state = .unauthenticated
    }

    func validAccessToken() async throws -> String {
        if let token = getUnexpiredAccessToken() {
            return token
        }
        return try await refreshTokens()
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        listener?.cancel()
        listener = nil
        codeVerifier = nil
        authStateCode = nil
        if case .authenticating = state {
            state = .unauthenticated
        }
    }

    // MARK: - Loopback Listener

    private func startLoopbackListener() throws {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: 1455)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            Task { @MainActor [weak self] in
                self?.handleConnection(connection)
            }
        }

        listener.start(queue: .main)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, let data, let requestString = String(data: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }

                let responseHTML: String
                if let (code, state) = self.extractAuthCode(from: requestString), state == self.authStateCode
                {
                    responseHTML = """
                        <html>
                        <head><title>Tinycast Authentication</title></head>
                        <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 40px;">
                            <h2>✓ Signed in to ChatGPT</h2>
                            <p style="color: #666;">You can close this window and return to Tinycast.</p>
                        </body>
                        </html>
                        """
                    self.sendHTTPResponse(connection: connection, html: responseHTML)
                    self.exchangeCodeForTokens(code: code)
                } else {
                    responseHTML = "<html><body><h2>Authentication failed or cancelled</h2></body></html>"
                    self.sendHTTPResponse(connection: connection, html: responseHTML)
                    self.state = .failed("Authorization code was invalid or missing.")
                }
            }
        }
    }

    private func sendHTTPResponse(connection: NWConnection, html: String) {
        let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=UTF-8\r
            Content-Length: \(html.utf8.count)\r
            Connection: close\r
            \r
            \(html)
            """
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }

    private func extractAuthCode(from request: String) -> (code: String, state: String)? {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
            let urlPart = firstLine.components(separatedBy: " ").dropFirst().first,
            let components = URLComponents(string: "http://localhost:1455" + urlPart),
            let queryItems = components.queryItems
        else { return nil }

        let code = queryItems.first(where: { $0.name == "code" })?.value
        let state = queryItems.first(where: { $0.name == "state" })?.value
        guard let code, let state else { return nil }
        return (code, state)
    }

    // MARK: - Token Exchange & Refresh

    private func exchangeCodeForTokens(code: String) {
        guard let verifier = codeVerifier else {
            state = .failed("Missing code verifier.")
            return
        }
        listener?.cancel()
        listener = nil

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier
        ]

        request.httpBody = params.map { "\($0.key)=\(Self.urlEncode($0.value))" }.joined(separator: "&").data(
            using: .utf8)

        activeTask = Task { [weak self] in
            do {
                let (data, response) = try await Self.session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "HTTP error"
                    self?.state = .failed("Token exchange failed: \(message)")
                    return
                }
                guard let tokenObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let access = tokenObj["access_token"] as? String
                else {
                    self?.state = .failed("Token response did not contain access_token.")
                    return
                }
                self?.persistTokenResponse(tokenObj, access: access)
            } catch {
                self?.state = .failed("Token exchange failed: \(error.localizedDescription)")
            }
        }
    }

    private func refreshTokens() async throws -> String {
        guard let refresh = SecretStore.secret(account: Self.refreshTokenKey), !refresh.isEmpty else {
            throw AIClientError.unauthorized
        }

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refresh
        ]
        request.httpBody = params.map { "\($0.key)=\(Self.urlEncode($0.value))" }.joined(separator: "&").data(
            using: .utf8)

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let tokenObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let newAccess = tokenObj["access_token"] as? String
        else {
            throw AIClientError.unauthorized
        }

        return persistTokenResponse(tokenObj, access: newAccess)
    }
    @discardableResult
    private func persistTokenResponse(_ tokenObj: [String: Any], access: String) -> String {
        let refresh = tokenObj["refresh_token"] as? String
        let expiresIn = (tokenObj["expires_in"] as? Double) ?? 3600
        let expiresAt = Date().addingTimeInterval(expiresIn).timeIntervalSince1970
        let email = extractEmail(fromIDToken: tokenObj["id_token"] as? String)

        SecretStore.setSecret(access, account: Self.accessTokenKey)
        if let refresh { SecretStore.setSecret(refresh, account: Self.refreshTokenKey) }
        SecretStore.setSecret(String(expiresAt), account: Self.expiresAtKey)
        if let email { SecretStore.setSecret(email, account: Self.emailKey) }

        state = .authenticated(email: email ?? SecretStore.secret(account: Self.emailKey))
        return access
    }

    private func hasValidTokens() -> Bool {
        SecretStore.secret(account: Self.accessTokenKey)?.isEmpty == false
            || SecretStore.secret(account: Self.refreshTokenKey)?.isEmpty == false
    }

    private func getUnexpiredAccessToken() -> String? {
        guard let token = SecretStore.secret(account: Self.accessTokenKey), !token.isEmpty,
            let expiresString = SecretStore.secret(account: Self.expiresAtKey),
            let expiresAt = Double(expiresString)
        else { return nil }

        // Proactive 5-minute skew before expiry
        if Date().timeIntervalSince1970 < (expiresAt - 300) {
            return token
        }
        return nil
    }

    private func extractEmail(fromIDToken idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2,
            let payloadData = Self.base64URLDecode(parts[1]),
            let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }

    // MARK: - Utilities

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateRandomString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(base64URLEncode(Data(bytes)).prefix(length))
    }

    private static func sha256Base64URL(_ input: String) -> String {
        base64URLEncode(Data(SHA256.hash(data: Data(input.utf8))))
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 =
            string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }

    private static func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
