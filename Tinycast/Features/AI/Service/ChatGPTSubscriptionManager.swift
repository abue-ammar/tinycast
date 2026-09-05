import Foundation
import Observation

/// Owns app-server while reusing the account already configured in the user's Codex installation.
@MainActor
@Observable
final class ChatGPTSubscriptionManager {
    /// Long enough to span a conversation; a relaunch costs a second, a resident server ~20 MB.
    private static let idleShutdown: Duration = .seconds(600)

    private let client: CodexAppServerClient
    let turns: CodexTurnRunner

    private(set) var phase = ChatGPTSubscription.Phase.idle
    private(set) var account: ChatGPTSubscription.Account?
    private(set) var models: [ChatGPTSubscription.Model] = []
    private(set) var rateLimits: ChatGPTSubscription.RateLimits?

    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        let root = supportDirectory.appending(path: "InstalledAI/Codex", directoryHint: .isDirectory)
        client = CodexAppServerClient(
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

    func refresh() {
        // A check is under way the moment it is asked for, so `.idle` can mean nobody asked.
        if phase == .idle { phase = .starting }
        runOperation { [weak self] in await self?.refreshNow() }
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
            throw AIProviderError.unavailable("Sign in with `codex login`, then check Codex again.")
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

    private func refreshNow() async {
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
                let rawEfforts = raw["supportedReasoningEfforts"]?.arrayValue ?? []
                let efforts = rawEfforts.compactMap { effort -> ChatGPTSubscription.Effort? in
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
        guard let rawAccount = response["account"]?.objectValue else {
            forget()
            return false
        }
        let type = rawAccount["type"]?.stringValue ?? "unknown"
        account = ChatGPTSubscription.Account(
            email: rawAccount["email"]?.stringValue,
            plan: rawAccount["planType"]?.stringValue ?? type)
        return true
    }

    private func handleNotification(method: String, params: [String: JSONValue]) {
        switch method {
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
            ?? "The Codex connection failed."
        return AIProviderError.responseFailed(message)
    }
}

struct CodexInstalledProvider: AIProvider {
    let turns: CodexTurnRunner
    let model: String
    let effort: String?

    func stream(_ request: AIRequest) -> AIProviderStream {
        turns.stream(request, model: model, effort: effort)
    }
}
