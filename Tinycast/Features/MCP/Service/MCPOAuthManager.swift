import AppKit
import Observation

@MainActor
@Observable
final class MCPOAuthManager {
    enum Status: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case required
        case failed(String)

        var label: String {
            switch self {
            case .signedOut: return "Not signed in"
            case .signingIn: return "Waiting for sign-in…"
            case .signedIn: return "Signed in"
            case .required: return "Sign-in required"
            case .failed(let message): return message
            }
        }
    }

    private(set) var statuses: [UUID: Status] = [:]
    @ObservationIgnored private let secrets: MCPSecretStore
    @ObservationIgnored private var revisions: [UUID: UUID] = [:]
    @ObservationIgnored private var refreshes: [UUID: Task<String, Error>] = [:]
    @ObservationIgnored private var listener: MCPOAuthListener?
    @ObservationIgnored private var signingIn: UUID?

    init(secrets: MCPSecretStore = MCPSecretStore()) { self.secrets = secrets }

    /// Takes the caller's credentials: a view body asks this and must not read the Keychain.
    func status(for server: MCPServer, stored credentials: MCPOAuth.Credentials?) -> Status {
        if let status = statuses[server.id] { return status }
        guard let registration = credentials?.registration,
            registration.resource == Self.resource(of: server),
            let token = credentials?.token
        else { return .signedOut }
        return token.needsRefresh(now: Date()) && token.refreshToken == nil ? .required : .signedIn
    }

    func signIn(server: MCPServer, credentials: MCPOAuth.Credentials) async throws {
        guard signingIn == nil else { throw MCPOAuth.Failure.signInInProgress }
        guard case .http(let url, _) = server.transport else { throw MCPOAuth.Failure.invalidMetadata }
        let revision = UUID()
        revisions[server.id] = revision
        refreshes.removeValue(forKey: server.id)?.cancel()
        signingIn = server.id
        statuses[server.id] = .signingIn
        let callback = MCPOAuthListener()
        listener = callback
        defer {
            callback.cancel()
            listener = nil
            signingIn = nil
        }
        do {
            let discovery = try await MCPOAuthService.discover(url)
            try checkRevision(server.id, revision)
            let registration = try await MCPOAuthService.registration(
                for: discovery, credentials: credentials)
            let pair = try MCPOAuthService.pkce()
            let state = MCPOAuth.base64URL(try MCPOAuthService.random())
            try await callback.start(
                state: state, issuer: registration.issuer,
                requiresIssuer: discovery.metadata.authorization_response_iss_parameter_supported == true)
            let authorize = try MCPOAuth.authorizeURL(
                metadata: discovery.metadata, registration: registration,
                challenge: pair.challenge, state: state, scope: discovery.scope)
            try checkRevision(server.id, revision)
            guard NSWorkspace.shared.open(authorize) else { throw MCPOAuth.Failure.network }
            let code = try await callback.code()
            let token = try await MCPOAuthService.token(
                registration: registration, code: code, verifier: pair.verifier)
            try checkRevision(server.id, revision)
            var stored = secrets.secrets(for: server.id)
            var signedIn = credentials
            signedIn.registration = registration
            signedIn.token = token
            stored.oauth = signedIn
            try secrets.save(stored, for: server.id)
            statuses[server.id] = .signedIn
        } catch {
            if revisions[server.id] == revision {
                statuses[server.id] =
                    error is CancellationError ? .signedOut : .failed(error.localizedDescription)
            }
            throw error
        }
    }

    func signOut(_ id: UUID) throws {
        cancelSignIn(id)
        revisions[id] = UUID()
        refreshes.removeValue(forKey: id)?.cancel()
        var stored = secrets.secrets(for: id)
        stored.oauth?.token = nil
        try secrets.save(stored, for: id)
        statuses[id] = .signedOut
    }

    /// A refresh in flight finishes: a rotating server may already have spent the old token.
    func cancelSignIn(_ id: UUID) {
        guard signingIn == id else { return }
        revisions[id] = UUID()
        listener?.cancel()
        statuses[id] = .signedOut
    }

    func stop() {
        if let signingIn { cancelSignIn(signingIn) }
    }

    /// A CLI holds a lent token for its whole turn, so it gets one with ten minutes left if it can.
    func lentToken(for server: MCPServer) async throws -> String {
        do {
            return try await accessToken(for: server, lasting: 600)
        } catch let failure as MCPOAuth.Failure where failure == .signInRequired {
            throw failure
        } catch {
            return try await accessToken(for: server)
        }
    }

    func accessToken(
        for server: MCPServer, rejectedToken: String? = nil, lasting margin: TimeInterval = 60
    ) async throws -> String {
        guard statuses[server.id] != .required else { throw MCPOAuth.Failure.signInRequired }
        let credentials = secrets.secrets(for: server.id).oauth
        guard let registration = credentials?.registration,
            registration.resource == Self.resource(of: server),
            let token = credentials?.token
        else {
            requireSignIn(server, stored: credentials)
            throw MCPOAuth.Failure.signInRequired
        }
        if let pending = refreshes[server.id] { return try await pending.value }
        // Without a refresh token nothing can extend it, and asking for one would end the session.
        let within = token.refreshToken == nil ? 60 : margin
        if rejectedToken != token.accessToken, !token.needsRefresh(now: Date(), within: within) {
            return token.accessToken
        }
        let revision = revisions[server.id] ?? UUID()
        revisions[server.id] = revision
        let task = Task { [weak self] in
            let refreshed = try await MCPOAuthService.token(registration: registration, previous: token)
            guard let self else { throw CancellationError() }
            try self.checkRevision(server.id, revision)
            var stored = self.secrets.secrets(for: server.id)
            guard stored.oauth?.registration == registration else { throw CancellationError() }
            stored.oauth?.token = refreshed
            try self.secrets.save(stored, for: server.id)
            return refreshed.accessToken
        }
        refreshes[server.id] = task
        defer { if refreshes[server.id] == task { refreshes[server.id] = nil } }
        do {
            let value = try await task.value
            try checkRevision(server.id, revision)
            statuses[server.id] = .signedIn
            return value
        } catch MCPOAuth.Failure.signInRequired {
            // Only a rejected grant ends the session; an offline refresh is retried next request.
            if revisions[server.id] == revision { statuses[server.id] = .required }
            throw MCPOAuth.Failure.signInRequired
        }
    }

    func requireSignIn(_ server: MCPServer) {
        requireSignIn(server, stored: secrets.secrets(for: server.id).oauth)
    }

    /// Test Connection on an edited URL says nothing about the session the saved server holds.
    private func requireSignIn(_ server: MCPServer, stored: MCPOAuth.Credentials?) {
        if let resource = stored?.registration?.resource, resource != Self.resource(of: server) { return }
        statuses[server.id] = .required
    }

    private static func resource(of server: MCPServer) -> String? {
        guard case .http(let url, _) = server.transport else { return nil }
        return try? MCPOAuth.resource(url)
    }

    private func checkRevision(_ id: UUID, _ revision: UUID) throws {
        try Task.checkCancellation()
        guard revisions[id] == revision else { throw CancellationError() }
    }
}
