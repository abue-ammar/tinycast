import Foundation

/// One generation at a time over the app-server, streamed back as provider events.
@MainActor
final class CodexTurnRunner {
    private static let safetyInstructions = """
        You are providing text generation inside Tinycast. Never invoke tools, execute commands, read \
        files, inspect the environment, or modify files. Use only the request content supplied by \
        Tinycast.
        """
    private static let webSearchInstructions = """
        You may search the web when the answer depends on current or external information. Cite a \
        source as a markdown link whose text is the publication's name, never "Read more" or a URL.
        """
    private static let noWebSearchInstructions = "Never access external resources."

    var connect: (@MainActor () async throws -> [ChatGPTSubscription.Model])?
    var onTurnEnded: (@MainActor () -> Void)?

    /// Reference identity for one stream, so a stale turn's cleanup can't clear its successor.
    private final class TurnToken: Sendable {}

    private let client: CodexAppServerClient
    private var activeContinuation: AIProviderStream.Continuation?
    private var activeToken: TurnToken?
    private var activeThreadID: String?
    private var activeTurnID: String?
    /// A Stop that beat the turn's ID arms its thread; the first ID to name it spends the Stop.
    private var pendingInterruptThreadID: String?
    private var appliedEffort: String?

    init(client: CodexAppServerClient) {
        self.client = client
    }

    var isActive: Bool { activeThreadID != nil }

    nonisolated func stream(_ request: AIRequest, model: String, effort: String?) -> AIProviderStream {
        AIProviderStream { continuation in
            let token = TurnToken()
            let task = Task { [weak self] in
                await self?.startTurn(
                    request, model: model, effort: effort, continuation: continuation, token: token)
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor in self?.endTurn(token) }
            }
        }
    }

    private func endTurn(_ token: TurnToken) {
        guard activeToken === token else { return }
        interruptActiveTurn()
    }

    /// Drops the live turn and the effort in the server's config; the next turn rewrites it.
    func reset() {
        interruptActiveTurn()
        appliedEffort = nil
    }

    func handle(method: String, params: [String: JSONValue]) {
        let thread = params["threadId"]?.stringValue
        if let thread, thread == pendingInterruptThreadID {
            handleArmed(method: method, params: params, threadID: thread)
            return
        }
        guard thread == activeThreadID else { return }
        switch method {
        case "item/agentMessage/delta":
            guard let delta = params["delta"]?.stringValue, !delta.isEmpty else { return }
            activeContinuation?.yield(.text(delta))
        case "item/started":
            guard let item = params["item"]?.objectValue else { return }
            switch item["type"]?.stringValue {
            case "webSearch": activeContinuation?.yield(.searching(item["query"]?.stringValue))
            case "reasoning": activeContinuation?.yield(.thinking)
            default: break
            }
        case "item/completed":
            guard let item = params["item"]?.objectValue, item["type"]?.stringValue == "webSearch"
            else { return }
            activeContinuation?.yield(.searched(item["query"]?.stringValue))
        case "turn/started":
            // Captured eagerly so Stop can interrupt even when the turn/start response never lands.
            if let id = params["turn"]?.objectValue?["id"]?.stringValue { activeTurnID = id }
        case "turn/completed":
            guard let turn = params["turn"]?.objectValue else { return }
            switch turn["status"]?.stringValue {
            case "completed":
                activeContinuation?.yield(.finished)
                activeContinuation?.finish()
            case "failed":
                activeContinuation?.finish(
                    throwing: AIProviderError.responseFailed(
                        turn["error"]?.objectValue?["message"]?.stringValue
                            ?? "ChatGPT could not finish the response."))
            default:
                activeContinuation?.finish(
                    throwing: AIProviderError.responseFailed("The response was interrupted."))
            }
            clearActiveTurn()
        case "error":
            guard params["willRetry"]?.boolValue != true else { return }
            activeContinuation?.finish(
                throwing: AIProviderError.responseFailed(
                    params["error"]?.objectValue?["message"]?.stringValue
                        ?? "ChatGPT returned an error."))
            clearActiveTurn()
        default:
            break
        }
    }

    /// A thread Stop already dropped, watched only for the turn ID that Stop lacked.
    private func handleArmed(
        method: String, params: [String: JSONValue], threadID: String
    ) {
        switch method {
        case "turn/started":
            guard let id = params["turn"]?.objectValue?["id"]?.stringValue else { return }
            interruptOnce(threadID: threadID, turnID: id)
        case "turn/completed", "error":
            pendingInterruptThreadID = nil
        default:
            break
        }
    }

    private func startTurn(
        _ request: AIRequest,
        model: String,
        effort: String?,
        continuation: AIProviderStream.Continuation,
        token: TurnToken
    ) async {
        guard
            let promptIndex = request.messages.lastIndex(where: {
                $0.role == .user
                    && (!$0.images.isEmpty
                        || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            })
        else {
            continuation.finish(
                throwing: AIProviderError.unavailable("There is no user message to send."))
            return
        }
        var tookOwnership = false
        do {
            let models = try await connect?() ?? []
            // Discovery swallows errors, so a Stop that landed inside connect resurfaces here.
            try Task.checkCancellation()
            guard !model.isEmpty else {
                throw AIProviderError.unavailable(
                    "No ChatGPT model is available for this account.")
            }
            activeContinuation?.finish(
                throwing: AIProviderError.responseFailed(
                    "A newer request replaced this response."))
            activeContinuation = continuation
            activeToken = token
            tookOwnership = true

            guard models.isEmpty || models.contains(where: { $0.id == model }) else {
                throw AIProviderError.unavailable(
                    "\(model) is no longer available — choose another model in Settings.")
            }

            if let effort, effort != appliedEffort {
                _ = try await client.request(
                    method: "config/value/write",
                    params: [
                        "keyPath": "model_reasoning_effort",
                        "value": effort,
                        "mergeStrategy": "replace"
                    ])
                appliedEffort = effort
            }

            let threadResponse = try await client.request(
                method: "thread/start",
                params: [
                    "model": model,
                    "cwd": client.workspace.path,
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "ephemeral": true,
                    // Thread-scoped, in Tinycast's private Codex home: never the user's ~/.codex.
                    "config": ["web_search": request.webSearch ? "live" : "disabled"],
                    "developerInstructions": developerInstructions(for: request)
                ])
            guard let thread = threadResponse["thread"]?.objectValue,
                let threadID = thread["id"]?.stringValue
            else {
                throw CodexAppServerClient.ClientError.requestFailed(
                    "Codex returned no generation thread.")
            }
            // Claiming the thread after losing the turn aims `isActive` at a stream nobody reads.
            guard activeToken === token, !Task.isCancelled else { return }
            activeThreadID = threadID

            let history = historyItems(from: request.messages[..<promptIndex])
            if !history.isEmpty {
                _ = try await client.request(
                    method: "thread/inject_items",
                    params: ["threadId": threadID, "items": history])
            }
            // An unstructured child survives Stop, so the turn ID it returns can be interrupted.
            let turnTask = Task { [client] in
                try await client.request(
                    method: "turn/start",
                    params: [
                        "threadId": threadID,
                        "model": model,
                        "approvalPolicy": "never",
                        "sandboxPolicy": ["type": "readOnly", "networkAccess": false],
                        "input": turnInput(for: request.messages[promptIndex])
                    ])
            }
            let turnID = try await turnTask.value["turn"]?.objectValue?["id"]?.stringValue
            guard activeToken === token, !Task.isCancelled else {
                if activeToken === token { interruptActiveTurn() }
                if let turnID { interruptOnce(threadID: threadID, turnID: turnID) }
                return
            }
            if let turnID { activeTurnID = turnID }
        } catch is CancellationError {
            if tookOwnership {
                endTurn(token)
            } else if activeToken == nil {
                // A pre-ownership Stop still skipped `endTurn`, so the idle timer must re-arm here.
                onTurnEnded?()
            }
        } catch {
            continuation.finish(throwing: ChatGPTSubscriptionManager.userFacing(error))
            if activeToken === token {
                interruptActiveTurn()
            } else if !tookOwnership, activeToken == nil {
                onTurnEnded?()
            }
        }
    }

    private func developerInstructions(for request: AIRequest) -> String {
        let requestInstructions =
            ([request.instructions]
            + request.messages.compactMap {
                $0.role == .system ? $0.text : nil
            }).compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        let search = request.webSearch ? Self.webSearchInstructions : Self.noWebSearchInstructions
        return ([Self.safetyInstructions, search] + requestInstructions).joined(separator: "\n\n")
    }

    private func turnInput(for message: AIMessage) -> [[String: Any]] {
        var input: [[String: Any]] = []
        if !message.text.isEmpty { input.append(["type": "text", "text": message.text]) }
        input += message.images.map { ["type": "image", "url": $0.dataURL] }
        return input
    }

    private func historyItems(from messages: ArraySlice<AIMessage>) -> [[String: Any]] {
        messages.compactMap { message in
            guard message.role != .system,
                !message.images.isEmpty
                    || !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let role = message.role == .user ? "user" : "assistant"
            let contentType = message.role == .user ? "input_text" : "output_text"
            var content: [[String: Any]] = []
            if !message.text.isEmpty { content.append(["type": contentType, "text": message.text]) }
            content += message.images.map { ["type": "input_image", "image_url": $0.dataURL] }
            return ["type": "message", "role": role, "content": content]
        }
    }

    private func interruptActiveTurn() {
        let threadID = activeThreadID
        let turnID = activeTurnID
        clearActiveTurn()
        guard let threadID else { return }
        guard let turnID else {
            // Stop beat the ID: arm the thread rather than lose the turn the server still runs.
            pendingInterruptThreadID = threadID
            return
        }
        interrupt(threadID: threadID, turnID: turnID)
    }

    /// Either naming of the turn may arrive first; disarming keeps a Stop from firing twice.
    private func interruptOnce(threadID: String, turnID: String) {
        guard pendingInterruptThreadID == threadID else { return }
        pendingInterruptThreadID = nil
        interrupt(threadID: threadID, turnID: turnID)
    }

    private func interrupt(threadID: String, turnID: String) {
        Task { [weak self] in
            _ = try? await self?.client.request(
                method: "turn/interrupt", params: ["threadId": threadID, "turnId": turnID])
        }
    }

    /// Finishing ends a stream the server abandoned; ending a live turn re-arms idle shutdown.
    private func clearActiveTurn() {
        let wasLive = activeContinuation != nil
        activeContinuation?.finish(
            throwing: AIProviderError.responseFailed("The ChatGPT connection was interrupted."))
        activeContinuation = nil
        activeToken = nil
        activeThreadID = nil
        activeTurnID = nil
        if wasLive { onTurnEnded?() }
    }
}
