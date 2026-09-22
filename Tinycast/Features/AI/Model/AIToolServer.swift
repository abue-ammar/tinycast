import Foundation

/// A tool server a route's own client runs, for the routes where the vendor CLI is the MCP client.
/// `AITool` is the same hand-off for the routes where Tinycast runs the loop itself.
struct AIToolServer: Equatable, Sendable {
    enum Transport: Equatable, Sendable {
        /// A local process. The values travel in the child's environment, never on its argv.
        case command(path: String, arguments: [String], environment: [String: String])
        /// A remote endpoint. The header value is a secret for the same reason.
        case url(String, headerName: String, headerValue: String)
    }

    /// The handle a tool name routes back to, and the name the CLI knows the server by.
    let handle: String
    let title: String
    let transport: Transport
}

/// One call a route's own client is asking permission for, named the way Tinycast addresses it.
struct AIToolServerCall: Equatable, Sendable {
    let handle: String
    let tool: String
}

/// How a route whose own client runs the tool loop reaches Tinycast's servers and its reader.
struct AIToolServerSession: Sendable {
    let servers: @Sendable () async -> [AIToolServer]
    let consent: @Sendable (AIToolServerCall) async -> Bool
    /// The bound the BYOK loop uses, applied to the CLI's own loop so a reply stops alike.
    let rounds: Int

    init(
        rounds: Int,
        servers: @escaping @Sendable () async -> [AIToolServer],
        consent: @escaping @Sendable (AIToolServerCall) async -> Bool
    ) {
        self.rounds = rounds
        self.servers = servers
        let queue = ConsentQueue()
        self.consent = { call in await queue.ask { await consent(call) } }
    }

    /// One question at a time: a second would find the dialog busy, and must see the first's grant.
    @MainActor
    private final class ConsentQueue {
        private var isAsking = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func ask(_ question: @Sendable () async -> Bool) async -> Bool {
            if isAsking {
                await withCheckedContinuation { waiting.append($0) }
            } else {
                isAsking = true
            }
            defer {
                if waiting.isEmpty { isAsking = false } else { waiting.removeFirst().resume() }
            }
            guard !Task.isCancelled else { return false }
            return await question()
        }
    }
}

/// What a transcript row may say about a call the CLI reported; the names come from someone else.
enum AIToolServerRow {
    /// A row is one line: a server that answers with a kilobyte of name must not become one.
    static let maxNameLength = 64

    static func label(_ name: String) -> String {
        name.count <= maxNameLength ? name : String(name.prefix(maxNameLength)) + "\u{2026}"
    }

    static func title(of server: String, in servers: [AIToolServer]) -> String {
        label(servers.first { $0.handle == server }?.title ?? server)
    }
}
