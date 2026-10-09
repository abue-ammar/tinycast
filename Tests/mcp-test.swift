// MCP's pure half: the wire framing, the names that route a call, trust, and what a chat addresses.

import Foundation

@main
@MainActor
struct MCPTests {
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

    static func main() {
        framingCarriesTheProtocolVersion()
        parsingTellsRepliesFromNotifications()
        slugsAreDerivedAndUnique()
        toolNamesRouteBackToTheirServer()
        toolListsDropWhatCannotBeCalled()
        outputFlattensToWhatAModelCanRead()
        trustDecidesFromStandingAndChatGrants()
        addressingTakesOnlyAKnownHandle()
        settingsPersistAndKeepHandlesApart()
        serversBecomeWhatACLICanRunItself()
        onlyOneCopyOfALocalServerRuns()
        nonASCIINamesStillMakeAHandle()
        wireNamesAreLookedUpNotParsed()
        theHandshakeIsNegotiatedAndPaged()
        legacyStreamsAreReadByEventName()
        sharedConfigurationImports()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// A server that never sees `"jsonrpc"` answers with an error instead of a result.
    static func framingCarriesTheProtocolVersion() {
        guard let data = try? MCPProtocol.request(id: 7, method: "tools/list"),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            expect(false, "a request encodes to a JSON object")
            return
        }
        expect(object["jsonrpc"] as? String == "2.0", "every message names JSON-RPC 2.0")
        expect(object["id"] as? Int == 7, "the id survives encoding")
        expect(object["params"] == nil, "no params means the key is absent, not null")
        expect(data.last != 0x0A, "an HTTP body is not newline-terminated")

        let framed = try? MCPProtocol.request(
            id: 1, method: "initialize", params: ["a": 1], newlineTerminated: true)
        expect(framed?.last == 0x0A, "a stdio message ends in the newline that frames it")

        let notification = try? MCPProtocol.notification(method: "notifications/initialized")
        let decoded =
            notification.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        expect(decoded?["id"] == nil, "a notification carries no id")
    }

    static func parsingTellsRepliesFromNotifications() {
        let response = MCPProtocol.parse(Data(#"{"jsonrpc":"2.0","id":3,"result":{"ok":true}}"#.utf8))
        expect(
            response == .response(id: 3, result: .object(["ok": .bool(true)])),
            "a result parses as the reply to its id")

        let failure = MCPProtocol.parse(
            Data(#"{"jsonrpc":"2.0","id":3,"error":{"code":-1,"message":"nope"}}"#.utf8))
        expect(failure == .failure(id: 3, message: "nope"), "an error carries the server's message")

        let notification = MCPProtocol.parse(
            Data(#"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#.utf8))
        expect(
            notification == .notification(method: "notifications/tools/list_changed", params: .object([:])),
            "a method without an id is a notification")

        guard
            case .request(let id, let method) = MCPProtocol.parse(
                Data(#"{"jsonrpc":"2.0","id":"a1","method":"sampling/createMessage"}"#.utf8))
        else {
            expect(false, "a method with an id is a request Tinycast must answer")
            return
        }
        expect(
            id == .string("a1") && method == "sampling/createMessage",
            "a server request keeps its string id, so the decline can address it")
        expect(
            MCPProtocol.parse(Data("not json".utf8)) == .invalid,
            "garbage on the wire is invalid, never a silent success")
    }

    static func slugsAreDerivedAndUnique() {
        expect(MCPSlug.normalize("GitHub Issues") == "github-issues", "a name becomes a handle")
        expect(MCPSlug.normalize("  ") == "server", "a nameless server still gets a handle")
        expect(
            MCPSlug.normalize("Files!! & Folders").allSatisfy {
                $0.isLowercase || $0.isNumber || $0 == "-"
            }, "punctuation never reaches a handle")
        expect(
            MCPSlug.normalize(String(repeating: "a", count: 60)).count <= MCPSlug.maxLength,
            "a handle stays typeable")
        expect(
            MCPSlug.make(from: "github", existing: ["github"]) == "github-2",
            "a taken handle is suffixed rather than refused")
        expect(
            MCPSlug.make(from: "github", existing: ["github", "github-2"]) == "github-3",
            "and keeps counting past the first collision")
    }

    static func toolNamesRouteBackToTheirServer() {
        let wire = MCPToolName.compose(slug: "github", tool: "search_issues")
        expect(wire == "github__search_issues", "a name is the handle, the separator, the tool")
        let parsed = MCPToolName.parse(wire)
        expect(
            parsed?.slug == "github" && parsed?.tool == "search_issues",
            "and parses back to exactly what composed it")
        expect(MCPToolName.parse("plain_name") == nil, "a name without the separator is not ours")

        let awkward = MCPToolName.compose(slug: "github", tool: "search issues/now")
        expect(
            awkward.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") },
            "a name only ever uses characters both providers accept")
        let long = MCPToolName.compose(slug: "github", tool: String(repeating: "x", count: 200))
        expect(long.count <= MCPToolName.maxLength, "and never exceeds the tighter provider's cap")
        expect(
            MCPToolName.parse(long)?.slug == "github",
            "the handle is the half that survives a trim, because it is what routes the call")
    }

    static func toolListsDropWhatCannotBeCalled() {
        let listed = JSONValue([
            "tools": [
                ["name": "read_file", "description": "Reads", "inputSchema": ["type": "object"]],
                ["description": "no name here"],
                ["name": "write_file"]
            ]
        ])
        let id = UUID()
        let tools = MCPTool.list(listed, serverID: id, serverSlug: "fs", serverTitle: "Files")
        expect(tools.count == 2, "an entry without a name is dropped rather than offered")
        expect(tools.first?.wireName == "fs__read_file", "a tool carries the handle that routes it")
        expect(
            tools.last?.inputSchema.objectValue?["type"]?.stringValue == "object",
            "a tool without a schema still gets one the providers accept")
        let ai = tools.first?.aiTool
        expect(
            ai?.origin == "Files" && ai?.title == "read_file",
            "the transcript pair travels with the tool, so the AI layer never parses a wire name")
    }

    static func outputFlattensToWhatAModelCanRead() {
        let text = MCPToolOutput.flatten(
            JSONValue(["content": [["type": "text", "text": "one"], ["type": "text", "text": "two"]]]))
        expect(text.content == "one\ntwo" && !text.isError, "text blocks join in order")

        let failed = MCPToolOutput.flatten(
            JSONValue(["isError": true, "content": [["type": "text", "text": "denied"]]]))
        expect(failed.isError, "a tool's own failure stays marked as one")

        let image = MCPToolOutput.flatten(JSONValue(["content": [["type": "image", "data": "…"]]]))
        expect(
            image.content.contains("omitted"),
            "a picture is named rather than inlined into a text context")

        let structured = MCPToolOutput.flatten(JSONValue(["structuredContent": ["count": 2]]))
        expect(structured.content.contains("count"), "structured-only output is read as JSON")
        expect(
            MCPToolOutput.flatten(JSONValue([:])).content.isEmpty == false,
            "an empty answer still says something rather than nothing")
    }

    static func trustDecidesFromStandingAndChatGrants() {
        expect(
            MCPTrustPolicy.decide(trust: .never, isGrantedForChat: true) == .refuse,
            "a withheld server stays withheld, whatever a chat granted")
        expect(
            MCPTrustPolicy.decide(trust: .always, isGrantedForChat: false) == .allow,
            "a trusted server never asks again")
        expect(
            MCPTrustPolicy.decide(trust: .ask, isGrantedForChat: false) == .ask,
            "the first call of a chat is asked about")
        expect(
            MCPTrustPolicy.decide(trust: .ask, isGrantedForChat: true) == .allow,
            "and the rest of that chat is not")
    }

    static func addressingTakesOnlyAKnownHandle() {
        let slugs: Set<String> = ["github", "files"]
        let addressed = MCPComposerAddress.parse("@github list my issues", slugs: slugs)
        expect(
            addressed.slug == "github" && addressed.rest == "list my issues",
            "a handle scopes the turn and leaves the composer's text behind")
        expect(
            MCPComposerAddress.parse("@GitHub hello", slugs: slugs).slug == "github",
            "a handle is matched however it was capitalised")

        let unknown = MCPComposerAddress.parse("@nosuch hello", slugs: slugs)
        expect(
            unknown.slug == nil && unknown.rest == "@nosuch hello",
            "an unknown handle is text, and is sent exactly as typed")
        expect(
            MCPComposerAddress.parse("email me @github", slugs: slugs).slug == nil,
            "only a leading handle addresses a server")
        expect(MCPComposerAddress.parse("@", slugs: slugs).slug == nil, "a bare @ addresses nothing")
        expect(
            MCPComposerAddress.parse("@files", slugs: slugs).rest.isEmpty,
            "a handle with nothing after it leaves an empty turn rather than its own text")
    }

    static func settingsPersistAndKeepHandlesApart() {
        let suite = "mcp-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            expect(false, "the harness can open its own defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MCPSettingsStore(defaults: defaults)
        store.save(
            MCPServer(name: "GitHub", transport: .http(url: "https://x/mcp", headerName: "Authorization")))
        store.save(
            MCPServer(name: "GitHub", transport: .stdio(command: "npx", arguments: [], environmentKeys: [])))
        expect(store.servers.count == 2, "two servers may honestly share a name")
        expect(
            Set(store.servers.map(\.slug)).count == 2,
            "but never a handle, or `@slug` would name both")

        var edited = store.servers[0]
        edited.trust = .always
        store.save(edited)
        expect(store.servers.count == 2, "saving an existing server updates it rather than adding")
        expect(store.server(id: edited.id)?.trust == .always, "and keeps what was edited")

        let reloaded = MCPSettingsStore(defaults: defaults)
        expect(
            reloaded.servers.map(\.slug) == store.servers.map(\.slug),
            "servers survive a relaunch")
        expect(reloaded.server(slug: "github") != nil, "and stay reachable by handle")

        store.remove(id: edited.id)
        expect(store.servers.count == 1, "removal takes exactly one")
    }

    /// The same servers, shaped for the routes whose own client runs them.
    static func serversBecomeWhatACLICanRunItself() {
        var remote = MCPServer(
            name: "Linear", slug: "linear",
            transport: .http(url: "https://mcp.linear.app/mcp", headerName: "Authorization"))
        remote.oauth = true
        expect(
            remote.toolServer(headerValue: "", environment: [:], bearerToken: "tok-9")?.transport
                == .url(
                    "https://mcp.linear.app/mcp", headerName: "Authorization",
                    headerValue: "Bearer tok-9"),
            "an OAuth server lends the session's token as the header Tinycast itself would send")
        expect(
            remote.toolServer(headerValue: "", environment: [:], bearerToken: nil) == nil,
            "and an OAuth server nobody is signed into is not offered at all")
        var switched = MCPServer(
            name: "Switched", slug: "switched",
            transport: .http(url: "https://switched.example/mcp", headerName: "X-Api-Key"))
        switched.oauth = true
        expect(
            switched.toolServer(headerValue: "stale", environment: [:], bearerToken: "tok-1")?
                .transport
                == .url(
                    "https://switched.example/mcp", headerName: "Authorization",
                    headerValue: "Bearer tok-1"),
            "a lent token always goes as Authorization, never under a header name left from before")

        let open = MCPServer(
            name: "Open", slug: "open",
            transport: .http(url: "https://open.example/mcp", headerName: "Authorization"))
        expect(
            open.toolServer(headerValue: "", environment: [:], bearerToken: nil)?.transport
                == .url("https://open.example/mcp", headerName: "Authorization", headerValue: ""),
            "a server that needs no credential is still offered, with no header to send")

        let header = MCPServer(
            name: "Notes", slug: "notes",
            transport: .http(url: "https://notes.example/mcp", headerName: " X-Api-Key "))
        expect(
            header.toolServer(headerValue: "k1", environment: [:], bearerToken: nil)?.transport
                == .url("https://notes.example/mcp", headerName: "X-Api-Key", headerValue: "k1"),
            "a header-authenticated server carries its own name and value, trimmed")

        let local = MCPServer(
            name: "Files", slug: "files",
            transport: .stdio(
                command: "/bin/node", arguments: ["s.js"], environmentKeys: ["API_KEY"]))
        expect(
            local.toolServer(
                headerValue: "", environment: ["API_KEY": "s3cret", "OTHER": "x"],
                bearerToken: nil)?
                .transport
                == .command(
                    path: "/bin/node", arguments: ["s.js"], environment: ["API_KEY": "s3cret"]),
            "a local server takes only the variables it declared, never the whole secret item")
        expect(
            local.toolServer(headerValue: "", environment: [:], bearerToken: nil)?.title == "Files",
            "and both kinds keep the handle and title a transcript row is written from")
        expect(
            MCPServer(
                name: "Empty", slug: "empty",
                transport: .stdio(
                    command: "", arguments: [], environmentKeys: [])
            )
            .toolServer(headerValue: "", environment: [:], bearerToken: nil) == nil,
            "a server with no command is nothing a CLI could start")
    }

    /// Codex and Claude start their own copy of a local server; Tinycast's would be the second.
    static func onlyOneCopyOfALocalServerRuns() {
        let local = MCPServer(
            name: "Files", slug: "files",
            transport: .stdio(command: "/bin/node", arguments: [], environmentKeys: []))
        let remote = MCPServer(
            name: "Linear", slug: "linear",
            transport: .http(url: "https://mcp.linear.app/mcp", headerName: "Authorization"))
        expect(
            local.runsInTinycast(whileCLIRouteSelected: false),
            "on an API route Tinycast runs a local server, since it is the one calling it")
        expect(
            !local.runsInTinycast(whileCLIRouteSelected: true),
            "on Codex or Claude it leaves the local server to the CLI's own copy")
        expect(
            remote.runsInTinycast(whileCLIRouteSelected: true),
            "while a remote one stays connected: a session, no process, and a live status row")
    }

    /// `文件` once slugged to `文件`, which sanitised to `__` and could never be routed back.
    static func nonASCIINamesStillMakeAHandle() {
        let slug = MCPSlug.normalize("文件")
        expect(slug == "wen-jian", "a Chinese name is transliterated, got \(slug)")
        expect(
            MCPSlug.normalize("Café Tools") == "cafe-tools", "diacritics are stripped, not dropped")
        expect(
            MCPSlug.normalize("数据库 DB").allSatisfy { $0.isASCII },
            "a mixed name still yields an ASCII handle")
    }

    static func wireNamesAreLookedUpNotParsed() {
        let id = UUID()
        func tool(_ name: String, slug: String = "files") -> MCPTool {
            MCPTool(
                serverID: id, serverSlug: slug, serverTitle: "文件", name: name, description: "",
                inputSchema: .object([:]))
        }
        let long = String(repeating: "browser_navigate_and_capture_", count: 4)
        let tools = [
            tool(long + "screenshot"), tool(long + "pdf"), tool("get.file"), tool("get_file"),
            tool("读取")
        ]
        let wire = tools.map(\.wireName)
        expect(Set(wire).count == wire.count, "trimmed or sanitised names never collide")
        expect(wire.allSatisfy { $0.count <= MCPToolName.maxLength }, "every name fits the cap")
        expect(
            wire.allSatisfy { name in
                name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }
            },
            "and is provider-safe")
        expect(wire[3] == "files__get_file", "an untouched name stays readable")
        expect(
            MCPToolName.compose(slug: "files", tool: "读取") == wire[4],
            "the same tool composes the same wire name every time")
        let routes = MCPToolRoutes(tools)
        for (index, name) in wire.enumerated() {
            expect(
                routes.tool(named: name)?.name == tools[index].name,
                "\(name) routes back to the tool's own name, not the trimmed one")
        }
        expect(routes.tool(named: "files__nothing") == nil, "an unknown name routes nowhere")
        // A slug saved before transliteration existed still routes, since nothing parses it.
        let legacy = tool("search", slug: "文件")
        expect(
            MCPToolRoutes([legacy]).tool(named: legacy.wireName)?.serverSlug == "文件",
            "an old non-ASCII handle is found by lookup")
    }

    static func theHandshakeIsNegotiatedAndPaged() {
        expect(
            MCPProtocol.negotiatedVersion(.object(["protocolVersion": .string("2024-11-05")]))
                == "2024-11-05", "an older version the server picked is held to")
        expect(
            MCPProtocol.negotiatedVersion(.object(["protocolVersion": .string("1999-01-01")]))
                == MCPProtocol.version, "an unknown one falls back to Tinycast's own")
        expect(MCPProtocol.negotiatedVersion(.object([:])) == MCPProtocol.version, "and so does none")
        expect(
            MCPProtocol.nextCursor(.object(["nextCursor": .string("p2")])) == "p2",
            "a cursor asks for another page")
        expect(
            MCPProtocol.nextCursor(.object(["nextCursor": .string("")])) == nil
                && MCPProtocol.nextCursor(.object([:])) == nil, "an empty or absent one ends the list")
        expect(MCPProtocol.timeout(for: "initialize") == .seconds(120), "a first npx gets two minutes")
        expect(MCPProtocol.timeout(for: "tools/call") == .seconds(300), "a tool call five")
        expect(MCPProtocol.timeout(for: "tools/list") == .seconds(30), "anything else thirty seconds")
        guard let data = try? MCPProtocol.reply(toRequest: .string("p1"), method: "ping"),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return expect(false, "a ping reply encodes") }
        expect(
            object["id"] as? String == "p1" && object["result"] is [String: Any]
                && object["error"] == nil, "a ping is answered with an empty result")
        let declined = (try? MCPProtocol.reply(toRequest: .number(2), method: "sampling/createMessage"))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        expect(declined?["error"] != nil, "anything else is still declined")
    }

    static func legacyStreamsAreReadByEventName() {
        var stream = MCPEventStream()
        expect(stream.feed(Data("event: endpoint\nda".utf8)).isEmpty, "half an event waits")
        let events = stream.feed(
            Data("ta: /messages?session=1\n\n: keepalive\n\nevent: message\r\ndata: {}\r\n\r\n".utf8))
        expect(
            events == [
                .init(name: "endpoint", data: "/messages?session=1"), .init(name: "message", data: "{}")
            ], "named events arrive whole, comments skipped, CRLF accepted")
        let base = URL(string: "https://mcp.test:8443/sse")!
        expect(
            MCPEventStream.endpoint("/messages?session=1", relativeTo: base)?.absoluteString
                == "https://mcp.test:8443/messages?session=1", "a relative endpoint joins the stream's")
        expect(
            MCPEventStream.endpoint("https://evil.test/messages", relativeTo: base) == nil,
            "an endpoint on another origin is refused")
    }

    static func sharedConfigurationImports() {
        let claude = """
            {"mcpServers": {
              "filesystem": {"command": "npx",
                             "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                             "env": {"DEBUG": "1"}},
              "linear": {"url": "https://mcp.linear.app/sse",
                         "headers": {"Authorization": "Bearer x", "X-Team": "a"}},
              "off": {"command": "uvx mcp-server-time", "disabled": true}
            }}
            """
        guard let entries = try? MCPServerImport.parse(claude) else {
            return expect(false, "a Claude Desktop config imports")
        }
        expect(entries.map(\.server.name) == ["filesystem", "linear", "off"], "every server, in order")
        expect(
            entries[0].server.transport
                == .stdio(
                    command: "npx", arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                    environmentKeys: ["DEBUG"]) && entries[0].environment == ["DEBUG": "1"],
            "a command keeps its arguments and environment")
        expect(
            entries[1].server.transport == .http(url: "https://mcp.linear.app/sse", headerName: "Authorization")
                && entries[1].headerValue == "Bearer x" && entries[1].dropped == ["header X-Team"],
            "a URL keeps its auth header and names the one it could not keep")
        expect(
            entries[2].server.transport
                == .stdio(command: "uvx", arguments: ["mcp-server-time"], environmentKeys: [])
                && !entries[2].server.isEnabled, "a one-string command is split; disabled stays off")
        let vscode = #"{"servers": {"gh": {"type": "http", "url": "https://api.githubcopilot.com/mcp/"}}}"#
        expect((try? MCPServerImport.parse(vscode))?.first?.server.name == "gh", "VS Code's shape imports")
        expect(
            (try? MCPServerImport.parse(#"{"command": "node", "args": ["s.js"], "name": "One"}"#))?
                .first?.server.name == "One", "a single bare server imports")
        do {
            _ = try MCPServerImport.parse("not json")
            expect(false, "plain text is refused")
        } catch {
            expect(error as? MCPServerImport.Failure == .notJSON, "plain text is refused as not JSON")
        }
        do {
            _ = try MCPServerImport.parse(#"{"mcpServers": {}}"#)
            expect(false, "an empty map is refused")
        } catch {
            expect(error as? MCPServerImport.Failure == .noServers, "an empty map names no server")
        }

        let suite = "mcp-import-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MCPSettingsStore(defaults: defaults)
        for entry in store.newEntries(in: entries) { store.save(entry.server) }
        expect(store.servers.count == 3, "an import adds every new server")
        expect(store.server(slug: "filesystem") != nil, "each under a derived handle")
        let again = try? MCPServerImport.parse(claude)
        expect(store.newEntries(in: again ?? []).isEmpty, "pasting the same JSON twice adds nothing")
        let chinese = try? MCPServerImport.parse(#"{"mcpServers": {"文件": {"command": "files-mcp"}}}"#)
        for entry in store.newEntries(in: chinese ?? []) { store.save(entry.server) }
        expect(store.server(slug: "wen-jian") != nil, "a Chinese server name imports with an ASCII handle")
        expect(
            MCPServerImport.Summary(added: 2, skipped: 1, dropped: ["linear: header X-Team"]).message
                == "Imported 2 servers. 1 was already set up. Not kept: linear: header X-Team.",
            "the summary says what happened")
    }
}
