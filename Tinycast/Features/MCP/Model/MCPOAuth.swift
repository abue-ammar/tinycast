import Foundation

enum MCPOAuth {
    enum Failure: LocalizedError, Equatable {
        case invalidMetadata
        case unsupportedPKCE
        case clientRequired
        case issuerChanged
        case invalidCallback
        case denied
        case invalidToken
        case signInRequired
        case network
        case registration
        case listenerUnavailable
        case signInInProgress
        case timedOut

        var errorDescription: String? {
            switch self {
            case .invalidMetadata: return "The server's OAuth metadata is invalid."
            case .unsupportedPKCE: return "The authorization server must advertise PKCE S256 support."
            case .clientRequired: return "Enter a registered client ID. This server cannot register Tinycast automatically."
            case .issuerChanged: return "The authorization server changed. Enter client credentials for the new server."
            case .invalidCallback: return "The sign-in response could not be verified."
            case .denied: return "Sign-in was declined."
            case .invalidToken: return "The authorization server did not return a usable bearer token."
            case .signInRequired: return "Sign-in required. Open this MCP server in Settings to sign in."
            case .network: return "The OAuth request failed. Check the connection and try again."
            case .registration: return "Client registration failed. Enter a registered client ID and try again."
            case .listenerUnavailable: return "Sign-in could not open loopback port 4962. Close the app using it and retry."
            case .signInInProgress: return "Another sign-in is still waiting. Finish it first."
            case .timedOut: return "Sign-in timed out. Try again."
            }
        }
    }

    struct Credentials: Codable, Equatable, Sendable {
        var clientID: String = ""
        var clientSecret: String = ""
        var registration: Registration?
        var token: Token?
    }

    struct Registration: Codable, Equatable, Sendable {
        let resource: String
        let issuer: String
        let clientID: String
        let clientSecret: String?
        let tokenEndpoint: String
        let authMethod: String
        let redirectURI: String
    }

    struct Token: Codable, Equatable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let scope: String?

        func needsRefresh(now: Date) -> Bool {
            expiresAt.map { $0.timeIntervalSince(now) <= 60 } ?? false
        }
    }

    struct ResourceMetadata: Decodable, Sendable {
        let resource: String
        let authorization_servers: [String]
        let scopes_supported: [String]?
    }

    struct ServerMetadata: Decodable, Sendable {
        let issuer: String
        let authorization_endpoint: String
        let token_endpoint: String
        let registration_endpoint: String?
        let code_challenge_methods_supported: [String]?
        let token_endpoint_auth_methods_supported: [String]?
        let scopes_supported: [String]?
        let authorization_response_iss_parameter_supported: Bool?
    }

    static func endpoint(_ value: String) throws -> URL {
        let url = try AIEndpointPolicy.validate(value)
        guard url.user == nil, url.password == nil, url.fragment == nil else { throw Failure.invalidMetadata }
        return url
    }

    static func resource(_ value: String) throws -> String {
        let url = try endpoint(value)
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidMetadata
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if parts.path == "/" { parts.path = "" }
        guard let result = parts.string else { throw Failure.invalidMetadata }
        return result
    }

    static func protectedMetadataURLs(resource: String, challenge: [String: String]) throws -> [URL] {
        if let location = challenge["resource_metadata"] { return [try endpoint(location)] }
        return try wellKnown(resource, suffixes: ["oauth-protected-resource"], appendOIDC: false, rootFallback: true)
    }

    static func serverMetadataURLs(issuer: String) throws -> [URL] {
        let url = try endpoint(issuer)
        guard url.query == nil else { throw Failure.invalidMetadata }
        return try wellKnown(issuer, suffixes: ["oauth-authorization-server", "openid-configuration"], appendOIDC: true)
    }

    private static func wellKnown(
        _ value: String, suffixes: [String], appendOIDC: Bool, rootFallback: Bool = false
    ) throws -> [URL] {
        let url = try endpoint(value)
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidMetadata
        }
        let encoded = parts.percentEncodedPath
        let path = encoded.hasSuffix("/") ? String(encoded.dropLast()) : encoded
        parts.query = nil
        var results: [URL] = []
        for suffix in suffixes {
            parts.percentEncodedPath = "/.well-known/\(suffix)\(path)"
            if let url = parts.url { results.append(url) }
        }
        if !path.isEmpty {
            if appendOIDC {
                parts.percentEncodedPath = path + "/.well-known/openid-configuration"
            } else if rootFallback {
                parts.percentEncodedPath = "/.well-known/\(suffixes[0])"
            }
            if let url = parts.url, !results.contains(url) { results.append(url) }
        }
        return results
    }

    /// A redirect may carry credentials only here: scheme, host and effective port all unchanged.
    static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return first.scheme?.lowercased() == second.scheme?.lowercased()
            && first.host()?.lowercased() == second.host()?.lowercased() && port(first) == port(second)
    }

    static func resourceCovers(_ resource: String, endpoint: String) throws -> Bool {
        let parent = try Self.endpoint(resource)
        let child = try Self.endpoint(endpoint)
        guard sameOrigin(parent, child),
            parent.query == nil || parent.query == child.query else { return false }
        let parentPath = parent.path.hasSuffix("/") ? parent.path : parent.path + "/"
        let childPath = child.path.hasSuffix("/") ? child.path : child.path + "/"
        return childPath.hasPrefix(parentPath)
    }

    static func parseResource(_ data: Data, expected: String) throws -> ResourceMetadata {
        guard let metadata = try? JSONDecoder().decode(ResourceMetadata.self, from: data),
            try resourceCovers(metadata.resource, endpoint: expected), !metadata.authorization_servers.isEmpty
        else { throw Failure.invalidMetadata }
        for issuer in metadata.authorization_servers { _ = try endpoint(issuer) }
        return metadata
    }

    /// Google advertises `https://accounts.google.com/` and publishes it without the slash.
    static func sameIssuer(_ first: String, _ second: String) -> Bool {
        func bare(_ value: String) -> String { value.hasSuffix("/") ? String(value.dropLast()) : value }
        return bare(first) == bare(second)
    }

    static func parseServer(_ data: Data, issuer: String) throws -> ServerMetadata {
        guard let metadata = try? JSONDecoder().decode(ServerMetadata.self, from: data),
            sameIssuer(metadata.issuer, issuer)
        else { throw Failure.invalidMetadata }
        guard metadata.code_challenge_methods_supported?.contains("S256") == true else {
            throw Failure.unsupportedPKCE
        }
        _ = try endpoint(metadata.authorization_endpoint)
        _ = try endpoint(metadata.token_endpoint)
        if let registration = metadata.registration_endpoint { _ = try endpoint(registration) }
        return metadata
    }

    static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func pkce(entropy: Data, sha256: (Data) -> Data) -> (verifier: String, challenge: String) {
        let verifier = base64URL(entropy)
        return (verifier, base64URL(sha256(Data(verifier.utf8))))
    }

    static func form(_ fields: [String: String]) -> Data {
        Data(fields.sorted { $0.key < $1.key }.map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&").utf8)
    }

    static func escape(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func authorizeURL(
        metadata: ServerMetadata, registration: Registration, challenge: String, state: String, scope: String?
    ) throws -> URL {
        let endpoint = try endpoint(metadata.authorization_endpoint)
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidMetadata
        }
        var fields = ["response_type": "code", "client_id": registration.clientID,
                      "redirect_uri": registration.redirectURI, "code_challenge": challenge,
                      "code_challenge_method": "S256", "state": state, "resource": registration.resource]
        fields["scope"] = scope
        let reserved = Set(fields.keys).union(["scope"])
        parts.percentEncodedQueryItems = (parts.percentEncodedQueryItems ?? []).filter { !reserved.contains($0.name) }
            + fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: escape($0.key), value: escape($0.value)) }
        guard let url = parts.url else { throw Failure.invalidMetadata }
        return url
    }

    static func callback(_ target: String, state: String, issuer: String, requiresIssuer: Bool) throws -> String {
        guard target.hasPrefix("/callback?"),
            let parts = URLComponents(string: "http://127.0.0.1" + target), parts.path == "/callback",
            parts.fragment == nil else { throw Failure.invalidCallback }
        var fields: [String: String] = [:]
        for part in (parts.percentEncodedQuery ?? "").split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                let key = String(pair[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                let value = String(pair[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                fields[key] == nil else { throw Failure.invalidCallback }
            fields[key] = value
        }
        guard fields["state"] == state,
            fields["iss"].map({ $0 == issuer }) ?? !requiresIssuer else { throw Failure.invalidCallback }
        if fields["error"] != nil { throw Failure.denied }
        guard let code = fields["code"], !code.isEmpty else { throw Failure.invalidCallback }
        return code
    }

    /// RFC 6749 §5.2: only 400 and 401 reject the grant; anything else is a server fault.
    static func tokenFailure(status: Int) -> Failure {
        status == 400 || status == 401 ? .signInRequired : .network
    }

    static func parseToken(_ data: Data, previous: Token?, now: Date) throws -> Token {
        struct Response: Decodable {
            let access_token: String
            let token_type: String
            let refresh_token: String?
            let expires_in: Double?
            let scope: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
            response.token_type.lowercased() == "bearer", !response.access_token.isEmpty,
            response.access_token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
            response.expires_in.map({ $0.isFinite && $0 > 0 }) ?? true
        else { throw Failure.invalidToken }
        return Token(accessToken: response.access_token,
                     refreshToken: response.refresh_token ?? previous?.refreshToken,
                     expiresAt: response.expires_in.map { now.addingTimeInterval($0) },
                     scope: response.scope ?? previous?.scope)
    }
}
