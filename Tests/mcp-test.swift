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
}
