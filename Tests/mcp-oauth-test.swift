import CryptoKit
import Foundation

@main
@MainActor
struct MCPOAuthTests {
    static var passes = 0
    static var failures = 0
    static let base = "http://127.0.0.1:4963"

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        if (try? condition()) == true { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func rejects(_ message: String, _ operation: () throws -> Void) {
        do {
            try operation()
            expect(false, message)
        } catch {
            expect(true, message)
        }
    }

    static func main() async {
        do {
            try pureRules()
            try await listenerLifecycle()
            try await networkFlow()
        } catch { expect(false, "unexpected failure: \(error)") }
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func pureRules() throws {
        let entropy =
            Data(
                base64Encoded: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk="
                    .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))
            ?? Data()
        let pkce = MCPOAuth.pkce(entropy: entropy) { Data(SHA256.hash(data: $0)) }
        expect(pkce.verifier == "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", "RFC 7636 verifier")
        expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 S256 vector")
        expect(try MCPOAuth.resource("https://example.com/") == "https://example.com", "canonical root")
        for value in [
            "http://example.com/mcp", "file:///secret", "https://user:pass@example.com/mcp",
            "https://example.com/#x"
        ] {
            rejects("reject unsafe endpoint") { _ = try MCPOAuth.endpoint(value) }
        }
        let header =
            "Basic realm=\"other\", Bearer resource_metadata=\"https://example.com/meta?a=1,b=2\", scope=\"read write\""
        let challenge = MCPOAuthChallenge.parse(header)
        expect(challenge["resource_metadata"] == "https://example.com/meta?a=1,b=2", "quoted comma survives")
        expect(challenge["scope"] == "read write", "bearer scopes")
        expect(
            MCPOAuthChallenge.parse("Bearer scope=\"a\", scope=\"b\"").isEmpty, "duplicate challenge refused")
        expect(MCPOAuthChallenge.parse("Bearer scope=\"unterminated").isEmpty, "bad quotes refused")
        let urls = try MCPOAuth.protectedMetadataURLs(
            resource: "https://example.com/team/mcp", challenge: [:])
        expect(
            urls.map(\.absoluteString) == [
                "https://example.com/.well-known/oauth-protected-resource/team/mcp",
                "https://example.com/.well-known/oauth-protected-resource"
            ], "path before root discovery")
        let issuers = try MCPOAuth.serverMetadataURLs(issuer: "https://example.com/tenant")
        expect(
            issuers.map(\.absoluteString) == [
                "https://example.com/.well-known/oauth-authorization-server/tenant",
                "https://example.com/.well-known/openid-configuration/tenant",
                "https://example.com/tenant/.well-known/openid-configuration"
            ], "all issuer discovery locations")
        expect(
            try MCPOAuth.serverMetadataURLs(issuer: "https://example.com/tenant/") == issuers,
            "an issuer's terminating slash is dropped before the well-known path goes in")
        expect(
            try MCPOAuth.protectedMetadataURLs(resource: "https://example.com/team/mcp/", challenge: [:])
                == urls,
            "a resource's terminating slash is dropped the same way")
        let metadataJSON =
            #"{"issuer":"https://auth.test","authorization_endpoint":"https://auth.test/authorize","#
            + #""token_endpoint":"https://auth.test/token","code_challenge_methods_supported":["S256"]}"#
        let metadata = try MCPOAuth.parseServer(Data(metadataJSON.utf8), issuer: "https://auth.test")
        let origin = URL(string: "https://example.com/mcp")!
        expect(
            MCPOAuth.sameOrigin(origin, URL(string: "HTTPS://Example.com:443/mcp/")!),
            "case and the default port do not change an origin")
        for other in [
            "https://example.com:8443/mcp", "https://evil.example.com/mcp", "http://example.com/mcp"
        ] {
            expect(!MCPOAuth.sameOrigin(origin, URL(string: other)!), "\(other) is another origin")
        }
        expect(
            [400, 401].allSatisfy { MCPOAuth.tokenFailure(status: $0) == .signInRequired },
            "a rejected grant requires sign-in")
        expect(
            [403, 429, 500, 503].allSatisfy { MCPOAuth.tokenFailure(status: $0) == .network },
            "a server fault is not a rejected grant")
        let slashed = try MCPOAuth.parseServer(Data(metadataJSON.utf8), issuer: "https://auth.test/")
        expect(
            slashed.issuer == "https://auth.test",
            "a trailing slash is the same issuer, and the server's own spelling is kept")
        rejects("another issuer is refused") {
            _ = try MCPOAuth.parseServer(Data(metadataJSON.utf8), issuer: "https://auth.test/tenant")
        }
        rejects("S256 required") {
            _ = try MCPOAuth.parseServer(
                Data(metadataJSON.replacingOccurrences(of: "S256", with: "plain").utf8),
                issuer: "https://auth.test")
        }
        rejects("resource must match requested server") {
            _ = try MCPOAuth.parseResource(
                Data(
                    #"{"resource":"https://other.test","authorization_servers":["https://auth.test"]}"#.utf8),
                expected: "https://example.com")
        }
        expect(
            try MCPOAuth.resourceCovers("https://example.com", endpoint: "https://example.com/mcp"),
            "root resource can describe its MCP endpoint")
        expect(
            try !MCPOAuth.resourceCovers(
                "https://example.com/team", endpoint: "https://example.com/teammate"),
            "path prefix cannot cross a tenant boundary")
        expect(
            try !MCPOAuth.resourceCovers("https://example.com/team", endpoint: "https://other.com/team"),
            "resource cannot describe another origin")
        let registration = MCPOAuth.Registration(
            resource: "https://example.com/mcp", issuer: "https://auth.test",
            clientID: "test+client", clientSecret: nil, tokenEndpoint: "https://auth.test/token",
            authMethod: "none",
            redirectURI: MCPOAuthListener.redirectURI)
        let url = try MCPOAuth.authorizeURL(
            metadata: metadata, registration: registration, challenge: pkce.challenge,
            state: "state", scope: "read write")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        expect(
            query.contains(URLQueryItem(name: "resource", value: registration.resource)), "authorize resource"
        )
        expect(query.contains(URLQueryItem(name: "code_challenge_method", value: "S256")), "authorize S256")
        expect(
            query.contains(URLQueryItem(name: "client_id", value: "test+client"))
                && url.absoluteString.contains("client_id=test%2Bclient")
                && url.absoluteString.contains("scope=read%20write"),
            "a plus in the authorization URL is escaped, so the server cannot read it as a space")
        let tenantJSON = metadataJSON.replacingOccurrences(
            of: "auth.test/authorize", with: "auth.test/authorize?tenant=a%2Bb&client_id=spoofed")
        let tenant = try MCPOAuth.authorizeURL(
            metadata: MCPOAuth.parseServer(Data(tenantJSON.utf8), issuer: "https://auth.test"),
            registration: registration, challenge: pkce.challenge, state: "state", scope: nil)
        expect(
            tenant.absoluteString.contains("?tenant=a%2Bb&client_id=test%2Bclient&"),
            "the endpoint's own query keeps its encoding and loses the fields it may not set")
        expect(
            String(bytes: MCPOAuth.form(["a+b": "&= +"]), encoding: .utf8) == "a%2Bb=%26%3D%20%2B",
            "form encoding")
        let good = "/callback?code=hello%2Bworld&state=state&iss=https%3A%2F%2Fauth.test"
        expect(
            try MCPOAuth.callback(good, state: "state", issuer: "https://auth.test", requiresIssuer: true)
                == "hello+world",
            "callback decodes code")
        for bad in [
            good + "&state=state", good.replacingOccurrences(of: "state=state", with: "state=wrong"),
            good.replacingOccurrences(of: "auth.test", with: "attacker.test"), "/callback?code=c&state=state",
            "/other?code=c&state=state"
        ] {
            rejects("invalid callback refused") {
                _ = try MCPOAuth.callback(
                    bad, state: "state", issuer: "https://auth.test", requiresIssuer: true)
            }
        }
        let now = Date(timeIntervalSince1970: 1_000)
        let token = try MCPOAuth.parseToken(
            Data(#"{"access_token":"a","token_type":"Bearer","refresh_token":"r","expires_in":3600}"#.utf8),
            previous: nil, now: now)
        expect(!token.needsRefresh(now: now.addingTimeInterval(3539)), "refresh not premature")
        expect(token.needsRefresh(now: now.addingTimeInterval(3540)), "refresh at skew boundary")
        expect(
            token.needsRefresh(now: now.addingTimeInterval(3000), within: 600)
                && !token.needsRefresh(now: now.addingTimeInterval(2999), within: 600),
            "a wider margin moves the boundary with it")
        let rotated = try MCPOAuth.parseToken(
            Data(#"{"access_token":"b","token_type":"bearer","refresh_token":"r2"}"#.utf8),
            previous: token, now: now)
        expect(rotated.refreshToken == "r2", "refresh rotates")
        let preserved = try MCPOAuth.parseToken(
            Data(#"{"access_token":"b","token_type":"Bearer"}"#.utf8), previous: token, now: now)
        expect(
            preserved.refreshToken == "r" && preserved.expiresAt == nil,
            "omitted refresh retained, expiry not invented")
        for bad in [
            #"{"access_token":"a","token_type":"MAC"}"#, #"{"access_token":"a\r\nx","token_type":"Bearer"}"#,
            #"{"access_token":"a","token_type":"Bearer","expires_in":-1}"#
        ] {
            rejects("invalid token refused") {
                _ = try MCPOAuth.parseToken(Data(bad.utf8), previous: nil, now: now)
            }
        }
        var old = MCPServer(name: "Old")
        let encoded = try JSONEncoder().encode(old)
        expect(
            try JSONDecoder().decode(MCPServer.self, from: encoded).oauth == nil, "old server shape decodes")
        old.oauth = true
        expect(
            try JSONDecoder().decode(MCPServer.self, from: JSONEncoder().encode(old)).oauth == true,
            "OAuth mode persists")
        let oldSecrets = try JSONDecoder().decode(
            MCPSecretStore.Secrets.self, from: Data(#"{"headerValue":"old","environment":{}}"#.utf8))
        expect(oldSecrets.headerValue == "old" && oldSecrets.oauth == nil, "old secrets decode")
    }

    static func listenerLifecycle() async throws {
        let listener = MCPOAuthListener()
        try await listener.start(
            state: "expected", issuer: "https://auth.test", requiresIssuer: true, timeout: .seconds(10))
        let competing = MCPOAuthListener()
        do {
            try await competing.start(
                state: "other", issuer: "https://auth.test", requiresIssuer: true, timeout: .seconds(2))
            expect(false, "occupied port must fail")
        } catch { expect(true, "occupied port fails") }
        competing.cancel()
        let bad = URLRequest(url: URL(string: MCPOAuthListener.redirectURI + "?state=wrong&code=c")!)
        let (_, refused) = try await MCPOAuthHTTP.send(bad)
        expect(refused.statusCode == 400, "wrong state refused without consuming listener")
        let target =
            MCPOAuthListener.redirectURI + "?state=expected&code=fixture-code&iss=https%3A%2F%2Fauth.test"
        let (_, accepted) = try await MCPOAuthHTTP.send(URLRequest(url: URL(string: target)!))
        expect(accepted.statusCode == 200, "browser receives close-tab page")
        let code = try await listener.code()
        expect(code == "fixture-code", "callback yields code once")
        let expiring = MCPOAuthListener()
        try await expiring.start(
            state: "expected", issuer: "https://auth.test", requiresIssuer: false, timeout: .milliseconds(80))
        do {
            _ = try await expiring.code()
            expect(false, "timeout required")
        } catch {
            expect(error as? MCPOAuth.Failure == .timedOut, "timeout tears down listener")
        }
        let cancelled = MCPOAuthListener()
        try await cancelled.start(state: "expected", issuer: "https://auth.test", requiresIssuer: false)
        cancelled.cancel()
        do {
            _ = try await cancelled.code()
            expect(false, "cancellation required")
        } catch {
            expect(error is CancellationError, "cancel releases waiter")
        }
    }

    /// A refresh the server could not serve is not a rejected grant: the session must survive it.
    static func transientRefresh(
        _ refresh: String, registration: MCPOAuth.Registration, secrets: MCPSecretStore,
        manager: MCPOAuthManager
    ) async throws {
        var configured = MCPServer(
            name: refresh, transport: .http(url: base + "/mcp", headerName: ""))
        configured.oauth = true
        let server = configured
        defer { try? secrets.remove(for: server.id) }
        var stored = MCPSecretStore.Secrets()
        stored.oauth = MCPOAuth.Credentials(
            registration: registration,
            token: MCPOAuth.Token(
                accessToken: "expired", refreshToken: refresh,
                expiresAt: .distantPast, scope: "read"))
        try secrets.save(stored, for: server.id)
        do {
            _ = try await manager.accessToken(for: server)
            expect(false, "\(refresh): an unserved refresh must fail")
        } catch {
            expect(error as? MCPOAuth.Failure == .network, "\(refresh): a network failure")
        }
        expect(
            manager.status(for: server, stored: stored.oauth) == .signedIn,
            "\(refresh): session survives")
        stored.oauth?.token = MCPOAuth.Token(
            accessToken: "expired", refreshToken: "fixture-refresh",
            expiresAt: .distantPast, scope: "read")
        try secrets.save(stored, for: server.id)
        let recovered = try await manager.accessToken(for: server)
        expect(recovered == "fixture-access", "\(refresh): next refresh recovers")
    }

    /// A rotating server may already have spent the old refresh token; the new one must be kept.
    static func refreshOutlivesEditor(
        registration: MCPOAuth.Registration, secrets: MCPSecretStore, manager: MCPOAuthManager
    ) async throws {
        var configured = MCPServer(name: "Held", transport: .http(url: base + "/mcp", headerName: ""))
        configured.oauth = true
        let server = configured
        defer { try? secrets.remove(for: server.id) }
        var stored = MCPSecretStore.Secrets()
        stored.oauth = MCPOAuth.Credentials(
            registration: registration,
            token: MCPOAuth.Token(
                accessToken: "expired", refreshToken: "fixture-held",
                expiresAt: .distantPast, scope: "read"))
        try secrets.save(stored, for: server.id)
        async let refreshed = manager.accessToken(for: server)
        var polls = 0
        while try await count("held") == 0, polls < 200 {
            polls += 1
            try await Task.sleep(for: .milliseconds(10))
        }
        manager.cancelSignIn(server.id)
        _ = try await MCPOAuthHTTP.json(URL(string: base + "/release")!)
        let token: String?
        do { token = try await refreshed } catch { token = nil }
        expect(
            polls < 200 && token == "fixture-access"
                && secrets.secrets(for: server.id).oauth?.token?.refreshToken == "rotated-refresh",
            "closing or saving the editor lets a refresh in flight finish and keep its rotated token")
        try secrets.save(stored, for: server.id)
        async let abandoned = manager.accessToken(for: server)
        polls = 0
        while try await count("held") == 0, polls < 200 {
            polls += 1
            try await Task.sleep(for: .milliseconds(10))
        }
        try manager.signOut(server.id)
        _ = try await MCPOAuthHTTP.json(URL(string: base + "/release")!)
        let late: String?
        do { late = try await abandoned } catch { late = nil }
        expect(
            polls < 200 && late == nil && secrets.secrets(for: server.id).oauth?.token == nil,
            "sign-out still discards a refresh in flight")
    }

    /// A CLI keeps a lent token for its whole turn, so one about to expire is refreshed first.
    static func lendingOutlastsTheTurn(
        registration: MCPOAuth.Registration, secrets: MCPSecretStore, manager: MCPOAuthManager
    ) async throws {
        var configured = MCPServer(
            name: "Lent", transport: .http(url: base + "/mcp", headerName: ""))
        configured.oauth = true
        let server = configured
        defer { try? secrets.remove(for: server.id) }
        func store(refresh: String?) throws {
            var stored = MCPSecretStore.Secrets()
            stored.oauth = MCPOAuth.Credentials(
                registration: registration,
                token: MCPOAuth.Token(
                    accessToken: "five-minutes", refreshToken: refresh,
                    expiresAt: Date().addingTimeInterval(300), scope: "read"))
            try secrets.save(stored, for: server.id)
        }
        try store(refresh: "fixture-refresh")
        let used = try await manager.accessToken(for: server)
        let lent = try await manager.lentToken(for: server)
        expect(
            used == "five-minutes" && lent == "fixture-access",
            "five minutes serve Tinycast's own request; a CLI's whole turn gets a fresh token")
        try store(refresh: nil)
        let unrefreshable = try await manager.lentToken(for: server)
        expect(
            unrefreshable == "five-minutes",
            "with no refresh token it is lent as it is, rather than ending a session")
        try store(refresh: "fixture-unavailable")
        let offline = try await manager.lentToken(for: server)
        expect(
            offline == "five-minutes",
            "and a refresh the server cannot serve still lends the minutes that are left")
    }

    static func count(_ name: String) async throws -> Int {
        let data = try await MCPOAuthHTTP.json(URL(string: base + "/counts")!)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Int])?[name] ?? 0
    }

    /// A supplied client ID wins over registration and authenticates the way the server advertises.
    static func suppliedClient(_ discovered: MCPOAuthService.Discovery) async throws {
        let registered = try await count("registrations")
        func advertising(_ methods: String?) throws -> MCPOAuthService.Discovery {
            let field = methods.map { #","token_endpoint_auth_methods_supported":\#($0)"# } ?? ""
            let json =
                #"{"issuer":"\#(base)","authorization_endpoint":"\#(base)/authorize","#
                + #""token_endpoint":"\#(base)/token","registration_endpoint":"\#(base)/register","#
                + #""code_challenge_methods_supported":["S256"]\#(field)}"#
            return MCPOAuthService.Discovery(
                resource: discovered.resource,
                metadata: try MCPOAuth.parseServer(Data(json.utf8), issuer: base),
                scope: nil)
        }
        let pasted = MCPOAuth.Credentials.supplied(
            clientID: " supplied+client\n", clientSecret: "\ts3cr:t/= \n")
        expect(
            pasted.clientID == "supplied+client" && pasted.clientSecret == "s3cr:t/=",
            "a pasted client ID and secret lose the whitespace a paste brings")
        let publicClient = MCPOAuth.Credentials.supplied(clientID: "supplied+client", clientSecret: "")
        let none = try await MCPOAuthService.registration(for: discovered, credentials: publicClient)
        expect(
            none.clientID == "supplied+client" && none.clientSecret == nil && none.authMethod == "none",
            "a supplied client ID takes precedence over dynamic registration")
        let both = try advertising(#"["client_secret_post","client_secret_basic"]"#)
        let basic = try await MCPOAuthService.registration(for: both, credentials: pasted)
        let post = try await MCPOAuthService.registration(
            for: advertising(#"["none","client_secret_post"]"#), credentials: pasted)
        let unstated = try await MCPOAuthService.registration(for: advertising(nil), credentials: pasted)
        expect(
            basic.authMethod == "client_secret_basic" && post.authMethod == "client_secret_post"
                && unstated.authMethod == "client_secret_basic",
            "a secret goes as Basic when advertised or unstated, and in the body when only post is")
        do {
            _ = try await MCPOAuthService.registration(for: advertising(#"["none"]"#), credentials: pasted)
            expect(false, "a secret the token endpoint cannot take must be refused")
        } catch {
            expect(
                error as? MCPOAuth.Failure == .invalidMetadata,
                "a secret the token endpoint cannot take is refused")
        }
        for registration in [none, basic, post] {
            let token = try await MCPOAuthService.token(
                registration: registration, code: "fixture-code", verifier: "fixture-verifier")
            expect(
                token.accessToken == "fixture-access",
                "\(registration.authMethod): the code exchange succeeds")
        }
        let recorded = try await MCPOAuthHTTP.json(URL(string: base + "/client-auth")!)
        let authentication = try JSONSerialization.jsonObject(with: recorded) as? [String]
        expect(
            authentication == ["none", "basic supplied%2Bclient:s3cr%3At%2F%3D", "post s3cr:t/="],
            "the token endpoint sees no secret, a form-encoded Basic pair, or one body field")
        var stored = pasted
        stored.registration = MCPOAuth.Registration(
            resource: discovered.resource, issuer: base, clientID: pasted.clientID,
            clientSecret: pasted.clientSecret,
            tokenEndpoint: base + "/token", authMethod: "client_secret_post",
            redirectURI: MCPOAuthListener.redirectURI)
        let reused = try await MCPOAuthService.registration(for: both, credentials: stored)
        expect(reused == stored.registration, "a stored supplied registration is reused, not renegotiated")
        var resecreted = stored
        resecreted.clientSecret = "rotated"
        let renewed = try await MCPOAuthService.registration(for: both, credentials: resecreted)
        expect(
            renewed.clientSecret == "rotated" && renewed.authMethod == "client_secret_basic",
            "a changed secret is not answered with the stored registration")
        var moved = stored
        moved.registration = MCPOAuth.Registration(
            resource: discovered.resource, issuer: "https://old.test", clientID: pasted.clientID,
            clientSecret: pasted.clientSecret, tokenEndpoint: "https://old.test/token",
            authMethod: "client_secret_basic", redirectURI: MCPOAuthListener.redirectURI)
        do {
            _ = try await MCPOAuthService.registration(for: both, credentials: moved)
            expect(false, "a client ID from another issuer must be refused")
        } catch {
            expect(error as? MCPOAuth.Failure == .issuerChanged, "a client ID from another issuer is refused")
        }
        let registeredAfter = try await count("registrations")
        expect(registeredAfter == registered, "a supplied client ID never reaches the registration endpoint")
    }

    static func networkFlow() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "Tests/ai-fixtures/mcp-oauth-stub.js"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        let ready = pipe.fileHandleForReading.availableData
        guard String(bytes: ready, encoding: .utf8)?.contains("ready") == true else {
            throw MCPOAuth.Failure.network
        }
        let discovered = try await MCPOAuthService.discover(base + "/mcp")
        expect(discovered.scope == "read", "401 discovery carries requested scopes")
        let registration = try await MCPOAuthService.registration(
            for: discovered, credentials: MCPOAuth.Credentials())
        expect(registration.clientID == "fixture-client", "native DCR succeeded")
        try await suppliedClient(discovered)
        let token = try await MCPOAuthService.token(
            registration: registration, code: "fixture-code", verifier: "fixture-verifier")
        expect(token.accessToken == "fixture-access", "code exchange includes resource")
        let keychain = KeychainSecretStore(
            scope: "mcp-oauth-test-" + UUID().uuidString, bundleIdentifier: "test.tinycast")
        let secrets = MCPSecretStore(keychain: keychain)
        var configured = MCPServer(name: "Fixture", transport: .http(url: base + "/mcp", headerName: ""))
        configured.oauth = true
        let server = configured
        defer { try? secrets.remove(for: server.id) }
        var stored = MCPSecretStore.Secrets()
        stored.oauth = MCPOAuth.Credentials(
            registration: registration,
            token: MCPOAuth.Token(
                accessToken: "expired", refreshToken: "fixture-refresh",
                expiresAt: .distantPast, scope: "read"))
        try secrets.save(stored, for: server.id)
        let manager = MCPOAuthManager(secrets: secrets)
        async let first = manager.accessToken(for: server)
        async let second = manager.accessToken(for: server)
        let refreshed = try await (first, second)
        expect(
            refreshed.0 == "fixture-access" && refreshed.1 == "fixture-access",
            "concurrent refreshes coalesce")
        expect(
            secrets.secrets(for: server.id).oauth?.token?.refreshToken == "rotated-refresh",
            "rotated token persisted")
        let connection = MCPServerConnection(server: server, secrets: stored, oauth: manager)
        await connection.start()
        expect(
            connection.status.isReady && connection.tools.count == 1, "signed-in connection discovers tools")
        connection.stop()
        var sends = 0
        let transport = try MCPHTTPTransport(url: base + "/mcp", headerName: "", headerValue: "") {
            rejected in
            sends += 1
            return rejected == nil ? "expired" : "fixture-access"
        }
        try await transport.connect()
        let result = try await transport.request("tools/call", ["name": "greet", "arguments": [:]])
        expect(
            MCPToolOutput.flatten(result).0.contains("Hello from OAuth") && sends == 2,
            "401 refresh retries tool request once")
        transport.close()
        var attempts = 0
        let failing = try MCPHTTPTransport(url: base + "/always-401", headerName: "", headerValue: "") { _ in
            attempts += 1
            return "expired"
        }
        try await failing.connect()
        do {
            _ = try await failing.request("tools/list")
            expect(false, "second 401 must require sign-in")
        } catch {
            expect(error as? MCPOAuth.Failure == .signInRequired && attempts == 2, "401 retry bounded")
        }
        failing.close()
        let relocated = try MCPHTTPTransport(url: base + "/mcp-moved", headerName: "", headerValue: "") { _ in
            "fixture-access"
        }
        try await relocated.connect()
        let followed = try await relocated.request("tools/call", ["name": "greet", "arguments": [:]])
        expect(
            MCPToolOutput.flatten(followed).0.contains("Hello from OAuth"),
            "a same-origin redirect is followed with its credentials")
        relocated.close()
        let away = try MCPHTTPTransport(url: base + "/mcp-away", headerName: "", headerValue: "") { _ in
            "fixture-access"
        }
        try await away.connect()
        do {
            _ = try await away.request("tools/list")
            expect(false, "a cross-origin redirect must not be followed")
        } catch { expect(true, "a cross-origin redirect is refused") }
        away.close()
        var redirected = URLRequest(url: URL(string: base + "/redirect")!)
        redirected.setValue("Bearer fixture-access", forHTTPHeaderField: "Authorization")
        let (_, response) = try await MCPOAuthHTTP.send(redirected)
        expect(response.statusCode == 307, "authenticated redirects not followed")
        let counts = try await MCPOAuthHTTP.json(URL(string: base + "/counts")!)
        let object = try JSONSerialization.jsonObject(with: counts) as? [String: Int]
        expect(object?["refreshes"] == 1, "one token exchange for simultaneous refresh")
        expect(object?["redirects"] == 0, "redirect target never receives credentials")
        for refresh in ["fixture-unavailable", "fixture-dropped"] {
            try await transientRefresh(
                refresh, registration: registration, secrets: secrets, manager: manager)
        }
        try await refreshOutlivesEditor(registration: registration, secrets: secrets, manager: manager)
        try await lendingOutlastsTheTurn(
            registration: registration, secrets: secrets, manager: manager)
        var moved = server
        moved.transport = .http(url: base + "/other", headerName: "")
        do {
            _ = try await manager.accessToken(for: moved)
            expect(false, "retargeted server must not borrow token")
        } catch {
            expect(error as? MCPOAuth.Failure == .signInRequired, "resource binding survives URL edit")
        }
        let edited = MCPServerConnection(server: moved, secrets: stored, oauth: manager)
        await edited.start()
        let kept: String?
        do { kept = try await manager.accessToken(for: server) } catch { kept = nil }
        expect(
            edited.status == .signInRequired && kept == "fixture-access"
                && manager.status(for: server, stored: secrets.secrets(for: server.id).oauth) == .signedIn,
            "testing an edited URL leaves the saved server signed in")
        try manager.signOut(server.id)
        expect(
            secrets.secrets(for: server.id).oauth?.token == nil, "sign-out deletes access and refresh tokens")
        do {
            _ = try await manager.accessToken(for: server)
            expect(false, "signed-out token unavailable")
        } catch {
            expect(error as? MCPOAuth.Failure == .signInRequired, "signed-out requests require sign-in")
        }
    }
}
