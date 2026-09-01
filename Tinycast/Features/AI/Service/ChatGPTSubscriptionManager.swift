import AppKit
import Foundation
import Observation

/// Owns the private Codex app-server and the ChatGPT login; it only says whether a turn may start.
@MainActor
@Observable
final class ChatGPTSubscriptionManager {
    /// Long enough to span a conversation; a relaunch costs a second, a resident server ~20 MB.
    private static let idleShutdown: Duration = .seconds(600)

    private let client: CodexAppServerClient
    private let codexHome: URL
    let turns: CodexTurnRunner

    private(set) var phase = ChatGPTSubscription.Phase.idle
    private(set) var account: ChatGPTSubscription.Account?
    private(set) var models: [ChatGPTSubscription.Model] = []
    private(set) var rateLimits: ChatGPTSubscription.RateLimits?

    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        let root = supportDirectory.appending(path: "ChatGPTSubscription", directoryHint: .isDirectory)
        codexHome = root.appending(path: "CodexHome", directoryHint: .isDirectory)
        client = CodexAppServerClient(
            codexHome: codexHome,
            workspace: root.appending(path: "Workspace", directoryHint: .isDirectory))
        turns = CodexTurnRunner(client: client)
        turns.connect = { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.ensureConnected()
            return self.models
        }
        turns.onTurnEnded = { [weak self] in self?.turnDidEnd() }
        client.onNotification = { [weak self] method, params in
            self?.handleNotification(method: method, params: params)
        }
        client.onExit = { [weak self] message in
            self?.forget()
            self?.phase = .failed(message)
        }
    }

    var isConnected: Bool { account != nil && phase == .connected }

    /// With the file credential store, a completed sign-in is exactly this file.
    private var hasStoredLogin: Bool {
        FileManager.default.fileExists(atPath: codexHome.appending(path: "auth.json").path)
    }

    func refresh() {
        // A check is under way the moment it is asked for, so `.idle` can mean nobody asked.
        if phase == .idle { phase = .starting }
        runOperation { [weak self] in await self?.refreshNow() }
    }

    func connect(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        runOperation { [weak self] in
            guard let self else { return }
            // A sign-in can fail or be abandoned in the browser, so arm on every outcome.
            defer { self.scheduleIdleShutdown() }
            self.phase = .starting
            do {
                try await self.client.start()
                let response = try await self.client.request(
                    method: "account/login/start",
                    params: [
                        "type": "chatgpt",
                        "useHostedLoginSuccessPage": true,
                        "appBrand": "chatgpt"
                    ])
                guard let urlString = response["authUrl"]?.stringValue,
                    let url = URL(string: urlString), openURL(url)
                else {
                    self.phase = .failed("The ChatGPT sign-in page could not be opened.")
                    return
                }
                self.phase = .waitingForBrowser
            } catch {
                self.apply(error)
            }
        }
    }

    func logout() {
        runOperation { [weak self] in
            guard let self else { return }
            do {
                try await self.client.start()
                _ = try await self.client.request(method: "account/logout")
                self.forget()
                self.phase = .signedOut
                self.client.stop()
            } catch {
                self.apply(error)
            }
        }
    }

    /// Releases process, timers and state alike; `.idle` lets the next visit check again.
    func stop() {
        operationTask?.cancel()
        // Interrupting a live turn re-arms idle shutdown, so forgetting must precede the cancel.
        forget()
        phase = .idle
        idleTask?.cancel()
        client.stop()
    }

    /// What a turn needs before it starts: a running server and a signed-in account.
    private func ensureConnected() async throws {
        idleTask?.cancel()
        try await client.start()
        if account == nil, try await restoreAccount() {
            phase = .connected
            await loadModelsAndLimits()
        }
        guard account != nil else {
            throw AIProviderError.unavailable("Connect ChatGPT in Settings first.")
        }
    }

    private func turnDidEnd() {
        Task { [weak self] in await self?.loadRateLimits() }
        scheduleIdleShutdown()
    }

    private func runOperation(_ operation: @escaping @MainActor () async -> Void) {
        operationTask?.cancel()
        operationTask = Task { await operation() }
    }

    /// Never spawns for an account that was never signed in: the picker and Settings ask often.
    private func refreshNow() async {
        guard hasStoredLogin || client.isRunning else {
            forget()
            phase = .signedOut
            return
        }
        phase = .starting
        do {
            try await client.start()
            guard try await restoreAccount() else {
                phase = .signedOut
                client.stop()
                return
            }
            phase = .connected
            await loadModelsAndLimits()
            scheduleIdleShutdown()
        } catch {
            apply(error)
        }
    }

    /// The server stays resident only while it is being used; a stopped one restarts on demand.
    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleShutdown)
            guard !Task.isCancelled, let self, !self.turns.isActive else { return }
            // A sign-in that lapsed here is over: say so rather than wait on a stopped server.
            if self.phase == .waitingForBrowser { self.phase = .signedOut }
            self.turns.reset()
            self.client.stop()
        }
    }

    private func loadModelsAndLimits() async {
        do {
            let response = try await client.request(
                method: "model/list", params: ["includeHidden": false, "limit": 100])
            models = (response["data"]?.arrayValue ?? []).compactMap { value in
                guard let raw = value.objectValue, let id = raw["model"]?.stringValue else {
                    return nil
                }
                let efforts = (raw["supportedReasoningEfforts"]?.arrayValue ?? []).compactMap {
                    effort -> ChatGPTSubscription.Effort? in
                    guard let raw = effort.objectValue,
                        let id = raw["reasoningEffort"]?.stringValue
                    else { return nil }
                    return ChatGPTSubscription.Effort(
                        id: id, detail: raw["description"]?.stringValue)
                }
                return ChatGPTSubscription.Model(
                    id: id,
                    name: raw["displayName"]?.stringValue ?? id,
                    efforts: efforts,
                    defaultEffort: raw["defaultReasoningEffort"]?.stringValue,
                    isDefault: raw["isDefault"]?.boolValue ?? false)
            }
        } catch {
            models = []
        }
        await loadRateLimits()
    }

    private func loadRateLimits() async {
        do {
            let response = try await client.request(method: "account/rateLimits/read")
            guard let limits = response["rateLimits"]?.objectValue else {
                rateLimits = nil
                return
            }
            rateLimits = ChatGPTSubscription.RateLimits(
                primary: usageWindow(limits["primary"]),
                secondary: usageWindow(limits["secondary"]))
        } catch {
            rateLimits = nil
        }
    }

    private func usageWindow(_ value: JSONValue?) -> ChatGPTSubscription.UsageWindow? {
        guard let raw = value?.objectValue, let used = raw["usedPercent"]?.intValue else {
            return nil
        }
        return ChatGPTSubscription.UsageWindow(
            usedPercent: used,
            durationMinutes: raw["windowDurationMins"]?.intValue,
            resetsAt: raw["resetsAt"]?.intValue.map {
                Date(timeIntervalSince1970: Double($0))
            })
    }

    private func restoreAccount() async throws -> Bool {
        let response = try await client.request(
            method: "account/read", params: ["refreshToken": false])
        guard let rawAccount = response["account"]?.objectValue,
            rawAccount["type"]?.stringValue == "chatgpt"
        else {
            forget()
            return false
        }
        account = ChatGPTSubscription.Account(
            email: rawAccount["email"]?.stringValue,
            plan: rawAccount["planType"]?.stringValue ?? "unknown")
        return true
    }

    private func handleNotification(method: String, params: [String: JSONValue]) {
        switch method {
        case "account/login/completed":
            if params["success"]?.boolValue == true {
                runOperation { [weak self] in await self?.refreshNow() }
            } else {
                phase = .failed(
                    params["error"]?.stringValue ?? "ChatGPT sign-in did not complete.")
            }
        case "account/updated":
            runOperation { [weak self] in await self?.refreshNow() }
        default:
            turns.handle(method: method, params: params)
        }
    }

    private func forget() {
        account = nil
        models = []
        rateLimits = nil
        turns.reset()
    }

    private func apply(_ error: Error) {
        // A cancelled check has no verdict: whoever cancelled it already set the state it wanted.
        guard !Task.isCancelled else { return }
        forget()
        let message = Self.userFacing(error).localizedDescription
        if let clientError = error as? CodexAppServerClient.ClientError,
            case .executableMissing = clientError
        {
            phase = .unavailable(message)
        } else {
            phase = .failed(message)
        }
    }

    static func userFacing(_ error: Error) -> Error {
        if error is AIProviderError { return error }
        let message =
            (error as? LocalizedError)?.errorDescription
            ?? "The ChatGPT connection failed."
        return AIProviderError.responseFailed(message)
    }
}

struct ChatGPTSubscriptionProvider: AIProvider {
    let turns: CodexTurnRunner
    let model: String
    let effort: String?

    func stream(_ request: AIRequest) -> AIProviderStream {
        turns.stream(request, model: model, effort: effort)
    }
}
