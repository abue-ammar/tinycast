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
        await theToolLoopRunsUntilTheModelStopsAsking()
        await theToolLoopRefusesToRunForever()
        await toolOutputIsBoundedBeforeItIsBilled()
        toolUsesPersistAndSettleOnReload()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// A reply that searched and called tools has to render them in the order they happened.
    static func segmentsInterleaveSearchesAndTools() {
        let message = ChatMessage(
            role: .assistant, text: "abcdef",
            searches: [ChatSearch(query: "q", isComplete: true, textOffset: 4)],
            toolUses: [
                ChatToolUse(
                    callID: "1", origin: "Files", title: "read", state: .completed, textOffset: 2)
            ])
        expect(
            message.segments == [
                .text("ab"),
                .tool(
                    ChatToolUse(
                        callID: "1", origin: "Files", title: "read", state: .completed,
                        textOffset: 2)),
                .text("cd"),
                .search(ChatSearch(query: "q", isComplete: true, textOffset: 4)),
                .text("ef")
            ],
            "segments interleave by offset, whichever kind of interruption came first")
        expect(
            ChatToolUse(
                callID: "1", origin: "Files", title: "read", state: .running, textOffset: 0
            ).label
                == "Calling Files · read",
            "a running call says so, and names the server it is calling")
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
            for try await _ in loop(base, invoker).stream(Self.turn) {}
        } catch {
            failure = error.localizedDescription
        }
        expect(
            base.requests.count == AIToolLoopProvider.maxRounds,
            "the loop stops at its cap rather than billing another round")
        expect(
            failure?.contains("\(AIToolLoopProvider.maxRounds) rounds") == true,
            "and the turn fails with a sentence naming why it stopped")
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
                        textOffset: 3),
                    ChatToolUse(
                        callID: "c2", origin: "Files", title: "write", state: .running,
                        textOffset: 7)
                ]))
        store.save(session)

        let reloaded = ChatHistoryStore(directory: directory).session(id: session.id)
        let uses = reloaded?.messages.last?.toolUses ?? []
        expect(uses.count == 2, "a reopened chat still shows what the model did on the reader's behalf")
        expect(uses.first?.title == "read", "in the order it did it")
        expect(
            uses.last?.state == .failed,
            "a call left running belonged to a process that is gone, so it never reported back")
    }

    private static let turn = AIRequest(messages: [AIMessage(role: .user, text: "go")])

    private static func loop(
        _ base: ScriptedProvider, _ invoker: RecordingInvoker
    ) -> AIToolLoopProvider {
        AIToolLoopProvider(
            base: base,
            tools: [
                AITool(
                    name: "fs__read", description: "", parameters: .object([:]), origin: "Files",
                    title: "read")
            ],
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
            !AIAttachmentBudget.admits(staged, adding: small),
            "the composer stops at the number of images one message may carry")
        expect(
            AIAttachmentBudget.admits(staged.dropLast(), adding: small),
            "one under that count still fits")

        let heavy = AIImage(
            data: Data(repeating: 7, count: AIAttachmentBudget.maxBytes), mimeType: "image/png")
        expect(
            AIAttachmentBudget.admits([], adding: heavy),
            "one picture may spend the whole byte budget")
        expect(
            !AIAttachmentBudget.admits([small], adding: heavy),
            "bytes are counted across the turn, not per picture")

        expect(
            AIAttachmentBudget.bounded(staged + [small]).count == AIAttachmentBudget.maxCount,
            "the backstop drops what the count cannot carry")
        expect(
            AIAttachmentBudget.bounded([small, heavy, small]) == [small],
            "the backstop keeps the leading run that fits the byte budget")
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
                searches: [ChatSearch(query: "india news", isComplete: false, textOffset: 3)]))
        expect(
            session.messages.last?.segments == [
                .text("Par"),
                .search(ChatSearch(query: "india news", isComplete: false, textOffset: 3)),
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
                == [ChatSearch(query: "india news", isComplete: true, textOffset: 3)],
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
            reply.searches = [ChatSearch(query: "docs", isComplete: true, textOffset: 0)]
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
                == [ChatSearch(query: "docs", isComplete: true, textOffset: 0)],
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
                searches: [ChatSearch(query: "news", isComplete: false, textOffset: 1)]))
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
                == [ChatSearch(query: "news", isComplete: true, textOffset: 1)],
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
                ChatSearch(query: nil, isComplete: true, textOffset: 0),
                ChatSearch(query: "late", isComplete: true, textOffset: 99)
            ])
        expect(
            message.segments == [
                .search(ChatSearch(query: nil, isComplete: true, textOffset: 0)),
                .text("abc"),
                .search(ChatSearch(query: "late", isComplete: true, textOffset: 99))
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
                    image: AIImage(data: Data([0x89, UInt8(stamp)]), mimeType: "image/png"),
                    name: "shot-\(stamp).png"))
        }

        let opening = AIChatState(history: store)
        stage(opening)
        let beforeOpen = opening.stagingGeneration
        expect(opening.open(id: saved), "a saved conversation opens")
        expect(opening.pendingImages.isEmpty, "opening another conversation drops its staged images")
        expect(
            opening.stagingGeneration != beforeOpen,
            "opening another conversation disowns a decode still in flight")

        let reopening = AIChatState(history: store)
        expect(reopening.open(id: saved), "the saved conversation opens once")
        stage(reopening)
        let beforeSame = reopening.stagingGeneration
        expect(reopening.open(id: saved), "reopening the conversation already on screen succeeds")
        expect(
            reopening.pendingImages.count == 1 && reopening.stagingGeneration == beforeSame,
            "reopening the conversation already on screen keeps its staged images")

        let deleting = AIChatState(history: store)
        expect(deleting.open(id: saved), "the conversation to delete opens")
        stage(deleting)
        let beforeOther = deleting.stagingGeneration
        deleting.delete(id: UUID())
        expect(
            deleting.pendingImages.count == 1 && deleting.stagingGeneration == beforeOther,
            "deleting some other conversation leaves the composer alone")
        deleting.delete(id: saved)
        expect(deleting.pendingImages.isEmpty, "deleting the open conversation drops its staged images")

        let clearingAll = AIChatState(history: store)
        stage(clearingAll)
        clearingAll.deleteAll()
        expect(clearingAll.pendingImages.isEmpty, "Delete All drops the staged images")

        let starting = AIChatState(history: store)
        stage(starting)
        let beforeNew = starting.stagingGeneration
        starting.startNewChat()
        expect(
            starting.pendingImages.isEmpty && starting.stagingGeneration != beforeNew,
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
