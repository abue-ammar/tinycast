import Foundation
import SQLite3

@main
@MainActor
struct AIChatTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        sessionSummariesAndRequests()
        requestsKeepOnlyBoundedContext()
        attachmentsStayInsideTheTurnBudget()
        attachedTextInlinesOnlyIntoTheRequest()
        onlyPDFsSurviveAsDocuments()
        inlinedTextIsFencedAndNamed()
        attachmentPolicyClassifiesWhatCanBeAttached()
        historyRoundTripsAndRepairsInterruptedReplies()
        savesRewriteOnlyTheStoredTail()
        crashRepairSurvivesTailSaves()
        markdownParsesStreamingFriendlyBlocks()
        markdownParsesTablesQuotesAndLists()
        markdownKeepsCommonMarkEdges()
        segmentsClampSearchOffsets()
        leavingAConversationDropsItsStagedImages()
        retentionPrunesByAgeAndCascades()
        segmentsInterleaveSearchesAndTools()
        consecutiveToolCallsMerge()
        searchesSeparateToolRuns()
        arrivalOrderBreaksOffsetTies()
        await arrivalOrderSurvivesTheReplyAndReload()
        textSeparatesToolRuns()
        singleToolCallsStaySingle()
        toolRunsDescribeTheirState()
        await theToolLoopRunsUntilTheModelStopsAsking()
        await theToolLoopRefusesToRunForever()
        await anUnlimitedToolLoopRunsPastEveryStep()
        await anUnlimitedToolLoopStopsWhenItsHistoryIsFull()
        await toolOutputIsBoundedBeforeItIsBilled()
        toolUsesPersistAndSettleOnReload()
        renamesAndPinsSurviveSavesAndSpareRetention()
        transcriptsExportAndDropOnlyATrailingReply()
        await regenerateAsksTheSameQuestionAgain()
        await aConversationIsLiveOnOneSurfaceAtATime()
        await everyStateReportsAFinishedReply()
        await reasoningFoldsIntoTheReplyAndIsNeverResent()
        chatsKeepTheirOwnModel()
        choicesComeOutOfTheirFence()
        referencesAreTheLinksAReplyCites()
        titlesAreCleanedAndNeverBeatARename()
        findWalksMatchesAndWraps()
        citationsCloseTheSentenceThatCitedThem()
        toolScopeSwitchesServersPerChat()
        await usageIsKeptWithTheReplyThatReportedIt()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// A reply that searched and called tools has to render them in the order they happened.
    static func segmentsInterleaveSearchesAndTools() {
        let message = ChatMessage(
            role: .assistant, text: "abcdef",
            searches: [ChatSearch(query: "q", isComplete: true, textOffset: 4, sequence: 1)],
            toolUses: [
                ChatToolUse(
                    callID: "1", origin: "Files", title: "read", state: .completed, textOffset: 2,
                    sequence: 0)
            ])
        expect(
            message.segments == [
                .text("ab"),
                .tools([
                    ChatToolUse(
                        callID: "1", origin: "Files", title: "read", state: .completed,
                        textOffset: 2, sequence: 0)
                ]),
                .text("cd"),
                .search(ChatSearch(query: "q", isComplete: true, textOffset: 4, sequence: 1)),
                .text("ef")
            ],
            "segments interleave by offset, whichever kind of interruption came first")
        expect(
            ChatToolUse(
                callID: "1", origin: "Files", title: "read", state: .running, textOffset: 0,
                sequence: 0
            ).label
                == "Calling Files · read",
            "a running call says so, and names the server it is calling")
    }

    static func consecutiveToolCallsMerge() {
        let uses = [
            ChatToolUse(
                callID: "1", origin: "Files", title: "read", state: .completed, textOffset: 2,
                sequence: 0),
            ChatToolUse(
                callID: "2", origin: "Files", title: "list", state: .failed, textOffset: 2,
                sequence: 1),
            ChatToolUse(
                callID: "3", origin: "Files", title: "find", state: .running, textOffset: 2,
                sequence: 2)
        ]
        let message = ChatMessage(role: .assistant, text: "abcd", toolUses: uses)
        expect(
            message.segments == [.text("ab"), .tools(uses), .text("cd")],
            "consecutive calls form one run in call order, regardless of state")
    }

    /// No text has arrived, so every offset is 0 and only the order they came in can place them.
    static func searchesSeparateToolRuns() {
        let first = ChatToolUse(
            callID: "1", origin: "Files", title: "read", state: .completed, textOffset: 0,
            sequence: 0)
        let last = ChatToolUse(
            callID: "2", origin: "Files", title: "list", state: .completed, textOffset: 0,
            sequence: 3)
        let searches = [
            ChatSearch(query: "one", isComplete: true, textOffset: 0, sequence: 1),
            ChatSearch(query: "two", isComplete: true, textOffset: 0, sequence: 2)
        ]
        let message = ChatMessage(
            role: .assistant, text: "", searches: searches, toolUses: [first, last])
        expect(
            message.segments == [
                .tools([first]), .search(searches[0]), .search(searches[1]), .tools([last])
            ],
            "searches stay separate and break tool runs in a reply with no text")
    }

    static func arrivalOrderBreaksOffsetTies() {
        let first = ChatToolUse(
            callID: "1", origin: "Files", title: "read", state: .completed, textOffset: 2,
            sequence: 0)
        let search = ChatSearch(query: "q", isComplete: true, textOffset: 2, sequence: 1)
        let last = ChatToolUse(
            callID: "2", origin: "Files", title: "list", state: .completed, textOffset: 2,
            sequence: 2)
        let message = ChatMessage(
            role: .assistant, text: "abcd", searches: [search], toolUses: [first, last])
        expect(
            message.segments == [
                .text("ab"), .tools([first]), .search(search), .tools([last]), .text("cd")
            ],
            "at one offset a call, a search and a call keep the order they came in")
    }

    /// Created live, stored and reloaded: the order has to come through all three.
    static func arrivalOrderSurvivesTheReplyAndReload() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ai-order-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let chat = AIChatState(history: ChatHistoryStore(directory: directory))
        let provider = ScriptedProvider(rounds: [
            [
                .toolCall(id: "a", origin: "Files", title: "read"),
                .toolResult(id: "a", isError: false),
                .searching("news"),
                .searched("news"),
                .toolCall(id: "b", origin: "Files", title: "list"),
                .toolResult(id: "b", isError: false),
                .text("Done."),
                .finished
            ]
        ])
        expect(chat.send("go", using: provider), "the turn starts")
        var waited = 0
        while chat.isStreaming, waited < 400 {
            try? await Task.sleep(for: .milliseconds(5))
            waited += 1
        }
        let expected = ["tools a", "search news", "tools b", "text Done."]
        expect(
            shape(chat.session.messages.last?.segments) == expected,
            "a search between two calls parts them, live, before any text has arrived")

        let database = directory.appendingPathComponent("ai-chats.sqlite3")
        let reloaded = ChatHistoryStore(directory: directory).session(id: chat.session.id)
        expect(
            shape(reloaded?.messages.last?.segments) == expected,
            "and still parts them once the chat is reopened from history")
        expect(
            count(database, "SELECT position FROM message_searches") == 1,
            "a search's position is its place among the reply's searches and calls")

        expect(
            tamper(
                database,
                """
                UPDATE message_searches SET position = 0;
                UPDATE message_tools SET position = 1 WHERE call_id = 'b';
                """),
            "the harness can store positions the way they were stored before")
        let older = ChatHistoryStore(directory: directory).session(id: chat.session.id)
        expect(
            shape(older?.messages.last?.segments) == ["search news", "tools a,b", "text Done."],
            "a chat stored with each table's own positions loads, a tie going to the search")
    }

    static func shape(_ segments: [ChatSegment]?) -> [String] {
        (segments ?? []).map {
            switch $0 {
            case .text(let text): "text \(text)"
            case .search(let search): "search \(search.query ?? "")"
            case .tools(let uses): "tools \(uses.map(\.callID).joined(separator: ","))"
            case .reasoning(let block): "reasoning \(block.text)"
            }
        }
    }

    static func textSeparatesToolRuns() {
        let first = ChatToolUse(
            callID: "1", origin: "Files", title: "read", state: .completed, textOffset: 0,
            sequence: 0)
        let last = ChatToolUse(
            callID: "2", origin: "Files", title: "list", state: .completed, textOffset: 1,
            sequence: 1)
        let message = ChatMessage(role: .assistant, text: " ", toolUses: [first, last])
        expect(
            message.segments == [.tools([first]), .text(" "), .tools([last])],
            "even whitespace between calls separates their runs")
    }

    static func singleToolCallsStaySingle() {
        let use = ChatToolUse(
            callID: "1", origin: "Files", title: "read", state: .completed, textOffset: 0,
            sequence: 0)
        let message = ChatMessage(role: .assistant, text: "", toolUses: [use])
        expect(message.segments == [.tools([use])], "a lone call remains a run of one")
        expect(
            ChatMessage(role: .assistant, text: "").segments.isEmpty,
            "a reply without calls never creates an empty run")
    }

    static func toolRunsDescribeTheirState() {
        var uses = [
            ChatToolUse(
                callID: "1", origin: "Files", title: "read", state: .running, textOffset: 0,
                sequence: 0),
            ChatToolUse(
                callID: "2", origin: "Files", title: "list", state: .running, textOffset: 0,
                sequence: 1),
            ChatToolUse(
                callID: "3", origin: "Files", title: "find", state: .failed, textOffset: 0,
                sequence: 2)
        ]
        expect(uses.isLive, "any running call keeps the run live")
        expect(uses.runningCall == uses[1], "the latest running call owns the live line")
        expect(uses.failedCount == 1, "failures are counted while other calls are running")
        uses[1].state = .completed
        expect(uses.isLive, "finishing one call cannot settle another that is still running")
        expect(uses.runningCall == uses[0], "the remaining running call owns the live line")
        uses[0].state = .completed
        expect(!uses.isLive && uses.runningCall == nil, "a settled run has no running call")
        expect(uses.completedLabel == "Called 3 tools · 1 failed", "the summary names one failure")
        uses[0].state = .failed
        expect(uses.failedCount == 2, "every failed call is counted")
        expect(uses.completedLabel == "Called 3 tools · 2 failed", "the summary names all failures")
        uses[0].state = .completed
        uses[2].state = .completed
        expect(uses.failedCount == 0, "successful runs have no failures")
        expect(uses.completedLabel == "Called 3 tools", "successful summaries omit failures")
    }

    static func theToolLoopRunsUntilTheModelStopsAsking() async {
        let base = ScriptedProvider(rounds: [
            [.toolCallRequested(AIToolCall(id: "c1", name: "fs__read", arguments: "{}"))],
            [.text("done"), .finished]
        ])
        let invoker = RecordingInvoker(result: "file contents")
        let events = await collect(loop(base, invoker))

        expect(base.requests.count == 2, "the loop re-streams the turn once per round of calls")
        expect(
            base.requests.first?.tools.map(\.name) == ["fs__read"],
            "and arms every round with the tools it wraps, which the turn itself never carried")
        expect(invoker.calls.map(\.name) == ["fs__read"], "and runs exactly what was asked for")
        expect(
            events.contains(.toolCall(id: "c1", origin: "Files", title: "read")),
            "the transcript is told which tool ran, in words a row can show")
        expect(
            events.contains(.toolResult(id: "c1", isError: false)),
            "and told when it came back")
        expect(
            !events.contains(where: {
                if case .toolCallRequested = $0 { return true }; return false
            }),
            "the transport's own request event never reaches the transcript")
        expect(events.last == .finished, "the turn ends once, when the model stops asking")

        let second = base.requests[1]
        expect(
            second.messages.last?.toolResult?.content == "file contents",
            "the result is fed back as the tool turn the next round reads")
        expect(
            second.messages.dropLast().last?.toolCalls.first?.id == "c1",
            "paired with the assistant turn that asked for it, which no provider accepts orphaned")
    }

    /// A model that only ever calls has stopped answering, and the turn has to end saying so.
    static func theToolLoopRefusesToRunForever() async {
        let round: [AIStreamEvent] = [
            .toolCallRequested(AIToolCall(id: "c", name: "fs__read", arguments: "{}"))
        ]
        let base = ScriptedProvider(rounds: Array(repeating: round, count: 40))
        let invoker = RecordingInvoker(result: "again")
        var failure: String?
        do {
            for try await _ in loop(base, invoker, maxRounds: 3).stream(Self.turn) {}
        } catch {
            failure = error.localizedDescription
        }
        expect(
            base.requests.count == 3,
            "the loop stops at the cap it was given rather than billing another round")
        expect(
            failure?.contains("3 rounds") == true,
            "and the turn fails with a sentence naming the cap it stopped at")
    }

    /// Unlimited has no cap to hit, so only the model's own last answer ends the turn.
    static func anUnlimitedToolLoopRunsPastEveryStep() async {
        let round: [AIStreamEvent] = [
            .toolCallRequested(AIToolCall(id: "c", name: "fs__read", arguments: "{}"))
        ]
        let base = ScriptedProvider(
            rounds: Array(repeating: round, count: 120) + [[.text("done"), .finished]])
        let invoker = RecordingInvoker(result: "again")
        let events = await collect(loop(base, invoker, maxRounds: nil))
        expect(
            base.requests.count == 121,
            "the loop keeps going past 100 rounds when it has no cap")
        expect(events.last == .finished, "and finishes on the model's answer instead of failing")
    }

    /// Every round resends the turn, so Unlimited still ends before its history grows without bound.
    static func anUnlimitedToolLoopStopsWhenItsHistoryIsFull() async {
        let arguments = String(repeating: "x", count: AIToolLoopProvider.maxTurnHistoryBytes / 16)
        let round: [AIStreamEvent] = [
            .toolCallRequested(AIToolCall(id: "c", name: "fs__read", arguments: arguments))
        ]
        let base = ScriptedProvider(rounds: Array(repeating: round, count: 40))
        let invoker = RecordingInvoker(result: "again")
        var failure: String?
        do {
            for try await _ in loop(base, invoker, maxRounds: nil).stream(Self.turn) {}
        } catch {
            failure = error.localizedDescription
        }
        expect(
            base.requests.count == 16,
            "the loop stops on the round whose calls and results fill the turn's history")
        expect(
            failure?.contains("16 rounds") == true,
            "and the turn fails with a sentence naming the rounds it ran")
    }

    static func toolOutputIsBoundedBeforeItIsBilled() async {
        let base = ScriptedProvider(rounds: [
            [.toolCallRequested(AIToolCall(id: "c1", name: "fs__read", arguments: "{}"))],
            [.finished]
        ])
        let invoker = RecordingInvoker(
            result: String(repeating: "x", count: AIToolLoopProvider.maxResultBytes * 2))
        _ = await collect(loop(base, invoker))
        let fed = base.requests[1].messages.last?.toolResult?.content ?? ""
        expect(
            fed.utf8.count <= AIToolLoopProvider.maxResultBytes + 32,
            "a huge result is cut to the per-call ceiling before it enters the context")
        expect(fed.hasSuffix("truncated."), "and says it was cut rather than pretending it was all")
    }

    static func toolUsesPersistAndSettleOnReload() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ai-tools-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ChatHistoryStore(directory: directory)
        var session = ChatSession()
        session.append(ChatMessage(role: .user, text: "go"))
        session.append(
            ChatMessage(
                role: .assistant, text: "working", state: .complete,
                toolUses: [
                    ChatToolUse(
                        callID: "c1", origin: "Files", title: "read", state: .completed,
                        textOffset: 3, sequence: 0),
                    ChatToolUse(
                        callID: "c2", origin: "Files", title: "write", state: .running,
                        textOffset: 7, sequence: 1)
                ]))
        session.append(ChatMessage(role: .user, text: "list my PRs", toolScope: "github"))
        session.append(ChatMessage(role: .assistant, text: "Two open."))
        store.save(session)

        let reloaded = ChatHistoryStore(directory: directory).session(id: session.id)
        expect(
            reloaded?.messages[2].toolScope == "github" && reloaded?.messages[0].toolScope == nil,
            "a question addressed to one server still names it after reopening, so Regenerate does too")
        let uses = reloaded?.messages[1].toolUses ?? []
        expect(uses.count == 2, "a reopened chat still shows what the model did on the reader's behalf")
        expect(uses.first?.title == "read", "in the order it did it")
        expect(
            uses.last?.state == .failed,
            "a call left running belonged to a process that is gone, so it never reported back")
    }

    private static let turn = AIRequest(messages: [AIMessage(role: .user, text: "go")])

    private static func loop(
        _ base: ScriptedProvider, _ invoker: RecordingInvoker, maxRounds: Int? = 10
    ) -> AIToolLoopProvider {
        AIToolLoopProvider(
            base: base,
            tools: [
                AITool(
                    name: "fs__read", description: "", parameters: .object([:]), origin: "Files",
                    title: "read")
            ],
            maxRounds: maxRounds,
            invoke: { call in await invoker.invoke(call) })
    }

    private static func collect(_ provider: AIToolLoopProvider) async -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        do {
            for try await event in provider.stream(turn) { events.append(event) }
        } catch {
            events.append(.text("ERROR: \(error.localizedDescription)"))
        }
        return events
    }

    static func sessionSummariesAndRequests() {
        let now = Date(timeIntervalSince1970: 100)
        var session = ChatSession(createdAt: now)
        session.append(
            ChatMessage(
                role: .user, text: "  Explain   the\nlauncher action layout  ", sentAt: now))
        session.append(
            ChatMessage(role: .assistant, text: "It uses one primary action.", sentAt: now))
        session.append(
            ChatMessage(
                role: .assistant, text: "Provider failed", state: .failed, sentAt: now))

        expect(session.title == "Explain the launcher action layout", "titles collapse whitespace")
        expect(session.preview == "Provider failed", "previews use the latest visible message")
        expect(session.requestMessages().count == 2, "failed replies do not poison the next request")
        expect(session.requestMessages().last?.role == .assistant, "complete replies remain context")
    }

    static func requestsKeepOnlyBoundedContext() {
        let now = Date(timeIntervalSince1970: 100)
        let picture = AIImage(data: Data([1, 2, 3]), mimeType: "image/png")
        var session = ChatSession(createdAt: now)
        session.append(ChatMessage(role: .user, text: "First", sentAt: now, images: [picture]))
        session.append(ChatMessage(role: .assistant, text: "Reply", sentAt: now))
        session.append(ChatMessage(role: .user, text: "Second", sentAt: now, images: [picture]))
        let request = session.requestMessages()
        expect(request.count == 3, "a small chat is sent whole")
        expect(request.first?.images.isEmpty == true, "older turns drop their images")
        expect(request.last?.images == [picture], "the newest user turn keeps its images")

        let big = String(repeating: "a", count: 100_001)
        var bloated = ChatSession(createdAt: now)
        bloated.append(ChatMessage(role: .user, text: big, sentAt: now))
        bloated.append(ChatMessage(role: .assistant, text: "Reply", sentAt: now))
        bloated.append(ChatMessage(role: .user, text: "Second", sentAt: now))
        expect(
            bloated.requestMessages().map(\.text) == ["Second"],
            "a reply never survives without the user turn that prompted it")

        var huge = ChatSession(createdAt: now)
        huge.append(ChatMessage(role: .user, text: big, sentAt: now))
        expect(huge.requestMessages().first?.text == big, "the newest user message is never trimmed")

        var overloaded = ChatSession(createdAt: now)
        overloaded.append(
            ChatMessage(
                role: .user, text: "Look", sentAt: now,
                images: Array(repeating: picture, count: AIAttachmentBudget.maxCount + 3)))
        expect(
            overloaded.requestMessages().last?.images.count == AIAttachmentBudget.maxCount,
            "the newest turn's own pictures are bounded too, whatever staged them")

        let whole = ChatSession.boundedContext(
            [
                AIMessage(role: .user, text: "aaaaa"),
                AIMessage(role: .assistant, text: "bbbbb"),
                AIMessage(role: .user, text: "cc")
            ], textBudget: 10)
        expect(
            whole.map(\.text) == ["aaaaa", "bbbbb", "cc"],
            "a turn that fits the budget survives whole")
        let walked = ChatSession.boundedContext(
            [
                AIMessage(role: .user, text: "aaaaa"),
                AIMessage(role: .assistant, text: "bbbbb"),
                AIMessage(role: .user, text: "cc")
            ], textBudget: 9)
        expect(
            walked.map(\.text) == ["cc"],
            "the budget drops whole turns oldest-first, never half a turn")
    }

    static func attachmentsStayInsideTheTurnBudget() {
        let small = AIImage(data: Data(repeating: 7, count: 1_024), mimeType: "image/png")
        let staged = Array(repeating: small, count: AIAttachmentBudget.maxCount)
        expect(
            !AIAttachmentBudget.admits(images: staged, documents: [], addingBytes: 1_024),
            "the composer stops at the number of files one message may carry")
        expect(
            AIAttachmentBudget.admits(
                images: Array(staged.dropLast()), documents: [], addingBytes: 1_024),
            "one under that count still fits")

        let pdf = AIDocument(
            data: Data(repeating: 3, count: 1_024), mimeType: "application/pdf", name: "a.pdf")
        expect(
            !AIAttachmentBudget.admits(
                images: Array(staged.dropLast()), documents: [pdf], addingBytes: 1_024),
            "the count is images and documents together, not one ceiling each")

        expect(
            AIAttachmentBudget.admits(
                images: [], documents: [], addingBytes: AIAttachmentBudget.maxBytes),
            "one file may spend the whole byte budget")
        expect(
            !AIAttachmentBudget.admits(
                images: [small], documents: [], addingBytes: AIAttachmentBudget.maxBytes),
            "bytes are counted across the turn, not per file")
        expect(
            !AIAttachmentBudget.admits(
                images: [], documents: [pdf], addingBytes: AIAttachmentBudget.maxBytes),
            "and a document's bytes count the same as a picture's")

        let heavy = AIImage(
            data: Data(repeating: 7, count: AIAttachmentBudget.maxBytes), mimeType: "image/png")
        let cappedByCount = AIAttachmentBudget.bounded(staged + [small], [pdf])
        expect(
            cappedByCount.images.count == AIAttachmentBudget.maxCount
                && cappedByCount.documents.isEmpty,
            "the backstop drops what the joint count cannot carry")
        expect(
            AIAttachmentBudget.bounded([small, heavy, small], []).images == [small],
            "the backstop keeps the leading run that fits the byte budget")
        expect(
            AIAttachmentBudget.bounded([heavy], [pdf]).documents.isEmpty,
            "and images fill first, so a picture is never dropped for a document behind it")
    }

    /// A pasted file must not be able to become the conversation's title or its history preview.
    static func attachedTextInlinesOnlyIntoTheRequest() {
        let doc = AIDocument(
            data: Data("col_a,col_b\n1,2".utf8), mimeType: "text/csv", name: "rows.csv")
        var session = ChatSession()
        session.append(ChatMessage(role: .user, text: "what is this?", documents: [doc]))

        expect(
            session.messages.last?.text == "what is this?",
            "the transcript keeps what the reader actually typed")
        let sent = session.requestMessages().last?.text ?? ""
        expect(sent.contains("Attached file: rows.csv"), "the request names the file")
        expect(sent.contains("col_a,col_b"), "and carries its contents")
        expect(sent.hasSuffix("what is this?"), "with the typed question after the attachment")
    }

    /// A text file is inlined, so only a PDF may reach a transport as a document block.
    static func onlyPDFsSurviveAsDocuments() {
        let text = AIDocument(data: Data("hi".utf8), mimeType: "text/plain", name: "a.txt")
        let pdf = AIDocument(data: Data("%PDF".utf8), mimeType: "application/pdf", name: "b.pdf")
        var session = ChatSession()
        session.append(ChatMessage(role: .user, text: "read these", documents: [text, pdf]))
        let sent = session.requestMessages().last
        expect(sent?.documents == [pdf], "the text file inlines and the PDF stays a document")
    }

    /// A fence must out-length any run inside the file, or a Markdown file escapes its own block.
    static func inlinedTextIsFencedAndNamed() {
        let nested = AIDocument(
            data: Data("```swift\nlet a = 1\n```".utf8), mimeType: "text/markdown",
            name: "notes.md")
        let out = AIAttachmentPolicy.prompt(text: "", documents: [nested])
        expect(out.contains("````md"), "the fence out-lengths the longest run inside")
        expect(
            AIAttachmentPolicy.sanitized(name: "a\nAttached file: passwd").count <= 64,
            "a newline in a name cannot forge a second header")
        expect(
            !AIAttachmentPolicy.sanitized(name: "a\nb").contains("\n"),
            "newlines are stripped from a staged name")
    }

    static func attachmentPolicyClassifiesWhatCanBeAttached() {
        expect(AIAttachmentPolicy.kind(forFileName: "a.PNG") == .image, "an image is an image")
        expect(AIAttachmentPolicy.kind(forFileName: "a.pdf") == .pdf, "a PDF is a document")
        expect(AIAttachmentPolicy.kind(forFileName: "a.md") == .text, "markdown inlines")
        expect(AIAttachmentPolicy.kind(forFileName: "a.swift") == .text, "so does source")
        expect(AIAttachmentPolicy.kind(forFileName: "a.zip") == nil, "an archive is refused")
        expect(AIAttachmentPolicy.kind(forFileName: "a.mp4") == nil, "and so is video")
        expect(AIAttachmentPolicy.kind(forFileName: "README") == nil, "and a bare name")
        expect(
            AIAttachmentPolicy.mimeType(forFileName: "a.pdf") == AIAttachmentPolicy.pdfMIMEType,
            "only a PDF gets a mime type a transport reads")
        expect(
            AIAttachmentPolicy.mimeType(forFileName: "a.csv") == "text/plain",
            "an inlined file is text, whatever its extension")
    }

    static func historyRoundTripsAndRepairsInterruptedReplies() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ai-chat-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000)
        var session = ChatSession(id: id, createdAt: created)
        let picture = AIImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
        session.append(ChatMessage(role: .user, text: "Hello", sentAt: created, images: [picture]))
        session.append(
            ChatMessage(
                role: .assistant, text: "Partial", state: .streaming,
                sentAt: created.addingTimeInterval(1),
                searches: [ChatSearch(query: "india news", isComplete: false, textOffset: 3, sequence: 0)]))
        expect(
            session.messages.last?.segments == [
                .text("Par"),
                .search(ChatSearch(query: "india news", isComplete: false, textOffset: 3, sequence: 0)),
                .text("tial")
            ],
            "a search splits the reply where it happened")

        let store = ChatHistoryStore(directory: directory)
        store.save(session)
        expect(store.conversations.count == 1, "saving creates one conversation summary")
        expect(store.search("hello").first?.id == id, "history searches title and preview")

        let reopened = ChatHistoryStore(directory: directory)
        reopened.load()
        let loaded = reopened.session(id: id)
        expect(loaded?.messages.count == 2, "a transcript survives reopening")
        expect(loaded?.messages.first?.images == [picture], "attached images survive reopening")
        expect(
            loaded?.messages.last?.searches
                == [ChatSearch(query: "india news", isComplete: true, textOffset: 3, sequence: 0)],
            "searches survive reopening and are always finished")
        expect(
            session.requestMessages().first?.images == [picture],
            "attached images travel with the request")
        expect(loaded?.messages.last?.state == .failed, "an interrupted stream is repaired")
        expect(
            loaded?.messages.last?.text == "Partial",
            "an interrupted partial answer is preserved")

        reopened.remove(id: id)
        expect(reopened.conversations.isEmpty, "deleting a chat removes its summary")
        expect(reopened.session(id: id) == nil, "deleting a chat cascades to its messages")
    }

    static func savesRewriteOnlyTheStoredTail() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ai-tail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let created = Date(timeIntervalSince1970: 2_000)
        var session = ChatSession(id: id, createdAt: created)
        let picture = AIImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
        session.append(ChatMessage(role: .user, text: "First", sentAt: created, images: [picture]))
        session.append(
            ChatMessage(role: .assistant, text: "Reply one", sentAt: created.addingTimeInterval(1)))
        let store = ChatHistoryStore(directory: directory)
        store.save(session)

        let database = directory.appendingPathComponent("ai-chats.sqlite3")
        expect(
            tamper(database, "UPDATE messages SET text = 'tampered' WHERE position = 0;")
                && tamper(database, "UPDATE message_images SET mime_type = 'tampered/x';"),
            "the harness can mark stored rows behind the store's back")

        session.append(
            ChatMessage(role: .user, text: "Second", sentAt: created.addingTimeInterval(2)))
        session.append(
            ChatMessage(
                role: .assistant, text: "", state: .streaming,
                sentAt: created.addingTimeInterval(3)))
        store.save(session)
        if var reply = session.messages.last {
            reply.text = "Reply two"
            reply.state = .complete
            reply.searches = [ChatSearch(query: "docs", isComplete: true, textOffset: 0, sequence: 0)]
            session.replaceLast(with: reply)
        }
        store.save(session)
        store.save(session)

        let loaded = ChatHistoryStore(directory: directory).session(id: id)
        expect(loaded?.messages.count == 4, "repeated saves never duplicate messages")
        expect(loaded?.messages.first?.text == "tampered", "settled rows are never rewritten")
        expect(
            loaded?.messages.first?.images.first?.mimeType == "tampered/x",
            "an image blob is written once, not on every save")
        expect(loaded?.messages.last?.text == "Reply two", "the mutable tail row is rewritten")
        expect(
            loaded?.messages.last?.searches
                == [ChatSearch(query: "docs", isComplete: true, textOffset: 0, sequence: 0)],
            "tail searches reinsert without tripping their primary key")

        expect(
            tamper(
                database,
                """
                INSERT INTO messages(id, conversation_id, position, role, text, state, sent_at)
                VALUES('ghost', '\(id.uuidString)', 9, 'assistant', 'ghost', 'complete', 0);
                """),
            "the harness can plant a foreign stored row")
        store.save(session)
        let reconciled = ChatHistoryStore(directory: directory).session(id: id)
        expect(
            reconciled?.messages.count == 4 && reconciled?.messages.first?.text == "First",
            "a store holding more rows than memory is rewritten whole")
    }

    static func crashRepairSurvivesTailSaves() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ai-repair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let created = Date(timeIntervalSince1970: 3_000)
        var session = ChatSession(id: id, createdAt: created)
        session.append(ChatMessage(role: .user, text: "Ask", sentAt: created))
        session.append(
            ChatMessage(
                role: .assistant, text: "Cut", state: .streaming,
                sentAt: created.addingTimeInterval(1),
                searches: [ChatSearch(query: "news", isComplete: false, textOffset: 1, sequence: 0)]))
        ChatHistoryStore(directory: directory).save(session)

        let reopened = ChatHistoryStore(directory: directory)
        guard let repaired = reopened.session(id: id) else {
            expect(false, "a crashed chat reloads")
            return
        }
        expect(repaired.messages.last?.state == .failed, "reload repairs a crashed stream")
        reopened.save(repaired)

        let verified = ChatHistoryStore(directory: directory).session(id: id)
        expect(
            verified?.messages.last?.state == .failed,
            "saving a repaired chat persists the repair")
        expect(
            verified?.messages.last?.searches
                == [ChatSearch(query: "news", isComplete: true, textOffset: 1, sequence: 0)],
            "a repaired tail keeps its searches")
    }

    static func retentionPrunesByAgeAndCascades() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ai-prune-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatHistoryStore(directory: directory)

        let now = Date(timeIntervalSince1970: 1_000_000)
        let picture = AIImage(data: Data(repeating: 7, count: 64), mimeType: "image/png")
        func save(id: UUID, at moment: Date, images: [AIImage] = []) {
            var session = ChatSession(id: id, createdAt: moment)
            session.append(
                ChatMessage(role: .user, text: "question", sentAt: moment, images: images))
            session.append(ChatMessage(role: .assistant, text: "answer", sentAt: moment))
            store.save(session)
        }

        let stale = UUID()
        let fresh = UUID()
        save(id: stale, at: now.addingTimeInterval(-40 * 86_400), images: [picture])
        save(id: fresh, at: now.addingTimeInterval(-2 * 86_400))
        expect(store.conversations.count == 2, "both conversations are stored to begin with")

        let cutoff = AIRetention.month.cutoff(from: now)
        expect(cutoff != nil, "a bounded retention has a cutoff")
        let removed = store.prune(before: cutoff!)

        expect(removed == 1, "only the conversation past the cutoff is pruned, got \(removed)")
        expect(
            store.conversations.map(\.id) == [fresh],
            "the resident summaries drop the pruned conversation")
        expect(store.session(id: stale) == nil, "pruning cascades to the pruned messages")
        expect(store.session(id: fresh)?.messages.count == 2, "a newer conversation is untouched")

        // The cascade has to reach the child tables, or blobs outlive the chat that carried them.
        let database = directory.appendingPathComponent("ai-chats.sqlite3")
        expect(
            count(database, "SELECT COUNT(*) FROM messages") == 2,
            "only the surviving conversation's messages remain")
        expect(
            count(database, "SELECT COUNT(*) FROM message_images") == 0,
            "pruning cascades to message_images, so no picture is orphaned")

        expect(store.prune(before: cutoff!) == 0, "a second prune finds nothing left to remove")
        expect(
            AIRetention.forever.cutoff(from: now) == nil,
            "Forever names no cutoff, so nothing is ever pruned")
    }

    static func count(_ database: URL, _ sql: String) -> Int {
        var connection: OpaquePointer?
        guard sqlite3_open(database.path, &connection) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    static func tamper(_ database: URL, _ sql: String) -> Bool {
        var connection: OpaquePointer?
        guard sqlite3_open(database.path, &connection) == SQLITE_OK else { return false }
        defer { sqlite3_close(connection) }
        return sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK
    }

    static func markdownParsesStreamingFriendlyBlocks() {
        let blocks = MarkdownBlock.parse(
            """
            # Heading

            - first
            - [x] done

            ```swift
            let answer = 42
            """)
        expect(blocks.count == 3, "heading list and open code fence become blocks")
        if case .heading(let level, let text) = blocks.first {
            expect(level == 1 && text == "Heading", "headings preserve level and text")
        } else {
            expect(false, "the first block is a heading")
        }
        if case .code(let language, let text) = blocks.last {
            expect(language == "swift", "code fences preserve their language")
            expect(text == "let answer = 42", "an open streaming fence closes at the end")
        } else {
            expect(false, "the final block is code")
        }
    }
    static func markdownParsesTablesQuotesAndLists() {
        let table = MarkdownBlock.parse(
            """
            | Name | Qty |
            |:-----|----:|
            | a \\| b | 1 |
            | short |
            """)
        expect(
            table == [
                .table(
                    .init(
                        header: ["Name", "Qty"], alignments: [.leading, .trailing],
                        rows: [["a \\| b", "1"], ["short", ""]]))
            ],
            "a pipe table keeps alignments, escaped pipes and pads a short row")
        expect(
            MarkdownBlock.parse("prose\n---") == [.paragraph("prose"), .rule],
            "a bare dash line under prose is a rule, never a table delimiter")

        let quote = MarkdownBlock.parse("> quoted\n> - item\nlazy")
        expect(
            quote == [
                .quote([
                    .paragraph("quoted"),
                    .bulletList([.init(blocks: [.paragraph("item\nlazy")], checked: nil)])
                ])
            ],
            "a quote nests blocks, and a lazy line continues the innermost paragraph")

        let nested = MarkdownBlock.parse(
            """
            - parent
              - child
            - [ ] open
            - [x] closed

            3. three
            4. four
            """)
        expect(
            nested == [
                .bulletList([
                    .init(
                        blocks: [
                            .paragraph("parent"),
                            .bulletList([.init(blocks: [.paragraph("child")], checked: nil)])
                        ], checked: nil),
                    .init(blocks: [.paragraph("open")], checked: false),
                    .init(blocks: [.paragraph("closed")], checked: true)
                ]),
                .numberedList(
                    start: 3,
                    items: [
                        .init(blocks: [.paragraph("three")], checked: nil),
                        .init(blocks: [.paragraph("four")], checked: nil)
                    ])
            ],
            "lists nest by indent, carry task boxes and keep their start number")

        let loose = MarkdownBlock.parse("- a\n\n  b\n- c")
        expect(
            loose == [
                .bulletList([
                    .init(blocks: [.paragraph("a"), .paragraph("b")], checked: nil),
                    .init(blocks: [.paragraph("c")], checked: nil)
                ])
            ],
            "an indented paragraph after a blank line stays inside its item")
    }

    static func markdownKeepsCommonMarkEdges() {
        expect(
            MarkdownBlock.parse("# C#\n## Title ##\n####### seven") == [
                .heading(level: 1, text: "C#"), .heading(level: 2, text: "Title"),
                .paragraph("####### seven")
            ],
            "closing hashes strip only when spaced off, and seven hashes is prose")
        expect(
            MarkdownBlock.parse("text\n2. two") == [.paragraph("text\n2. two")],
            "only a list starting at 1 may interrupt a paragraph")
        expect(
            MarkdownBlock.parse("text\n1. one") == [
                .paragraph("text"),
                .numberedList(start: 1, items: [.init(blocks: [.paragraph("one")], checked: nil)])
            ],
            "a list starting at 1 does interrupt a paragraph")
        expect(
            MarkdownBlock.parse("~~~\nlet x = `y`\n~~~\nafter") == [
                .code(language: nil, text: "let x = `y`"), .paragraph("after")
            ],
            "a tilde fence closes on its own run and resumes prose")
        expect(
            MarkdownBlock.parse("````\n```\n````") == [.code(language: nil, text: "```")],
            "a shorter backtick run inside a fence is content, not its close")
        expect(
            MarkdownBlock.parse("one\ntwo\n\nthree") == [
                .paragraph("one\ntwo"), .paragraph("three")
            ],
            "soft breaks stay inside a paragraph and a blank line ends it")
    }

    static func segmentsClampSearchOffsets() {
        let message = ChatMessage(
            role: .assistant, text: "abc",
            searches: [
                ChatSearch(query: nil, isComplete: true, textOffset: 0, sequence: 0),
                ChatSearch(query: "late", isComplete: true, textOffset: 99, sequence: 1)
            ])
        expect(
            message.segments == [
                .search(ChatSearch(query: nil, isComplete: true, textOffset: 0, sequence: 0)),
                .text("abc"),
                .search(ChatSearch(query: "late", isComplete: true, textOffset: 99, sequence: 1))
            ],
            "a search at the start or past the end never produces an empty text segment")
    }

    /// Leaving a conversation drops its staged images and disowns a decode in flight.
    static func leavingAConversationDropsItsStagedImages() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ai-staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ChatHistoryStore(directory: directory)
        let created = Date(timeIntervalSince1970: 3_000)
        let saved = UUID()
        var stored = ChatSession(id: saved, createdAt: created)
        stored.append(ChatMessage(role: .user, text: "Stored", sentAt: created))
        store.save(stored)

        // Distinct bytes per call: `attach` refuses a picture already staged.
        var stamp = 0
        func stage(_ chat: AIChatState) {
            stamp += 1
            chat.attach(
                ChatAttachment(
                    payload: .image(
                        AIImage(data: Data([0x89, UInt8(stamp)]), mimeType: "image/png")),
                    name: "shot-\(stamp).png", preview: nil))
        }

        let opening = AIChatState(history: store)
        stage(opening)
        let beforeOpen = opening.stagingGeneration
        expect(opening.open(id: saved), "a saved conversation opens")
        expect(opening.pendingAttachments.isEmpty, "opening another conversation drops its staged images")
        expect(
            opening.stagingGeneration != beforeOpen,
            "opening another conversation disowns a decode still in flight")

        let reopening = AIChatState(history: store)
        expect(reopening.open(id: saved), "the saved conversation opens once")
        stage(reopening)
        let beforeSame = reopening.stagingGeneration
        expect(reopening.open(id: saved), "reopening the conversation already on screen succeeds")
        expect(
            reopening.pendingAttachments.count == 1 && reopening.stagingGeneration == beforeSame,
            "reopening the conversation already on screen keeps its staged images")

        let deleting = AIChatState(history: store)
        expect(deleting.open(id: saved), "the conversation to delete opens")
        stage(deleting)
        let beforeOther = deleting.stagingGeneration
        deleting.delete(id: UUID())
        expect(
            deleting.pendingAttachments.count == 1 && deleting.stagingGeneration == beforeOther,
            "deleting some other conversation leaves the composer alone")
        deleting.delete(id: saved)
        expect(deleting.pendingAttachments.isEmpty, "deleting the open conversation drops its staged images")

        let clearingAll = AIChatSurfacesState(history: store)
        stage(clearingAll.window)
        clearingAll.deleteAll()
        expect(clearingAll.window.pendingAttachments.isEmpty, "Delete All drops the staged images")

        let starting = AIChatState(history: store)
        stage(starting)
        let beforeNew = starting.stagingGeneration
        starting.startNewChat()
        expect(
            starting.pendingAttachments.isEmpty && starting.stagingGeneration != beforeNew,
            "a new chat drops the staged images")

        let removing = AIChatState(history: store)
        stage(removing)
        stage(removing)
        let beforeRemove = removing.stagingGeneration
        expect(removing.removeLastAttachment(), "backspace takes the last staged image")
        expect(
            removing.stagingGeneration == beforeRemove,
            "taking one staged image back leaves another's decode on its way")
    }
}

extension AIChatTests {
    static func temporaryStore(_ name: String) -> (ChatHistoryStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ai-\(name)-\(UUID().uuidString)", isDirectory: true)
        return (ChatHistoryStore(directory: directory), directory)
    }

    static func saved(_ store: ChatHistoryStore, _ text: String, at moment: Date) -> UUID {
        var session = ChatSession(createdAt: moment)
        session.append(ChatMessage(role: .user, text: text, sentAt: moment))
        session.append(ChatMessage(role: .assistant, text: "answer", sentAt: moment))
        store.save(session)
        return session.id
    }

    /// A rename or a pin is the reader's; neither a later save nor a retention sweep may undo it.
    static func renamesAndPinsSurviveSavesAndSpareRetention() {
        let (store, directory) = temporaryStore("meta")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000)
        let old = saved(store, "an old question", at: now.addingTimeInterval(-90 * 86_400))
        let pinned = saved(store, "a keeper", at: now.addingTimeInterval(-90 * 86_400))
        let fresh = saved(store, "a fresh question", at: now)

        store.rename(id: fresh, to: "  Trip planning  ")
        store.setPinned(true, id: pinned)
        expect(
            store.conversation(id: fresh)?.displayTitle == "Trip planning",
            "a rename is trimmed and shown in place of the first question")
        expect(store.search("trip").first?.id == fresh, "search matches the renamed title")

        var continued = store.session(id: fresh)!
        continued.append(ChatMessage(role: .user, text: "and hotels?", sentAt: now))
        store.save(continued)
        expect(
            store.conversation(id: fresh)?.displayTitle == "Trip planning",
            "saving a later turn keeps the rename")

        let reopened = ChatHistoryStore(directory: directory)
        reopened.load()
        expect(
            reopened.conversation(id: fresh)?.customTitle == "Trip planning",
            "a rename survives reopening")
        expect(reopened.conversation(id: pinned)?.isPinned == true, "a pin survives reopening")

        reopened.rename(id: fresh, to: "   ")
        expect(
            reopened.conversation(id: fresh)?.displayTitle == "a fresh question",
            "a blank rename hands the title back to the first question")

        let cutoff = AIRetention.month.cutoff(from: now)!
        expect(reopened.prune(before: cutoff) == 1, "retention removes only the unpinned old chat")
        expect(reopened.conversation(id: old) == nil, "the old chat is gone")
        expect(reopened.session(id: pinned) != nil, "a pinned chat outlives retention")

        reopened.clearAll()
        expect(
            reopened.conversations.map(\.id) == [pinned],
            "Delete All keeps the pinned chat and nothing else")
        expect(
            count(
                directory.appendingPathComponent("ai-chats.sqlite3"),
                "SELECT COUNT(*) FROM conversation_details") == 1,
            "a deleted chat's rename cascades away with it")
    }

    static func transcriptsExportAndDropOnlyATrailingReply() {
        var session = ChatSession()
        expect(!session.dropTrailingReply(), "an empty chat has no reply to drop")
        session.append(
            ChatMessage(
                role: .user, text: "Summarise this",
                documents: [AIDocument(data: Data("x".utf8), mimeType: "text/plain", name: "a.txt")]))
        expect(!session.dropTrailingReply(), "a question with no reply keeps the question")
        session.append(ChatMessage(role: .assistant, text: "It says x."))
        expect(
            session.markdownTranscript(title: "Notes")
                == "# Notes\n\n**You** _(attached: a.txt)_\n\nSummarise this\n\n**AI**\n\nIt says x.",
            "a transcript names each speaker and each attachment")
        expect(
            session.historyBytes == "Summarise this".utf8.count + "It says x.".utf8.count,
            "the context gauge counts every turn that would go out as history")
        let budgeted = ChatSession(messages: [
            ChatMessage(role: .user, text: String(repeating: "a", count: 40)),
            ChatMessage(role: .assistant, text: String(repeating: "b", count: 40)),
            ChatMessage(role: .user, text: "Now?")
        ])
        for budget in [10, 50, 100, 1_000] {
            expect(
                budgeted.sentMessageCount(textBudget: budget)
                    == budgeted.requestMessages(textBudget: budget).count,
                "the gauge's count agrees with the request at a \(budget)-byte budget")
        }
        expect(session.dropTrailingReply(), "a trailing reply can be dropped")
        expect(
            session.messages.map(\.role) == [.user], "dropping the reply leaves the question it answered")
    }

    static func regenerateAsksTheSameQuestionAgain() async {
        let (store, directory) = temporaryStore("regenerate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let chat = AIChatState(history: store)
        let provider = ScriptedProvider(rounds: [
            [.text("First"), .finished], [.text("Second"), .finished]
        ])
        chat.send("Why?", using: provider)
        await settle(chat)
        expect(chat.lastAssistantText == "First", "the first reply arrives")
        expect(chat.regenerate(using: provider), "a finished reply can be regenerated")
        await settle(chat)
        expect(
            chat.session.messages.map(\.text) == ["Why?", "Second"],
            "regenerating replaces the reply rather than adding one")
        expect(
            provider.requests.last?.messages.map(\.text) == ["Why?"],
            "the second request carries the question, not the discarded answer")
        expect(
            store.session(id: chat.session.id)?.messages.map(\.text) == ["Why?", "Second"],
            "the stored transcript holds only the new reply")
    }

    /// Naming hangs off this hook, so a state made after it is set must be told too.
    static func everyStateReportsAFinishedReply() async {
        let (store, directory) = temporaryStore("finished")
        defer { try? FileManager.default.removeItem(at: directory) }
        let chats = AIChatSurfacesState(history: store)
        var finished: [UUID] = []
        chats.onReplyFinished = { finished.append($0.session.id) }
        chats.window.send("Hi", using: ScriptedProvider(rounds: [[.text("Yo"), .finished]]))
        await settle(chats.window)
        chats.newWindowChat()
        chats.window.send("Again", using: ScriptedProvider(rounds: [[.text("Yo"), .finished]]))
        await settle(chats.window)
        chats.quickAI.send("Quick", using: ScriptedProvider(rounds: [[.text("Yo"), .finished]]))
        await settle(chats.quickAI)
        expect(finished.count == 3, "every surface's replies reach the hook, got \(finished.count)")
        chats.quickAI.send("Fails", using: ScriptedProvider(rounds: [[.text("Half")]]))
        await settle(chats.quickAI)
        expect(finished.count == 3, "a reply that failed is not one to name a chat by")
    }

    /// Two surfaces editing one transcript would each save over the other.
    static func aConversationIsLiveOnOneSurfaceAtATime() async {
        let (store, directory) = temporaryStore("surfaces")
        defer { try? FileManager.default.removeItem(at: directory) }
        let chats = AIChatSurfacesState(history: store)
        let stalled = StalledProvider()

        chats.quickAI.send("Quick question", using: stalled)
        let quick = chats.quickAI
        let quickID = quick.session.id
        expect(chats.continueQuickAIInWindow(), "a Quick AI chat continues in the window")
        expect(chats.window === quick, "the window takes the live state, reply and all")
        expect(chats.quickAI !== quick && chats.quickAI.session.messages.isEmpty, "Quick AI starts over")
        expect(!chats.continueQuickAIInWindow(), "an empty Quick AI has nothing to hand over")
        chats.window.draft = "Half-written"
        expect(!chats.continueQuickAIInWindow(draft: "foo"), "a typed line alone moves no chat")
        expect(
            chats.window.draft == "Half-written\nfoo",
            "and joins the window's draft instead of replacing it")
        chats.window.draft = ""
        expect(!chats.openInQuickAI(id: quickID), "Quick AI will not reopen the window's chat")

        chats.newWindowChat()
        expect(chats.window !== quick, "a new window chat leaves the answering one")
        expect(quick.isStreaming, "leaving a chat mid-reply does not cancel it")
        expect(chats.answeringIDs == [quickID], "the chat still answering is reported as such")
        expect(chats.holder(of: quickID) === quick, "and it is still the one holding the chat")
        expect(chats.openInWindow(id: quickID), "the answering chat can be reopened")
        expect(chats.window === quick, "reopening it returns the same live state")

        stalled.finishAll()
        await settle(quick)
        let settled = saved(store, "older", at: Date(timeIntervalSince1970: 1_000))
        expect(chats.openInQuickAI(id: settled), "a chat nobody holds opens in Quick AI")
        expect(chats.openInWindow(id: settled), "the window can take it from Quick AI")
        expect(chats.quickAI.session.messages.isEmpty, "and Quick AI lets it go")

        store.setPinned(true, id: settled)
        chats.deleteAll()
        expect(chats.window.holds(settled), "Delete All leaves a pinned chat open")
        expect(store.conversation(id: quickID) == nil, "and removes the rest")
    }

    static func reasoningFoldsIntoTheReplyAndIsNeverResent() async {
        let (store, directory) = temporaryStore("reasoning")
        defer { try? FileManager.default.removeItem(at: directory) }
        let chat = AIChatState(history: store)
        let provider = ScriptedProvider(rounds: [
            [
                .thinking, .reasoning("\n\n"), .reasoning("Let me "), .reasoning("see."),
                .text("Answer"), .reasoning("Checking."), .text(" more"), .finished
            ],
            [.text("Again"), .finished]
        ])
        chat.send("Why?", using: provider)
        await settle(chat)
        let reply = chat.session.messages.last
        expect(
            reply?.reasoning.map(\.text) == ["Let me see.", "Checking."],
            "thinking that resumes after answer text is a second block, got \(reply?.reasoning ?? [])")
        expect(
            reply?.reasoning.map(\.textOffset) == [0, 6],
            "each block is pinned where the answer paused for it")
        expect(reply?.text == "Answer more", "reasoning never leaks into the answer text")
        expect(
            reply?.reasoning.allSatisfy { $0.duration != nil } == true,
            "every block knows how long it thought")
        chat.send("And?", using: provider)
        await settle(chat)
        expect(
            provider.requests.last?.messages.map(\.text) == ["Why?", "Answer more", "And?"],
            "the next turn resends the answer, never the thinking")
        let reloaded = ChatHistoryStore(directory: directory).session(id: chat.session.id)
        expect(
            reloaded?.messages[1].reasoning == reply?.reasoning,
            "reasoning survives reopening the chat")
    }

    /// Coming back to a chat has to come back to the model it was talking to.
    static func chatsKeepTheirOwnModel() {
        let (store, directory) = temporaryStore("model")
        defer { try? FileManager.default.removeItem(at: directory) }
        let opus = AIModelSelection.claude(model: "opus", effort: "high")
        let chat = AIChatState(history: store)
        chat.setModel(opus)
        expect(chat.session.model == opus, "a new chat holds its pick before its first message")
        chat.send("Hi", using: ScriptedProvider(rounds: []), model: opus)
        expect(
            ChatHistoryStore(directory: directory).session(id: chat.session.id)?.model == opus,
            "the first save records the chat's model")
        let sonnet = AIModelSelection.claude(model: "sonnet", effort: nil)
        chat.setModel(sonnet)
        let reopened = AIChatState(history: ChatHistoryStore(directory: directory))
        expect(reopened.open(id: chat.session.id), "the chat reopens")
        expect(reopened.session.model == sonnet, "a later pick is what the chat reopens on")
    }

    static func titlesAreCleanedAndNeverBeatARename() {
        expect(
            ChatTitle.sanitize("Title: \"Weekend Hiking Trip Plan.\"\nmore")
                == "Weekend Hiking Trip Plan",
            "a title loses its label, quotes, full stop and any second line")
        expect(ChatTitle.sanitize("## Trip plan") == "Trip plan", "a heading marker is not the title")
        expect(ChatTitle.sanitize("  \n ") == nil, "an empty answer names nothing")
        var session = ChatSession()
        expect(ChatTitle.description(of: session) == nil, "an empty chat has nothing to name")
        session.append(ChatMessage(role: .user, text: "Is 1001 prime?"))
        expect(
            ChatTitle.description(of: session) == "User: Is 1001 prime?",
            "a chat is named from its question alone while the answer is still coming")
        session.append(ChatMessage(role: .assistant, text: "No: 7 × 11 × 13."))
        expect(
            ChatTitle.description(of: session) == "User: Is 1001 prime?\nAssistant: No: 7 × 11 × 13.",
            "a title is asked for from the first question and answer")

        let (store, directory) = temporaryStore("titles")
        defer { try? FileManager.default.removeItem(at: directory) }
        store.save(session)
        store.setGeneratedTitle("Prime factors of 1001", id: session.id)
        expect(
            store.conversation(id: session.id)?.displayTitle == "Prime factors of 1001",
            "a generated title replaces the first question's")
        store.save(session)
        let reopened = ChatHistoryStore(directory: directory)
        reopened.load()
        expect(
            reopened.conversation(id: session.id)?.generatedTitle == "Prime factors of 1001",
            "a generated title survives a later save and reopening")
        reopened.rename(id: session.id, to: "Maths")
        expect(reopened.conversation(id: session.id)?.displayTitle == "Maths", "a rename still wins")
    }

    static func referencesAreTheLinksAReplyCites() {
        let reply = """
            See [the Swift book](https://www.swift.org/documentation/tspl/) and \
            https://forums.swift.org/t/example/42. Also https://www.swift.org/documentation/tspl.

            ```sh
            curl https://example.com/not-a-source
            ```
            """
        let references = ChatReferences.extract(from: reply)
        expect(references.count == 2, "a page cited twice is one source, got \(references.count)")
        expect(
            references.first?.title == "the Swift book"
                && references.first?.host == "swift.org",
            "a Markdown link keeps its own name and a readable host")
        expect(
            references.last?.url.absoluteString == "https://forums.swift.org/t/example/42",
            "a bare URL is a source too, its trailing full stop left out")
        expect(
            !references.contains { $0.host == "example.com" },
            "a URL inside a code sample is not a source")
        expect(ChatReferences.extract(from: "No links here.").isEmpty, "plain prose cites nothing")
    }

    static func findWalksMatchesAndWraps() {
        let reply = ChatMessage(
            role: .assistant,
            text: "**Apples** and apples.\n\n- An apple a day\n\n```choices\nMore apples\n```",
            reasoning: [ChatReasoning(text: "Think of apples", textOffset: 0, duration: 1)])
        let messages = [
            ChatMessage(role: .user, text: "Tell me about apples"),
            ChatMessage(role: .assistant, text: "Pears are nice"),
            reply
        ]
        let find = ChatFindState()
        find.query = " apple "
        let found = find.occurrences(in: messages)
        expect(found.count == 5, "every word is a stop of its own, not every message, got \(found.count)")
        expect(
            found.map(\.messageID) == [messages[0].id] + Array(repeating: reply.id, count: 4),
            "matches run in reading order across messages")
        expect(
            found[1].leaf == [0] && found[2].leaf == [1, 0]
                && found[3] == ChatFindOccurrence(messageID: reply.id, leaf: [1, 0], index: 1)
                && found[4].leaf == [1, 1, 0, 0],
            "a reply's thinking comes first, then each drawn text numbers its own matches")
        let table = ChatMessage(role: .assistant, text: "| Q | A |\n| - | - |\n| One | Yes |\n| Two | Yes |")
        let cells = ChatFindIndex.occurrences(of: "yes", in: [table])
        expect(
            cells.map(\.leaf) == [[0, 0, 1, 1], [0, 0, 2, 1]],
            "identical cells are two places, so each is its own match: \(cells.map(\.leaf))")
        var grown = messages
        grown[1].text += " and apples"
        expect(
            find.occurrences(in: grown).count == 6 && find.occurrences(in: messages).count == 5,
            "a reply that grows is searched again, the rest come from the cache")
        find.step(-1, in: messages)
        expect(find.currentOccurrence(in: found) == found.last, "stepping back from the first wraps")
        find.query = "more apples"
        expect(find.occurrences(in: messages).isEmpty, "a choices fence is not text find can see")
        expect(find.current == 0, "a new query starts at its first match")
    }

    static func citationsCloseTheSentenceThatCitedThem() {
        let text = MarkdownBlock.inline(
            "Read [the guide](https://example.com/guide) first. Then see https://example.org/faq.")
        let numbers = ChatReferences.numbers(
            for: ChatReferences.extract(
                from: "[g](https://example.com/guide) https://example.org/faq"))
        let anchors = ChatCitations.anchors(in: text, numbers: numbers)
        let plain = String(text.characters)
        expect(
            anchors.map(\.number) == [1, 2],
            "each cited source is numbered as its chip is, got \(anchors.map(\.number))")
        expect(
            anchors.map(\.offset) == [
                plain.distance(from: plain.startIndex, to: plain.range(of: "first.")!.upperBound),
                plain.count
            ],
            "a number lands after the full stop of the sentence that cited it")
        expect(
            ChatCitations.anchors(in: text, numbers: [:]).isEmpty,
            "a reply with no sources gets no numbers")
    }

    static func toolScopeSwitchesServersPerChat() {
        var scope = ChatToolScope()
        expect(scope.allows("files"), "a new chat may call every connected server")
        scope.toggle("files")
        expect(!scope.allows("files") && scope.allows("web"), "one server switches off alone")
        scope.toggle("files")
        scope.isEnabled = false
        expect(!scope.allows("web"), "switching tools off stops every server")
    }

    static func choicesComeOutOfTheirFence() {
        let reply = "Which one?\n\n```choices\n- Summarise it\n2. Translate it\n\n```\nThanks."
        let split = ChatChoices.split(reply)
        expect(split.choices == ["Summarise it", "Translate it"], "a fence's lines are the choices")
        expect(split.text == "Which one?\n\nThanks.", "the fence never shows as prose")
        let streaming = ChatChoices.split("Pick:\n```choices\nA\nB")
        expect(
            streaming.choices == ["A", "B"] && streaming.text == "Pick:",
            "an unclosed fence is already hidden while it streams")
        let code = "Use this:\n```swift\nlet choices = 1\n```"
        expect(ChatChoices.split(code).choices.isEmpty, "an ordinary code fence is not a choice list")
        let inline = ChatChoices.split("Say ```choices``` to me")
        expect(inline.choices.isEmpty, "a fence mid-line is prose, not choices")

        // What Apple Intelligence wrote: no fence, a `choices` line over a list.
        let unfenced = ChatChoices.split(
            "Here are a few ways I can help:\n\n* Open it\n\nchoices\n\n- Open Quick AI\n- Open AI Chat\n")
        expect(
            unfenced.choices == ["Open Quick AI", "Open AI Chat"]
                && unfenced.text == "Here are a few ways I can help:\n\n* Open it",
            "a bare `choices` label over a closing list is a choice list: \(unfenced)")
        expect(
            ChatChoices.split("**Choices:**\n1. Yes\n2. No").choices == ["Yes", "No"],
            "the label may be bold, capitalised or end in a colon")
        let proseAfter = "choices\n- A\n- B\n\nThat is all."
        expect(
            ChatChoices.split(proseAfter).choices.isEmpty, "a list followed by prose is not the reply's end")
        expect(
            ChatChoices.split("Your choices matter.\n- A").choices.isEmpty,
            "the word inside a sentence is not a label")
    }

    static func usageIsKeptWithTheReplyThatReportedIt() async {
        let (store, directory) = temporaryStore("usage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let reported = AIUsage(
            inputTokens: 10, outputTokens: 59, cachedInputTokens: 6_401, reasoningTokens: 51,
            contextWindow: 200_000, costUSD: 0.0009)
        let chat = AIChatState(history: store)
        chat.send("Hi", using: ScriptedProvider(rounds: [[.text("Yo"), .usage(reported), .finished]]))
        await settle(chat)
        expect(chat.usage == reported, "the reply carries what its route reported")
        expect(reported.contextTokens == 6_470, "the context counts cached prompt tokens too")
        let reopened = AIChatState(history: ChatHistoryStore(directory: directory))
        expect(reopened.open(id: chat.session.id), "the chat reopens")
        expect(reopened.usage == reported, "a reopened chat still knows its last turn's tokens")
    }

    /// Replies stream on a task; a few turns of the main actor let the scripted events land.
    static func settle(_ chat: AIChatState) async {
        for _ in 0..<50 where chat.isStreaming {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Holds every reply open until told to finish, so a test can switch surfaces mid-answer.
final class StalledProvider: AIProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AIProviderStream.Continuation] = []

    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            lock.withLock { continuations.append(continuation) }
        }
    }

    func finishAll() {
        for continuation in lock.withLock({ continuations }) {
            continuation.yield(.text("done"))
            continuation.yield(.finished)
            continuation.finish()
        }
    }
}

/// A base route that replays one scripted round per request, so the loop's driving is what is tested.
final class ScriptedProvider: AIProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var rounds: [[AIStreamEvent]]
    private var seen: [AIRequest] = []

    init(rounds: [[AIStreamEvent]]) {
        self.rounds = rounds
    }

    var requests: [AIRequest] {
        lock.withLock { seen }
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        let events: [AIStreamEvent] = lock.withLock {
            seen.append(request)
            return rounds.isEmpty ? [.finished] : rounds.removeFirst()
        }
        return AIProviderStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// Stands in for the MCP coordinator: it records what it was asked and answers the same way.
final class RecordingInvoker: @unchecked Sendable {
    private let lock = NSLock()
    private let result: String
    private var received: [AIToolCall] = []

    init(result: String) {
        self.result = result
    }

    var calls: [AIToolCall] {
        lock.withLock { received }
    }

    func invoke(_ call: AIToolCall) async -> AIToolResult {
        lock.withLock { received.append(call) }
        return AIToolResult(callID: call.id, content: result, isError: false)
    }
}
