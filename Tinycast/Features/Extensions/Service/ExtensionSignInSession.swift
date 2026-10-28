import AppKit
import AuthenticationServices

/// One browser sign-in. It catches its own redirect, so an installed Raycast cannot take it.
@MainActor
final class ExtensionSignInSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: LocalizedError {
        case cancelled
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .cancelled: "Sign-in was cancelled."
            case .couldNotStart: "The sign-in session could not start."
            }
        }
    }

    typealias SessionFactory = (
        URL, String, @escaping @Sendable (URL?, (any Error)?) -> Void
    ) -> ASWebAuthenticationSession

    private nonisolated let anchor: ASPresentationAnchor
    private let makeSession: SessionFactory
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, any Error>?

    init(
        makeSession: @escaping SessionFactory = { url, scheme, completion in
            ASWebAuthenticationSession(
                url: url, callback: .customScheme(scheme), completionHandler: completion)
        }
    ) {
        anchor = NSApp.keyWindow ?? ASPresentationAnchor()
        self.makeSession = makeSession
    }

    /// Resolves with the redirect URL; cancelling the task closes the browser window.
    func run(url: URL, callbackScheme: String) async throws -> URL {
        let redirect = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = makeSession(url, callbackScheme) { [weak self] redirect, error in
                    Task { @MainActor in
                        if let redirect {
                            self?.finish(.success(redirect))
                        } else if let error,
                            (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin
                        {
                            self?.finish(.failure(error))
                        } else {
                            self?.finish(.failure(Failure.cancelled))
                        }
                    }
                }
                session.presentationContextProvider = self
                self.session = session
                if !session.start() { finish(.failure(Failure.couldNotStart)) }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
        try Task.checkCancellation()
        return redirect
    }

    private func cancel() {
        let session = session
        finish(.failure(CancellationError()))
        session?.cancel()
    }

    private func finish(_ result: Result<URL, any Error>) {
        let continuation = continuation
        self.continuation = nil
        session = nil
        continuation?.resume(with: result)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
