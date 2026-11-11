import AppKit
import AuthenticationServices

@main
@MainActor
struct ExtensionSignInTests {
    static var passes = 0
    static var failures = 0
    static let url = URL(string: "https://example.test/authorize")!
    static let redirect = URL(string: "raycast://oauth?code=fixture")!

    final class BrowserSession: ASWebAuthenticationSession {
        var starts = true
        var cancelled = false
        let completion: @Sendable (URL?, (any Error)?) -> Void

        init(completion: @escaping @Sendable (URL?, (any Error)?) -> Void) {
            self.completion = completion
            super.init(
                url: URL(string: "https://example.test/authorize")!,
                callback: .customScheme("raycast"), completionHandler: completion)
        }

        override func start() -> Bool { starts }
        override func cancel() { cancelled = true }
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async {
        _ = NSApplication.shared
        await failedStart()
        await browserCompletion()
        await cancellationBeforeStart()
        await cancellationDuringSignIn()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func failedStart() async {
        let signIn = ExtensionSignInSession { _, _, completion in
            let browser = BrowserSession(completion: completion)
            browser.starts = false
            return browser
        }
        do {
            _ = try await signIn.run(url: url, callbackScheme: "raycast")
            expect(false, "a refused browser start must throw")
        } catch {
            expect(
                error as? ExtensionSignInSession.Failure == .couldNotStart,
                "a refused start finishes without waiting for a browser callback")
        }
    }

    static func browserCompletion() async {
        for outcome in 0..<3 {
            let signIn = ExtensionSignInSession { _, scheme, completion in
                expect(scheme == "raycast", "the requested callback scheme reaches the browser")
                let browser = BrowserSession(completion: completion)
                switch outcome {
                case 0:
                    completion(redirect, nil)
                    completion(nil, URLError(.cancelled))
                case 1:
                    completion(nil, ASWebAuthenticationSessionError(.canceledLogin))
                default:
                    completion(nil, URLError(.cannotConnectToHost))
                }
                return browser
            }
            do {
                let result = try await signIn.run(url: url, callbackScheme: "raycast")
                expect(outcome == 0 && result == redirect, "success returns the redirect exactly once")
            } catch {
                if outcome == 1 {
                    expect(
                        error as? ExtensionSignInSession.Failure == .cancelled,
                        "dismissing the browser reports cancelled sign-in")
                } else {
                    expect(
                        outcome == 2 && (error as? URLError)?.code == .cannotConnectToHost,
                        "browser failures reach the caller")
                }
            }
        }
    }

    static func cancellationBeforeStart() async {
        var opened = false
        let signIn = ExtensionSignInSession { _, _, completion in
            opened = true
            return BrowserSession(completion: completion)
        }
        let task = Task { try await signIn.run(url: url, callbackScheme: "raycast") }
        task.cancel()
        do {
            _ = try await task.value
            expect(false, "an already cancelled task must throw")
        } catch {
            expect(error is CancellationError && !opened, "cancelled work never opens a browser")
        }
    }

    static func cancellationDuringSignIn() async {
        var browser: BrowserSession?
        var exited = false
        let signIn = ExtensionSignInSession { _, _, completion in
            let session = BrowserSession(completion: completion)
            browser = session
            return session
        }
        let task = Task {
            defer { exited = true }
            return try await signIn.run(url: url, callbackScheme: "raycast")
        }
        while browser == nil { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            expect(false, "cancelling an active sign-in must throw")
        } catch {
            expect(error is CancellationError, "task cancellation reaches the caller")
        }
        expect(browser?.cancelled == true, "cancelling the caller closes its browser")
        expect(exited, "the caller's cleanup runs without a browser completion callback")
        browser?.completion(redirect, nil)
        browser?.completion(nil, ASWebAuthenticationSessionError(.canceledLogin))
        await Task.yield()
        expect(exited, "late browser callbacks do not resume the caller again")
    }
}
