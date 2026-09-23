import Foundation
import Observation
import SQLite3

private let chatSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Durable local chats; summaries stay resident while transcripts load only when requested.
@MainActor
@Observable
final class ChatHistoryStore {
    private(set) var conversations: [ChatConversation] = []
    private(set) var isAvailable = true

    private static let schema = """
        PRAGMA foreign_keys = ON;
        CREATE TABLE IF NOT EXISTS conversations(
          id TEXT PRIMARY KEY NOT NULL,
          title TEXT NOT NULL,
          preview TEXT NOT NULL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          message_count INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS messages(
          id TEXT PRIMARY KEY NOT NULL,
          conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          role TEXT NOT NULL,
          text TEXT NOT NULL,
          state TEXT NOT NULL,
          sent_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS message_images(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          mime_type TEXT NOT NULL,
          data BLOB NOT NULL,
          PRIMARY KEY(message_id, position)
        );
        CREATE TABLE IF NOT EXISTS message_documents(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          name TEXT NOT NULL,
          mime_type TEXT NOT NULL,
          data BLOB NOT NULL,
          PRIMARY KEY(message_id, position)
        );
        CREATE TABLE IF NOT EXISTS message_searches(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          query TEXT,
          text_offset INTEGER NOT NULL,
          PRIMARY KEY(message_id, position)
        );
        CREATE TABLE IF NOT EXISTS message_tools(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          call_id TEXT NOT NULL,
          origin TEXT NOT NULL,
          title TEXT NOT NULL,
          state TEXT NOT NULL,
          text_offset INTEGER NOT NULL,
          PRIMARY KEY(message_id, position)
        );
        CREATE TABLE IF NOT EXISTS conversation_details(
          conversation_id TEXT PRIMARY KEY NOT NULL
            REFERENCES conversations(id) ON DELETE CASCADE,
          custom_title TEXT,
          generated_title TEXT,
          pinned INTEGER NOT NULL DEFAULT 0,
          model TEXT
        );
        CREATE TABLE IF NOT EXISTS message_details(
          message_id TEXT PRIMARY KEY NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          tool_scope TEXT,
          input_tokens INTEGER,
          output_tokens INTEGER,
          cached_tokens INTEGER,
          reasoning_tokens INTEGER,
          context_window INTEGER,
          cost_usd REAL
        );
        CREATE TABLE IF NOT EXISTS message_thinking(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          text TEXT NOT NULL,
          text_offset INTEGER NOT NULL,
          duration REAL,
          PRIMARY KEY(message_id, position)
        );
        CREATE INDEX IF NOT EXISTS messages_by_conversation
          ON messages(conversation_id, position);
        CREATE INDEX IF NOT EXISTS conversations_by_recency
          ON conversations(updated_at DESC);
        """

    @ObservationIgnored private let databaseURL: URL
    @ObservationIgnored private var database: OpaquePointer?

    init(directory: URL) {
        databaseURL = directory.appendingPathComponent("ai-chats.sqlite3")
    }

    isolated deinit {
        sqlite3_close(database)
    }

    func load() {
        guard ensureDatabase(), let database else { return }
        let sql = """
            SELECT c.id, c.title, c.preview, c.created_at, c.updated_at, c.message_count,
              m.custom_title, COALESCE(m.pinned, 0), m.generated_title
            FROM conversations c
            LEFT JOIN conversation_details m ON m.conversation_id = c.id
            ORDER BY c.updated_at DESC;
            """
        guard let statement = prepare(sql, in: database) else { return }
        defer { sqlite3_finalize(statement) }
        var loaded: [ChatConversation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)) else { continue }
            loaded.append(
                ChatConversation(
                    id: id, title: text(statement, 1), preview: text(statement, 2),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    messageCount: Int(sqlite3_column_int64(statement, 5)),
                    customTitle: optionalText(statement, 6),
                    isPinned: sqlite3_column_int64(statement, 7) != 0,
                    generatedTitle: optionalText(statement, 8)))
        }
        conversations = loaded
    }

    /// Off means fully off: the handle and the resident summaries go, the file on disk stays.
    func close() {
        sqlite3_close(database)
        database = nil
        conversations = []
    }

    func search(_ query: String) -> [ChatConversation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    func conversation(id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    /// A blank name hands the title back to the first question rather than storing an empty one.
    func rename(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.titleLimit))
        guard var conversation = conversation(id: id),
            write(.customTitle(custom), of: id)
        else { return }
        conversation.customTitle = custom
        replace(conversation)
    }

    /// The harness's name for a chat; stored beside it, so a later save cannot derive it away.
    func setGeneratedTitle(_ title: String, id: UUID) {
        guard var conversation = conversation(id: id), write(.generatedTitle(title), of: id)
        else { return }
        conversation.generatedTitle = title
        replace(conversation)
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        guard var conversation = conversation(id: id), conversation.isPinned != pinned,
            write(.pinned(pinned), of: id)
        else { return }
        conversation.isPinned = pinned
        replace(conversation)
    }

    private static let titleLimit = 120

    func session(id: UUID) -> ChatSession? {
        guard ensureDatabase(), let database else { return nil }
        let conversationSQL = """
            SELECT created_at, updated_at FROM conversations WHERE id = ? LIMIT 1;
            """
        guard let conversation = prepare(conversationSQL, in: database) else { return nil }
        defer { sqlite3_finalize(conversation) }
        bind(id.uuidString, to: conversation, at: 1)
        guard sqlite3_step(conversation) == SQLITE_ROW else { return nil }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(conversation, 0))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(conversation, 1))

        let messageSQL = """
            SELECT id, role, text, state, sent_at FROM messages
            WHERE conversation_id = ? ORDER BY position;
            """
        guard let messagesStatement = prepare(messageSQL, in: database) else { return nil }
        defer { sqlite3_finalize(messagesStatement) }
        bind(id.uuidString, to: messagesStatement, at: 1)
        let images = images(forConversation: id, in: database)
        let documents = documents(forConversation: id, in: database)
        let searches = searches(forConversation: id, in: database)
        let toolUses = toolUses(forConversation: id, in: database)
        let reasoning = reasoning(forConversation: id, in: database)
        let meta = messageMeta(forConversation: id, in: database)
        var messages: [ChatMessage] = []
        while sqlite3_step(messagesStatement) == SQLITE_ROW {
            guard
                let messageID = UUID(uuidString: text(messagesStatement, 0)),
                let role = ChatMessage.Role(rawValue: text(messagesStatement, 1)),
                let storedState = ChatMessage.State(rawValue: text(messagesStatement, 3))
            else { continue }
            var body = text(messagesStatement, 2)
            let state: ChatMessage.State
            if storedState == .streaming {
                state = .failed
                if body.isEmpty { body = "Response interrupted." }
            } else {
                state = storedState
            }
            messages.append(
                ChatMessage(
                    id: messageID, role: role, text: body, state: state,
                    sentAt: Date(
                        timeIntervalSince1970: sqlite3_column_double(messagesStatement, 4)),
                    images: images[messageID] ?? [], documents: documents[messageID] ?? [],
                    searches: searches[messageID] ?? [],
                    toolUses: toolUses[messageID] ?? [],
                    reasoning: reasoning[messageID] ?? [],
                    usage: meta[messageID]?.usage, toolScope: meta[messageID]?.toolScope))
        }
        return ChatSession(
            id: id, createdAt: createdAt, updatedAt: updatedAt, messages: messages,
            model: model(forConversation: id, in: database))
    }

    func save(_ session: ChatSession) {
        guard !session.messages.isEmpty, ensureDatabase(), let database else { return }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return }
        guard saveConversation(session, in: database), rewriteTail(of: session, database: database),
            saveModel(of: session)
        else {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            return
        }
        guard sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            return
        }
        var summary = session.summary
        // The summary is derived afresh; a rename and a pin are the reader's, so they carry over.
        if let existing = conversation(id: session.id) {
            summary.customTitle = existing.customTitle
            summary.isPinned = existing.isPinned
            summary.generatedTitle = existing.generatedTitle
        }
        replace(summary)
    }

    private func replace(_ conversation: ChatConversation) {
        var updated = conversations.filter { $0.id != conversation.id }
        updated.append(conversation)
        conversations = updated.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// One fact a conversation's meta row holds; writing one never touches the others.
    private enum Meta {
        case customTitle(String?)
        case generatedTitle(String)
        case pinned(Bool)
        case model(AIModelSelection)

        var column: String {
            switch self {
            case .customTitle: "custom_title"
            case .generatedTitle: "generated_title"
            case .pinned: "pinned"
            case .model: "model"
            }
        }
    }

    private func write(_ meta: Meta, of id: UUID) -> Bool {
        guard ensureDatabase(), let database else { return false }
        let column = meta.column
        let sql = """
            INSERT INTO conversation_details(conversation_id, \(column)) VALUES(?, ?)
            ON CONFLICT(conversation_id) DO UPDATE SET \(column) = excluded.\(column);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        switch meta {
        case .customTitle(let title): if let title { bind(title, to: statement, at: 2) }
        case .generatedTitle(let title): bind(title, to: statement, at: 2)
        case .pinned(let pinned): sqlite3_bind_int64(statement, 2, pinned ? 1 : 0)
        case .model(let model):
            guard let json = try? JSONEncoder().encode(model),
                let encoded = String(bytes: json, encoding: .utf8)
            else { return false }
            bind(encoded, to: statement, at: 2)
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    func remove(id: UUID) {
        guard ensureDatabase(), let database,
            let statement = prepare("DELETE FROM conversations WHERE id = ?;", in: database)
        else { return }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { return }
        conversations.removeAll { $0.id == id }
    }

    /// Pinned chats are the ones the reader asked to keep, so clearing the rest spares them.
    func clearAll() {
        guard ensureDatabase(), let database,
            sqlite3_exec(
                database, "DELETE FROM conversations WHERE id NOT IN (\(Self.pinnedIDs))", nil,
                nil, nil) == SQLITE_OK
        else { return }
        conversations.removeAll { !$0.isPinned }
    }

    private static let pinnedIDs =
        "SELECT conversation_id FROM conversation_details WHERE pinned = 1"

    /// Inline BLOBs make this the one store where a delete frees pages without shrinking the file.
    @discardableResult
    func prune(before cutoff: Date) -> Int {
        guard ensureDatabase(), let database,
            let statement = prepare(
                "DELETE FROM conversations WHERE updated_at < ? AND id NOT IN (\(Self.pinnedIDs));",
                in: database)
        else { return 0 }
        var removed = 0
        defer {
            sqlite3_finalize(statement)
            if removed > 0 { sqlite3_exec(database, "VACUUM", nil, nil, nil) }
        }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { return 0 }
        removed = Int(sqlite3_changes(database))
        guard removed > 0 else { return 0 }
        conversations.removeAll { $0.updatedAt < cutoff && !$0.isPinned }
        return removed
    }

    private func ensureDatabase() -> Bool {
        if database != nil { return true }
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            isAvailable = false
            return false
        }
        guard
            sqlite3_open_v2(
                databaseURL.path, &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
            sqlite3_exec(database, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(database, Self.schema, nil, nil, nil) == SQLITE_OK
        else {
            sqlite3_close(database)
            database = nil
            isAvailable = false
            return false
        }
        isAvailable = true
        return true
    }

    private func saveConversation(_ session: ChatSession, in database: OpaquePointer) -> Bool {
        let sql = """
            INSERT INTO conversations(id, title, preview, created_at, updated_at, message_count)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              title = excluded.title,
              preview = excluded.preview,
              updated_at = excluded.updated_at,
              message_count = excluded.message_count;
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        let summary = session.summary
        bind(summary.id.uuidString, to: statement, at: 1)
        bind(summary.title, to: statement, at: 2)
        bind(summary.preview, to: statement, at: 3)
        sqlite3_bind_double(statement, 4, summary.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, summary.updatedAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 6, Int64(summary.messageCount))
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// A session only appends or replaces its last, so a save rewrites the stored tail alone.
    private func rewriteTail(of session: ChatSession, database: OpaquePointer) -> Bool {
        let stored = storedMessageCount(of: session.id, in: database)
        // A store holding more rows than memory is foreign state; rewrite it whole, never splice.
        let rewriteFrom = stored > session.messages.count ? 0 : max(stored - 1, 0)
        guard
            let deletion = prepare(
                "DELETE FROM messages WHERE conversation_id = ? AND position >= ?;", in: database)
        else { return false }
        bind(session.id.uuidString, to: deletion, at: 1)
        sqlite3_bind_int64(deletion, 2, Int64(rewriteFrom))
        let deleted = sqlite3_step(deletion) == SQLITE_DONE
        sqlite3_finalize(deletion)
        guard deleted else { return false }

        let sql = """
            INSERT INTO messages(id, conversation_id, position, role, text, state, sent_at)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for (position, message) in session.messages.enumerated().dropFirst(rewriteFrom) {
            bind(message.id.uuidString, to: statement, at: 1)
            bind(session.id.uuidString, to: statement, at: 2)
            sqlite3_bind_int64(statement, 3, Int64(position))
            bind(message.role.rawValue, to: statement, at: 4)
            bind(message.text, to: statement, at: 5)
            bind(message.state.rawValue, to: statement, at: 6)
            sqlite3_bind_double(statement, 7, message.sentAt.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return session.messages[rewriteFrom...].allSatisfy {
            saveImages(of: $0, in: database) && saveDocuments(of: $0, in: database)
                && saveSearches(of: $0, in: database)
                && saveToolUses(of: $0, in: database)
                && saveReasoning(of: $0, in: database)
                && saveMeta(of: $0, in: database)
        }
    }

    private func storedMessageCount(of id: UUID, in database: OpaquePointer) -> Int {
        guard
            let statement = prepare(
                "SELECT COUNT(*) FROM messages WHERE conversation_id = ?;", in: database)
        else { return 0 }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func saveSearches(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.searches.isEmpty else { return true }
        let sql = """
            INSERT INTO message_searches(message_id, position, query, text_offset)
            VALUES(?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for search in message.searches {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(search.sequence))
            if let query = search.query { bind(query, to: statement, at: 3) }
            sqlite3_bind_int64(statement, 4, Int64(search.textOffset))
            guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    /// A stored search is always finished: only a live reply has one in progress.
    private func searches(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [ChatSearch]] {
        let sql = """
            SELECT s.message_id, s.query, s.text_offset, s.position FROM message_searches s
            JOIN messages m ON m.id = s.message_id
            WHERE m.conversation_id = ? ORDER BY s.message_id, s.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var searches: [UUID: [ChatSearch]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)) else { continue }
            let query = optionalText(statement, 1)
            searches[messageID, default: []].append(
                ChatSearch(
                    query: query, isComplete: true,
                    textOffset: Int(sqlite3_column_int64(statement, 2)),
                    sequence: Int(sqlite3_column_int64(statement, 3))))
        }
        return searches
    }

    private func saveToolUses(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.toolUses.isEmpty else { return true }
        let sql = """
            INSERT INTO message_tools(
              message_id, position, call_id, origin, title, state, text_offset)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for use in message.toolUses {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(use.sequence))
            bind(use.callID, to: statement, at: 3)
            bind(use.origin, to: statement, at: 4)
            bind(use.title, to: statement, at: 5)
            bind(use.state.rawValue, to: statement, at: 6)
            sqlite3_bind_int64(statement, 7, Int64(use.textOffset))
            guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    /// A call left running belonged to a process that is gone, so it never reported back.
    private func toolUses(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [ChatToolUse]] {
        let sql = """
            SELECT t.message_id, t.call_id, t.origin, t.title, t.state, t.text_offset, t.position
            FROM message_tools t
            JOIN messages m ON m.id = t.message_id
            WHERE m.conversation_id = ? ORDER BY t.message_id, t.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var uses: [UUID: [ChatToolUse]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)) else { continue }
            let stored = ChatToolUse.State(rawValue: text(statement, 4)) ?? .failed
            uses[messageID, default: []].append(
                ChatToolUse(
                    callID: text(statement, 1), origin: text(statement, 2),
                    title: text(statement, 3), state: stored == .running ? .failed : stored,
                    textOffset: Int(sqlite3_column_int64(statement, 5)),
                    sequence: Int(sqlite3_column_int64(statement, 6))))
        }
        return uses
    }

    /// After the conversation's row, which the meta row references; a chat with no pick has none.
    private func saveModel(of session: ChatSession) -> Bool {
        guard let model = session.model else { return true }
        return write(.model(model), of: session.id)
    }

    /// A route removed since is the coordinator's to repair; an unreadable one is simply absent.
    private func model(forConversation id: UUID, in database: OpaquePointer) -> AIModelSelection? {
        guard
            let statement = prepare(
                "SELECT model FROM conversation_details WHERE conversation_id = ? AND model IS NOT NULL;",
                in: database)
        else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try? JSONDecoder().decode(
            AIModelSelection.self, from: Data(text(statement, 0).utf8))
    }

    /// A chat already saved changes model between turns; one not yet saved takes it on its first.
    func setModel(_ model: AIModelSelection, id: UUID) {
        guard conversation(id: id) != nil else { return }
        _ = write(.model(model), of: id)
    }

    private func saveReasoning(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.reasoning.isEmpty else { return true }
        let sql = """
            INSERT INTO message_thinking(message_id, position, text, text_offset, duration)
            VALUES(?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for (position, block) in message.reasoning.enumerated() {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(position))
            bind(block.text, to: statement, at: 3)
            sqlite3_bind_int64(statement, 4, Int64(block.textOffset))
            if let duration = block.duration { sqlite3_bind_double(statement, 5, duration) }
            guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    private func reasoning(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [ChatReasoning]] {
        let sql = """
            SELECT r.message_id, r.text, r.text_offset, r.duration FROM message_thinking r
            JOIN messages m ON m.id = r.message_id
            WHERE m.conversation_id = ? ORDER BY r.message_id, r.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var reasoning: [UUID: [ChatReasoning]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)) else { continue }
            let duration =
                sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 3)
            reasoning[messageID, default: []].append(
                ChatReasoning(
                    text: text(statement, 1), textOffset: Int(sqlite3_column_int64(statement, 2)),
                    duration: duration))
        }
        return reasoning
    }

    /// Only a message with a scope or a usage report writes a row.
    private func saveMeta(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard message.toolScope != nil || message.usage != nil else { return true }
        let sql = """
            INSERT INTO message_details(message_id, tool_scope, input_tokens, output_tokens,
              cached_tokens, reasoning_tokens, context_window, cost_usd)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(message.id.uuidString, to: statement, at: 1)
        if let scope = message.toolScope { bind(scope, to: statement, at: 2) }
        if let usage = message.usage {
            let counts = [
                usage.inputTokens, usage.outputTokens, usage.cachedInputTokens,
                usage.reasoningTokens, usage.contextWindow
            ]
            for (offset, count) in counts.enumerated() {
                if let count { sqlite3_bind_int64(statement, Int32(offset + 3), Int64(count)) }
            }
            if let cost = usage.costUSD { sqlite3_bind_double(statement, 8, cost) }
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// A row with no usage column set is a scope alone: the reply reported nothing.
    private func messageMeta(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: (toolScope: String?, usage: AIUsage?)] {
        let sql = """
            SELECT x.message_id, x.tool_scope, x.input_tokens, x.output_tokens, x.cached_tokens,
              x.reasoning_tokens, x.context_window, x.cost_usd
            FROM message_details x JOIN messages m ON m.id = x.message_id
            WHERE m.conversation_id = ?;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        func count(_ column: Int32) -> Int? {
            sqlite3_column_type(statement, column) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(statement, column))
        }
        var meta: [UUID: (toolScope: String?, usage: AIUsage?)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)) else { continue }
            let usage = AIUsage(
                inputTokens: count(2), outputTokens: count(3), cachedInputTokens: count(4),
                reasoningTokens: count(5), contextWindow: count(6),
                costUSD: sqlite3_column_type(statement, 7) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 7))
            meta[messageID] = (optionalText(statement, 1), usage == AIUsage() ? nil : usage)
        }
        return meta
    }

    private func saveImages(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.images.isEmpty else { return true }
        let sql = """
            INSERT INTO message_images(message_id, position, mime_type, data) VALUES(?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for (position, image) in message.images.enumerated() {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(position))
            bind(image.mimeType, to: statement, at: 3)
            let bound = image.data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(
                    statement, 4, bytes.baseAddress, Int32(bytes.count), chatSQLiteTransient)
            }
            guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    private func saveDocuments(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.documents.isEmpty else { return true }
        let sql = """
            INSERT INTO message_documents(message_id, position, name, mime_type, data)
            VALUES(?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for (position, document) in message.documents.enumerated() {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(position))
            bind(document.name, to: statement, at: 3)
            bind(document.mimeType, to: statement, at: 4)
            let bound = document.data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(
                    statement, 5, bytes.baseAddress, Int32(bytes.count), chatSQLiteTransient)
            }
            guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    private func documents(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [AIDocument]] {
        let sql = """
            SELECT d.message_id, d.name, d.mime_type, d.data FROM message_documents d
            JOIN messages m ON m.id = d.message_id
            WHERE m.conversation_id = ? ORDER BY d.message_id, d.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var documents: [UUID: [AIDocument]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)),
                let bytes = sqlite3_column_blob(statement, 3)
            else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 3)))
            documents[messageID, default: []].append(
                AIDocument(data: data, mimeType: text(statement, 2), name: text(statement, 1)))
        }
        return documents
    }

    private func images(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [AIImage]] {
        let sql = """
            SELECT i.message_id, i.mime_type, i.data FROM message_images i
            JOIN messages m ON m.id = i.message_id
            WHERE m.conversation_id = ? ORDER BY i.message_id, i.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var images: [UUID: [AIImage]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)),
                let bytes = sqlite3_column_blob(statement, 2)
            else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            images[messageID, default: []].append(AIImage(data: data, mimeType: text(statement, 1)))
        }
        return images
    }

    private func prepare(_ sql: String, in database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, chatSQLiteTransient)
    }

    private func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(statement, index)
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
}
