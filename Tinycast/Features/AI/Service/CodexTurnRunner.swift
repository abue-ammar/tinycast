import Foundation

/// Generations over the app-server, one ephemeral thread each, so chats can run side by side.
@MainActor
final class CodexTurnRunner {
    private static let safetyInstructions = """
        You are providing text generation inside Tinycast. Never invoke tools, execute commands, read \
        files, inspect the environment, or modify files. Use only the request content supplied by \
        Tinycast.
        """
    /// The same boundary for the one turn shape that is handed tools; everything else stays off.
    private static let toolSafetyInstructions = """
        You are providing text generation inside Tinycast. The only tools you may use are the MCP \
        tools supplied with this request. Never execute commands, read files, inspect the \
        environment, or modify files.
        """
    private static let webSearchInstructions = """
        You may search the web when the answer depends on current or external information. Cite a \
        source as a markdown link whose text is the publication's name, never "Read more" or a URL.
        """
    private static let noWebSearchInstructions = "Never access external resources."

    var connect: (@MainActor ([AIToolServer]) async throws -> [ChatGPTSubscription.Model])?
    var onTurnEnded: (@MainActor () -> Void)?

    /// One stream's live state; its reference identity keeps a stale cleanup off its successor.
    private final class Turn {
        let continuation: AIProviderStream.Continuation
        /// What this turn may call and who answers; a turn armed with nothing declines every ask.
        let servers: [AIToolServer]
        let session: AIToolServerSession?
        var threadID: String?
        var turnID: String?
        /// The summary part the last delta belonged to, so the next part starts a paragraph.
        var summaryPart: String?
        /// The tool an elicitation is about: the item that names it always starts before the ask.
        var startedTools: [String: String] = [:]
        var spentCalls = 0

        init(
            continuation: AIProviderStream.Continuation, servers: [AIToolServer],
            session: AIToolServerSession?
        ) {
            self.continuation = continuation
            self.servers = servers
            self.session = session
        }

        var roundCap: Int? { session == nil ? 1 : session?.rounds }
    }

    /// Reference identity for one stream, handed out before its turn exists.
    private final class TurnToken: Sendable {}

    private let client: CodexAppServerClient
    private var turns: [ObjectIdentifier: Turn] = [:]
    /// Threads whose Stop beat the turn's ID; the first ID to name one spends its Stop.
    private var pendingInterruptThreadIDs: Set<String> = []

    init(client: CodexAppServerClient) {
        self.client = client
        client.onElicitation = { [weak self] elicitation in
            await self?.consent(to: elicitation) ?? false
        }
        client.onRelaunch = { [weak self] in self?.endStrandedTurns() }
    }

    var isActive: Bool { !turns.isEmpty }

    nonisolated func stream(
        _ request: AIRequest, model: String, effort: String?,
        toolServers: AIToolServerSession? = nil
    ) -> AIProviderStream {
        AIProviderStream { continuation in
            let token = TurnToken()
            let task = Task { [weak self] in
                await self?.startTurn(
                    request, model: model, effort: effort, toolServers: toolServers,
                    continuation: continuation, token: token)
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor in self?.endTurn(token) }
            }
        }
    }

    private func endTurn(_ token: TurnToken) {
        guard let turn = turns[ObjectIdentifier(token)] else { return }
        interrupt(turn, key: ObjectIdentifier(token))
    }

    func reset() {
        for (key, turn) in turns { interrupt(turn, key: key) }
    }

    func handle(method: String, params: [String: JSONValue]) {
        guard let thread = params["threadId"]?.stringValue else { return }
        if pendingInterruptThreadIDs.contains(thread) {
            handleArmed(method: method, params: params, threadID: thread)
            return
        }
        guard let entry = turns.first(where: { $0.value.threadID == thread }) else { return }
        let key = entry.key
        let turn = entry.value
        let continuation = turn.continuation
        switch method {
        case "item/agentMessage/delta":
            guard let delta = params["delta"]?.stringValue, !delta.isEmpty else { return }
            continuation.yield(.text(delta))
        // The summary, not raw reasoning: the raw stream is off by default and would repeat it.
        case "item/reasoning/summaryTextDelta":
            guard let delta = params["delta"]?.stringValue, !delta.isEmpty else { return }
            let part = "\(params["itemId"]?.stringValue ?? ""):\(params["summaryIndex"]?.intValue ?? 0)"
            if let previous = turn.summaryPart, previous != part { continuation.yield(.reasoning("\n\n")) }
            turn.summaryPart = part
            continuation.yield(.reasoning(delta))
        case "item/started":
            guard let item = params["item"]?.objectValue else { return }
            switch item["type"]?.stringValue {
            case "webSearch": continuation.yield(.searching(item["query"]?.stringValue))
            case "reasoning": continuation.yield(.thinking)
            case "mcpToolCall": startToolCall(item, in: turn, key: key)
            default: break
            }
        case "item/completed":
            guard let item = params["item"]?.objectValue else { return }
            switch item["type"]?.stringValue {
            case "webSearch": continuation.yield(.searched(item["query"]?.stringValue))
            case "mcpToolCall":
                guard let id = item["id"]?.stringValue else { return }
                continuation.yield(
                    .toolResult(id: id, isError: item["status"]?.stringValue != "completed"))
            default: break
            }
        case "turn/started":
            // Captured eagerly so Stop can interrupt even when the turn/start response never lands.
            if let id = params["turn"]?.objectValue?["id"]?.stringValue { turn.turnID = id }
        case "turn/completed":
            guard let completed = params["turn"]?.objectValue else { return }
            switch completed["status"]?.stringValue {
            case "completed":
                continuation.yield(.finished)
                continuation.finish()
            case "failed":
                continuation.finish(
                    throwing: AIProviderError.responseFailed(
                        completed["error"]?.objectValue?["message"]?.stringValue
                            ?? "Codex could not finish the response."))
            default:
                continuation.finish(
                    throwing: AIProviderError.responseFailed("The response was interrupted."))
            }
            clear(key)
        case "error":
            guard params["willRetry"]?.boolValue != true else { return }
            continuation.finish(
                throwing: AIProviderError.responseFailed(
                    params["error"]?.objectValue?["message"]?.stringValue
                        ?? "Codex returned an error."))
            clear(key)
        default:
            break
        }
    }

    /// A call's row, and the cap: Codex names no round, so it counts calls, which is stricter.
    private func startToolCall(_ item: [String: JSONValue], in turn: Turn, key: ObjectIdentifier) {
        guard let id = item["id"]?.stringValue else { return }
        let name = item["server"]?.stringValue ?? ""
        let handle = CodexMCPLaunch.handle(ofServer: name)
        if let handle, let tool = item["tool"]?.stringValue { turn.startedTools[handle] = tool }
        let origin = handle.map { AIToolServerRow.title(of: $0, in: turn.servers) }
        turn.continuation.yield(
            .toolCall(
                id: id, origin: origin ?? AIToolServerRow.label(name),
                title: AIToolServerRow.label(item["tool"]?.stringValue ?? "")))
        turn.spentCalls += 1
        guard let roundCap = turn.roundCap, turn.spentCalls > roundCap else { return }
        // Finished before the interrupt, whose own cleanup would otherwise name a different reason.
        turn.continuation.finish(
            throwing: AIProviderError.responseFailed(
                "Stopped after \(roundCap) rounds of tool calls."))
        interrupt(turn, key: key)
    }

    /// Routed by thread, so each chat's calls are asked about under that chat's own consent.
    private func consent(to elicitation: CodexElicitation) async -> Bool {
        guard let turn = turns.values.first(where: { $0.threadID == elicitation.threadID }),
            !turn.servers.isEmpty, let session = turn.session,
            let handle = CodexMCPLaunch.handle(ofServer: elicitation.serverName)
        else { return false }
        let tool = elicitation.namedTool ?? turn.startedTools[handle] ?? elicitation.toolName
        return await session.consent(AIToolServerCall(handle: handle, tool: tool))
    }

    /// The server list is fixed at launch, so a turn armed with another one ends the live threads.
    private func endStrandedTurns() {
        pendingInterruptThreadIDs.removeAll()
        for (key, turn) in turns where turn.threadID != nil {
            turn.continuation.finish(
                throwing: AIProviderError.responseFailed(
                    "Codex restarted to change the tools another chat can use."))
            clear(key)
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
            pendingInterruptThreadIDs.remove(threadID)
        default:
            break
        }
    }

    private func startTurn(
        _ request: AIRequest,
        model: String,
        effort: String?,
        toolServers: AIToolServerSession?,
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
        let key = ObjectIdentifier(token)
        var tookOwnership = false
        do {
            let servers = await toolServers?.servers() ?? []
            // The list is a launch fact, so `connect` may relaunch a server armed with another.
            let models = try await connect?(servers) ?? []
            // Discovery swallows errors, so a Stop that landed inside connect resurfaces here.
            try Task.checkCancellation()
            guard !model.isEmpty else {
                throw AIProviderError.unavailable(
                    "No Codex model is available for this account.")
            }
            let turn = Turn(continuation: continuation, servers: servers, session: toolServers)
            turns[key] = turn
            tookOwnership = true

            guard models.isEmpty || models.contains(where: { $0.id == model }) else {
                throw AIProviderError.unavailable(
                    "\(model) is no longer available. Choose another model in Settings.")
            }

            let threadResponse = try await client.request(
                method: "thread/start",
                params: [
                    "model": model,
                    "cwd": client.workspace.path,
                    // `untrusted` is what turns an MCP tool call into an elicitation to answer.
                    "approvalPolicy": servers.isEmpty ? "never" : "untrusted",
                    "sandbox": "read-only",
                    "ephemeral": true,
                    // Thread-scoped so this request never writes the user's saved web-search choice.
                    "config": ["web_search": request.webSearch ? "live" : "disabled"],
                    "developerInstructions": developerInstructions(
                        for: request, hasTools: !servers.isEmpty)
                ])
            guard let thread = threadResponse["thread"]?.objectValue,
                let threadID = thread["id"]?.stringValue
            else {
                throw CodexAppServerClient.ClientError.requestFailed(
                    "Codex returned no generation thread.")
            }
            // A thread claimed after Stop would route events to a stream nobody reads.
            guard turns[key] === turn, !Task.isCancelled else { return }
            turn.threadID = threadID

            let history = historyItems(from: request.messages[..<promptIndex])
            if !history.isEmpty {
                _ = try await client.request(
                    method: "thread/inject_items",
                    params: ["threadId": threadID, "items": history])
            }
            // An unstructured child survives Stop, so the turn ID it returns can be interrupted.
            var turnParameters: [String: Any] = [
                "threadId": threadID,
                "model": model,
                "approvalPolicy": servers.isEmpty ? "never" : "untrusted",
                "sandboxPolicy": ["type": "readOnly", "networkAccess": false],
                "input": turnInput(for: request.messages[promptIndex])
            ]
            if let effort { turnParameters["effort"] = effort }
            let turnTask = Task { [client] in
                try await client.request(
                    method: "turn/start", params: turnParameters)
            }
            let turnID = try await turnTask.value["turn"]?.objectValue?["id"]?.stringValue
            guard turns[key] === turn, !Task.isCancelled else {
                if turns[key] === turn { interrupt(turn, key: key) }
                if let turnID { interruptOnce(threadID: threadID, turnID: turnID) }
                return
            }
            if let turnID { turn.turnID = turnID }
        } catch is CancellationError {
            if tookOwnership {
                endTurn(token)
            } else if turns.isEmpty {
                // A pre-ownership Stop still skipped `endTurn`, so the idle timer must re-arm here.
                onTurnEnded?()
            }
        } catch {
            continuation.finish(throwing: ChatGPTSubscriptionManager.userFacing(error))
            if let turn = turns[key] {
                interrupt(turn, key: key)
            } else if !tookOwnership, turns.isEmpty {
                onTurnEnded?()
            }
        }
    }

    private func developerInstructions(for request: AIRequest, hasTools: Bool) -> String {
        let requestInstructions =
            ([request.instructions]
            + request.messages.compactMap {
                $0.role == .system ? $0.text : nil
            }).compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        let safety = hasTools ? Self.toolSafetyInstructions : Self.safetyInstructions
        let search = request.webSearch ? Self.webSearchInstructions : Self.noWebSearchInstructions
        return ([safety, search] + requestInstructions).joined(separator: "\n\n")
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

    private func interrupt(_ turn: Turn, key: ObjectIdentifier) {
        clear(key)
        guard let threadID = turn.threadID else { return }
        guard let turnID = turn.turnID else {
            // Stop beat the ID: arm the thread rather than lose the turn the server still runs.
            pendingInterruptThreadIDs.insert(threadID)
            return
        }
        interrupt(threadID: threadID, turnID: turnID)
    }

    /// Either naming of the turn may arrive first; disarming keeps a Stop from firing twice.
    private func interruptOnce(threadID: String, turnID: String) {
        guard pendingInterruptThreadIDs.remove(threadID) != nil else { return }
        interrupt(threadID: threadID, turnID: turnID)
    }

    private func interrupt(threadID: String, turnID: String) {
        Task { [weak self] in
            _ = try? await self?.client.request(
                method: "turn/interrupt", params: ["threadId": threadID, "turnId": turnID])
        }
    }

    /// Finishing ends a stream the server abandoned; the last live turn ending re-arms idle shutdown.
    private func clear(_ key: ObjectIdentifier) {
        guard let turn = turns.removeValue(forKey: key) else { return }
        turn.continuation.finish(
            throwing: AIProviderError.responseFailed("The Codex connection was interrupted."))
        if let threadID = turn.threadID { client.cancelElicitations(threadID: threadID) }
        if turns.isEmpty { onTurnEnded?() }
    }
}
