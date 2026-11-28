import Foundation
import Testing

@testable import Tinycast

extension AIProviderTests {
    // MARK: Codex arguments

    @Test func everyOneOfTheReadersServersIsDisabledByName() {
        let arguments = LaunchFixtures.codexArguments
        #expect(arguments.contains("mcp_servers.computer-use.enabled=false"))
        #expect(arguments.contains("mcp_servers.files.enabled=false"), "one named like ours too")
    }

    /// No table of the reader's merges into a name of Tinycast's own.
    @Test func tinycastsServersGoByNamesOfTheirOwn() {
        let arguments = LaunchFixtures.codexArguments
        #expect(arguments.contains("mcp_servers.tinycast-files.enabled=true"))
        #expect(!arguments.contains { $0.hasPrefix("mcp_servers.files.") && !$0.hasSuffix("=false") })
    }

    @Test func aLocalServerWithVariablesArrivesThroughAShellThatRenamesThem() {
        let arguments = LaunchFixtures.codexArguments
        #expect(arguments.contains(#"mcp_servers.tinycast-files.command="/bin/sh""#))
        #expect(arguments.contains(LaunchFixtures.renamingArguments))
    }

    /// Codex forwards only the variables a server's launch lists.
    @Test func aLocalServersEnvironmentIsNamedRatherThanCarried() {
        #expect(LaunchFixtures.codexArguments.contains(LaunchFixtures.forwardedVariables))
    }

    @Test func anOAuthEndpointLendsItsTokenThroughTheVariableCodexReads() {
        #expect(
            LaunchFixtures.codexArguments.contains(
                #"mcp_servers.tinycast-linear.bearer_token_env_var="TC_MCP_1_0""#))
    }

    @Test func anotherHeaderNameGoesThroughTheMapThatTakesOne() {
        #expect(LaunchFixtures.codexArguments.contains(LaunchFixtures.headerMapOverride))
    }

    /// `ps` shows argv to every user on the Mac.
    @Test(arguments: ["s3cret", "tok-123", "k1"])
    func noSecretValueReachesArgv(_ secret: String) {
        #expect(!LaunchFixtures.codexArguments.contains { $0.contains(secret) })
    }

    @Test func theValuesRideTheChildsEnvironmentInstead() throws {
        let environment = try #require(
            CodexMCPLaunch.environment(
                servers: [LaunchFixtures.stdio, LaunchFixtures.oauth, LaunchFixtures.custom]))
        #expect(environment["TC_MCP_0_0"] == "s3cret")
        #expect(environment["TC_MCP_2_0"] == "k1")
        #expect(environment["TC_MCP_1_0"] == "tok-123", "a bearer token loses its prefix, as Codex adds it")
    }

    @Test func aServerThatNeedsNoCredentialGoesToCodexWithNoHeaderAndNoVariable() {
        let open = AIToolServer(
            handle: "open", title: "Open",
            transport: .url("https://open.example/mcp", headerName: "Authorization", headerValue: ""))
        let arguments = CodexMCPLaunch.arguments(servers: [open], disabling: [])
        #expect(arguments.contains(#"mcp_servers.tinycast-open.url="https://open.example/mcp""#))
        #expect(!arguments.contains { $0.contains("bearer_token") || $0.contains("headers") })
        #expect(CodexMCPLaunch.environment(servers: [open]) == [:])
    }

    @Test func aPathWithAQuoteInItIsStillOneTOMLString() {
        let odd = AIToolServer(
            handle: "odd", title: "Odd",
            transport: .command(path: #"/tmp/we"ird\bin"#, arguments: [], environment: [:]))
        let arguments = CodexMCPLaunch.arguments(servers: [odd], disabling: [])
        #expect(arguments.contains(#"mcp_servers.tinycast-odd.command="/tmp/we\"ird\\bin""#))
    }

    @Test func controlCharactersAndDeleteBecomeEscapesTOMLAccepts() {
        #expect(
            CodexMCPLaunch.quoted("a\r\nb\tc\u{1}\u{7F}é\"\\")
                == #""a\u000D\u000Ab\u0009c\u0001\u007Fé\"\\""#)
    }

    @Test func anArgumentCarryingAWindowsLineEndingLeavesCodexsConfigLoadable() {
        let lines = AIToolServer(
            handle: "lines", title: "Lines",
            transport: .command(path: "/bin/echo", arguments: ["a\r\nb"], environment: [:]))
        let arguments = CodexMCPLaunch.arguments(servers: [lines], disabling: [])
        #expect(arguments.contains(#"mcp_servers.tinycast-lines.args=["a\u000D\u000Ab"]"#))
    }

    @Test(arguments: [("tinycast-files", "files"), ("files", nil), ("tinycast-", nil)] as [(String, String?)])
    func aNameCodexReportsMapsBackToAHandleOnlyWhenItIsTinycasts(_ name: String, _ handle: String?) {
        #expect(CodexMCPLaunch.handle(ofServer: name) == handle)
    }

    @Test func aReadersServerNamedLikeAnArmedOneOfOursIsCaughtBeforeLaunch() {
        let servers = [LaunchFixtures.stdio]
        #expect(
            CodexMCPLaunch.takenName(servers: servers, foreignNames: ["tinycast-files"]) == "tinycast-files")
        #expect(CodexMCPLaunch.takenName(servers: servers, foreignNames: ["files"]) == nil)
    }

    @Test func theReadersServersAreEveryNameTheListingReports() {
        let listing = #"[{"name":"a","enabled":true},{"name":"b c"}]"#
        #expect(CodexMCPLaunch.foreignNames(listing: listing) == ["a", "b c"])
    }

    @Test(arguments: ["warning: not json", #"{"name":"a"}"#, #"[{"name":"a"},{"enabled":true}]"#])
    func outputThatIsNotTheListReadsAsUnknownNeverAsEmpty(_ listing: String) {
        #expect(CodexMCPLaunch.foreignNames(listing: listing) == nil)
    }

    /// Spaces and other scripts are addressable; a dot or `=` keeps `-c` from naming a server.
    @Test(
        arguments: [
            (["ok", "日本", "has space", "has.dot"], "has.dot"),
            (["a=b"], "a=b"),
            (["ok", "日本", "has space"], nil)
        ] as [([String], String?)])
    func onlyADotOrEqualsSignMakesAServerUnaddressable(_ names: [String], _ unaddressable: String?) {
        #expect(CodexMCPLaunch.unaddressableName(names) == unaddressable)
    }

    // MARK: Codex variables, run

    /// Only running the launch proves a server gets its own names; `printenv` stands in for it.
    @Test func aServerReadsItsValueUnderItsOwnName() async throws {
        let scratch = try ScratchDirectory("codex-launch")
        let launch = CodexMCPLaunch.command(
            path: "/usr/bin/printenv", arguments: ["API_KEY"],
            environment: ["API_KEY": "s3cret"], server: 0)
        let read = await LaunchFixtures.run(launch, environment: ["TC_MCP_0_0": "s3cret"], in: scratch)
        #expect(read.output == "s3cret\n", "which Codex alone cannot give it")
    }

    @Test func theDerivedNameIsGoneSoTheValueDoesNotReachTheServerTwice() async throws {
        let scratch = try ScratchDirectory("codex-launch")
        let launch = CodexMCPLaunch.command(
            path: "/usr/bin/printenv", arguments: ["TC_MCP_0_0"],
            environment: ["API_KEY": "s3cret"], server: 0)
        let read = await LaunchFixtures.run(launch, environment: ["TC_MCP_0_0": "s3cret"], in: scratch)
        #expect(read.output == "")
        #expect(read.status == 1, "printenv ran and found nothing")
    }

    @Test func aNameTheShellCannotExportIsNotForwardedAndTheServerLaunchesDirectly() {
        let odd = AIToolServer(
            handle: "odd", title: "Odd",
            transport: .command(path: "/usr/bin/true", arguments: [], environment: ["NOT-A-NAME": "hidden"]))
        let arguments = CodexMCPLaunch.arguments(servers: [odd], disabling: [])
        #expect(arguments.contains(#"mcp_servers.tinycast-odd.command="/usr/bin/true""#))
        #expect(arguments.contains("mcp_servers.tinycast-odd." + "env" + "_vars=[]"))
        #expect(
            CodexMCPLaunch.environment(servers: [odd]) == [:],
            "its value never enters the app-server's environment under a name nobody reads")
    }

    /// Two spellings of handle and key must never meet in one variable, or a secret changes hands.
    @Test func everySecretGetsAVariableOfItsOwnHoweverHandlesAndKeysAreSpelled() throws {
        let environment = try #require(CodexMCPLaunch.environment(servers: LaunchFixtures.collidingServers))
        #expect(environment.count == 8)
        #expect(Set(environment.values) == ["one", "two", "three", "four", "five", "six", "seven", "eight"])
    }

    @Test func eachLocalServerReadsOnlyItsOwnValuesUnderItsOwnNames() async throws {
        let scratch = try ScratchDirectory("codex-launch")
        let servers = LaunchFixtures.collidingServers
        let environment = try #require(CodexMCPLaunch.environment(servers: servers))
        var delivered: [String] = []
        for (index, server) in servers.enumerated() {
            guard case .command(let path, _, let values) = server.transport else { continue }
            for key in values.keys.sorted() {
                let launch = CodexMCPLaunch.command(
                    path: path, arguments: [key], environment: values, server: index)
                delivered.append(
                    await LaunchFixtures.run(launch, environment: environment, in: scratch).output)
            }
        }
        #expect(delivered == ["one\n", "two\n", "four\n", "three\n", "six\n", "seven\n", "eight\n"])
    }

    @Test func aKeySpelledLikeADerivedNameStillReadsItsOwnValueAsDoTheKeysAfterIt() async throws {
        let scratch = try ScratchDirectory("codex-launch")
        let shadowing = ["TC_MCP_0_0": "zero", "TC_MCP_0_1": "one", "Z": "zed"]
        let derived = try #require(
            CodexMCPLaunch.environment(servers: [LaunchFixtures.local("s", shadowing)]))
        var reads: [InstalledAIProbe.Result] = []
        for key in ["TC_MCP_0_0", "TC_MCP_0_1", "Z", "TC_MCP_0_2"] {
            let launch = CodexMCPLaunch.command(
                path: "/usr/bin/printenv", arguments: [key], environment: shadowing, server: 0)
            reads.append(await LaunchFixtures.run(launch, environment: derived, in: scratch))
        }
        #expect(reads.map(\.output) == ["zero\n", "one\n", "zed\n", ""])
        #expect(reads.map(\.status) == [0, 0, 0, 1], "every printenv ran")
    }

    @Test func aTenthValueAndBeyondReadWholeNotAsTheFirstFollowedByADigit() async throws {
        let scratch = try ScratchDirectory("codex-launch")
        let many = Dictionary(uniqueKeysWithValues: (0...10).map { ("K\($0)", "v\($0)") })
        let derived = try #require(CodexMCPLaunch.environment(servers: [LaunchFixtures.local("m", many)]))
        var reads: [String] = []
        for key in many.keys.sorted() {
            let launch = CodexMCPLaunch.command(
                path: "/usr/bin/printenv", arguments: [key], environment: many, server: 0)
            reads.append(await LaunchFixtures.run(launch, environment: derived, in: scratch).output)
        }
        #expect(reads == many.keys.sorted().map { "\(many[$0, default: ""])\n" })
    }

    @Test func aRepeatedVariableRefusesTheLaunchRatherThanKeepingOneValue() {
        let repeated = [(name: "TC_MCP_0_0", value: "a"), (name: "TC_MCP_0_0", value: "b")]
        #expect(CodexMCPLaunch.distinct(repeated) == nil)
    }

    // MARK: Claude configuration

    /// The file is the only place Claude's secrets go.
    @Test func claudesConfigurationCarriesALocalServersCommandAndEnvironment() throws {
        let files = try LaunchFixtures.claudeEntry("files")
        #expect(files["command"] as? String == "/bin/node")
        #expect(files["args"] as? [String] == ["s.js"])
        #expect(files["env"] as? [String: String] == ["API_KEY": "s3cret"])
    }

    @Test func aRemoteServerCarriesTheHeaderTinycastWouldHaveSentItself() throws {
        let linear = try LaunchFixtures.claudeEntry("linear")
        #expect(linear["type"] as? String == "http")
        #expect(linear["headers"] as? [String: String] == ["Authorization": "Bearer tok-123"])
    }

    @Test func aServerThatNeedsNoCredentialGoesToClaudeWithNoHeaders() {
        let bare = ClaudeMCPLaunch.configuration(servers: [
            AIToolServer(
                handle: "open", title: "Open",
                transport: .url("https://open.example/mcp", headerName: "Authorization", headerValue: ""))
        ])
        #expect(bare == #"{"mcpServers":{"open":{"type":"http","url":"https:\/\/open.example\/mcp"}}}"#)
    }

    @Test func claudesFlagsNameTheFileRouteConsentToTinycastAndCapTheTurn() {
        let arguments = LaunchFixtures.claudeArguments
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.contains("/tmp/m.json"))
        #expect(arguments.contains("--permission-prompt-tool"))
        #expect(arguments.contains("stdio"))
        #expect(LaunchFixtures.value(after: "--max-turns", in: arguments) == "25")
    }

    /// Claude has no cap without `--max-turns`.
    @Test func unlimitedRoundsPassNoMaxTurnsAtAll() {
        let uncapped = ClaudeMCPLaunch.arguments(
            configurationPath: "/tmp/m.json", handles: ["files"], rounds: nil)
        #expect(uncapped.contains("--mcp-config"))
        #expect(!uncapped.contains("--max-turns"))
    }

    /// Denying every tool would take the MCP ones with it.
    @Test func claudeIsNeverToldToDenyEveryTool() {
        #expect(!LaunchFixtures.claudeArguments.contains("--disallowedTools"))
    }

    /// A reader's bypassPermissions default would otherwise skip the question.
    @Test func thePermissionModeIsPinned() {
        #expect(
            LaunchFixtures.value(after: "--permission-mode", in: LaunchFixtures.claudeArguments) == "default")
    }

    /// An ask rule outranks any allow rule of the reader's.
    @Test func everyArmedServerHasAnAskRuleAndTheSettingsHoldNothingElse() throws {
        let text = try #require(LaunchFixtures.value(after: "--settings", in: LaunchFixtures.claudeArguments))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(
            (settings["permissions"] as? [String: Any])?["ask"] as? [String] == ["mcp__files", "mcp__linear"])
        #expect(settings.count == 1)
    }

    /// The first separator is the split: a handle is letters, digits and `-`, a tool is not.
    @Test(
        arguments: [
            ("mcp__files__read_file", AIToolServerCall(handle: "files", tool: "read_file")),
            ("mcp__files__read__file", AIToolServerCall(handle: "files", tool: "read__file")),
            ("Bash", nil),
            ("mcp__files", nil)
        ] as [(String, AIToolServerCall?)])
    func aWireNameRoutesBackToItsServerAndToolOnlyWhenItIsOurs(_ name: String, _ call: AIToolServerCall?) {
        #expect(ClaudeMCPLaunch.route(name) == call)
    }

    // MARK: Codex elicitations

    /// Every other server request stays declined, so only a tool call may become a question.
    @Test func aToolCallElicitationNamesItsServerAndItsMessageNamesTheTool() throws {
        let call = try #require(
            CodexElicitation(
                params: [
                    "serverName": .string("files"),
                    "message": .string("Allow the files MCP server to run tool \u{201C}read\u{201D}?"),
                    "_meta": .object([
                        "codex_approval_kind": .string("mcp_tool_call"),
                        "persist": .array([.string("session"), .string("always")])
                    ])
                ]))
        #expect(call.serverName == "files")
        #expect(call.toolName == "read")
        #expect(call.namedTool == nil)
    }

    @Test func metaToolNameWhenSentIsTheNameTiedToThisCall() throws {
        let named = try #require(
            CodexElicitation(
                params: [
                    "serverName": .string("files"),
                    "_meta": .object([
                        "codex_approval_kind": .string("mcp_tool_call"),
                        "tool_name": .string("write"), "tool_title": .string("Write")
                    ])
                ]))
        #expect(named.namedTool == "write")
        #expect(named.toolName == "write")
    }

    @Test func aFormIsNotAToolCallAndIsNeverAskedAbout() {
        let form = CodexElicitation(
            params: [
                "serverName": .string("files"), "_meta": .object(["codex_approval_kind": .string("form")])
            ])
        #expect(form == nil)
    }

    @Test func anElicitationThatNamesNoServerIsNeverAskedAbout() {
        #expect(CodexElicitation(params: ["message": .string("hello")]) == nil)
    }

    @Test func theTwoAnswersAreTheTwoTheAppServerHonours() {
        #expect(CodexElicitation.Action.accept.rawValue == "accept")
        #expect(CodexElicitation.Action.decline.rawValue == "decline")
    }

    // MARK: Claude control frames

    /// The consent channel is the SDK's undocumented one; this is all of it Tinycast speaks.
    @Test func aCanUseToolFrameDecodesIntoTheIdToAnswerAndTheCallToAskAbout() throws {
        let request = try #require(ClaudeControlProtocol.request(try LaunchFixtures.canUseToolFrame()))
        #expect(request.id == "r1")
        #expect(request.call == AIToolServerCall(handle: "files", tool: "read"))
    }

    @Test func anAllowHandsTheArgumentsBackUntouchedOnOneLine() throws {
        let request = try #require(ClaudeControlProtocol.request(try LaunchFixtures.canUseToolFrame()))
        let allow = try #require(ClaudeControlProtocol.response(to: request, allowed: true, message: ""))
        let allowed = try LaunchFixtures.innerResponse(of: allow)
        #expect(allowed["behavior"] as? String == "allow")
        #expect((allowed["updatedInput"] as? [String: Any])?["path"] as? String == "/tmp")
        #expect(
            allowed["updatedPermissions"] == nil,
            "never a permission update, which would have the CLI write its own settings")
        #expect(allow.last == 0x0A, "the channel is newline framed")
    }

    @Test func aDenySaysSoWithTheReasonTheModelReadsAsTheResult() throws {
        let request = try #require(ClaudeControlProtocol.request(try LaunchFixtures.canUseToolFrame()))
        let deny = try #require(ClaudeControlProtocol.response(to: request, allowed: false, message: "no"))
        let denied = try LaunchFixtures.innerResponse(of: deny)
        #expect(denied["behavior"] as? String == "deny")
        #expect(denied["message"] as? String == "no")
    }

    @Test func aSubtypeTinycastDoesNotKnowIsNoToolQuestionYetIsStillAnswered() throws {
        let initialize = try LaunchFixtures.object(
            #"{"type":"control_request","request_id":"r2","request":{"subtype":"initialize"}}"#)
        #expect(ClaudeControlProtocol.request(initialize) == nil)
        #expect(ClaudeControlProtocol.unsupportedRequestID(initialize) == "r2")
        #expect(ClaudeControlProtocol.unsupportedRequestID(try LaunchFixtures.canUseToolFrame()) == nil)
    }

    /// The SDK's error response is what makes the CLI stop waiting on the request.
    @Test func anUnknownSubtypeGetsTheSDKsErrorResponse() throws {
        let data = try #require(ClaudeControlProtocol.error(to: "r2", message: "no"))
        let error = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let response = error["response"] as? [String: Any]
        #expect(error["type"] as? String == "control_response")
        #expect(response?["subtype"] as? String == "error")
        #expect(response?["request_id"] as? String == "r2")
    }
}

private enum LaunchFixtures {
    static let stdio = AIToolServer(
        handle: "files", title: "Files",
        transport: .command(
            path: "/usr/local/bin/node", arguments: ["server.js", "--root=/tmp"],
            environment: ["API_KEY": "s3cret"]))
    static let oauth = AIToolServer(
        handle: "linear", title: "Linear",
        transport: .url(
            "https://mcp.linear.app/mcp", headerName: "Authorization", headerValue: "Bearer tok-123"))
    static let custom = AIToolServer(
        handle: "notes", title: "Notes",
        transport: .url("https://notes.example/mcp", headerName: "X-Api-Key", headerValue: "k1"))

    /// The reader runs `computer-use` and a `files` of their own, named like Tinycast's.
    static let codexArguments = CodexMCPLaunch.arguments(
        servers: [stdio, oauth, custom], disabling: ["computer-use", "files"])

    static let renamingArguments =
        #"mcp_servers.tinycast-files.args=["-c","set -- \"$TC_MCP_0_0\" \"$@\"; "#
        + #"unset TC_MCP_0_0; export API_KEY=\"${1}\"; shift 1; "#
        + #"exec \"$@\"","tinycast-mcp","/usr/local/bin/node","server.js","--root=/tmp"]"#

    /// Spelled through a joined literal so no shell hook mistakes the key for a dotfile.
    static let forwardedVariables = "mcp_servers.tinycast-files." + "env" + #"_vars=["TC_MCP_0_0"]"#
    static let headerMapOverride =
        "mcp_servers.tinycast-notes." + "env" + #"_http_headers={"X-Api-Key"="TC_MCP_2_0"}"#

    static func local(_ handle: String, _ environment: [String: String]) -> AIToolServer {
        AIToolServer(
            handle: handle, title: handle,
            transport: .command(path: "/usr/bin/printenv", arguments: [], environment: environment))
    }

    /// Handles and keys whose spellings would meet in one variable under a careless scheme.
    static let collidingServers = [
        local("github-x", ["TOKEN": "one"]),
        local("github", ["X_TOKEN": "two"]),
        local("both", ["token": "three", "TOKEN": "four"]),
        AIToolServer(
            handle: "a", title: "a",
            transport: .url("https://a.example/mcp", headerName: "B-C", headerValue: "five")),
        local("a-b", ["C": "six"]),
        local("日本", ["TOKEN": "seven"]),
        local("中国", ["TOKEN": "eight"])
    ]

    /// What the launch printed to stdout, run with only the variables Codex would hand it.
    static func run(
        _ launch: (path: String, arguments: [String]), environment: [String: String],
        in scratch: ScratchDirectory
    ) async -> InstalledAIProbe.Result {
        await InstalledAIProbe.run(
            executable: URL(filePath: launch.path), arguments: launch.arguments, workspace: scratch.url,
            environment: environment.merging(["PATH": "/usr/bin:/bin"]) { value, _ in value })
    }

    static let claudeServers = [
        AIToolServer(
            handle: "files", title: "Files",
            transport: .command(path: "/bin/node", arguments: ["s.js"], environment: ["API_KEY": "s3cret"])),
        AIToolServer(
            handle: "linear", title: "Linear",
            transport: .url(
                "https://mcp.linear.app/mcp", headerName: "Authorization", headerValue: "Bearer tok-123"))
    ]

    static let claudeArguments = ClaudeMCPLaunch.arguments(
        configurationPath: "/tmp/m.json", handles: ["files", "linear"], rounds: 25)

    /// One server's record in Claude's MCP configuration, which must decode as `mcpServers`.
    static func claudeEntry(_ handle: String) throws -> [String: Any] {
        let configuration = try object(ClaudeMCPLaunch.configuration(servers: claudeServers))
        let entries = try #require(configuration["mcpServers"] as? [String: Any])
        return try #require(entries[handle] as? [String: Any])
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func object(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    static func canUseToolFrame() throws -> [String: Any] {
        try object(
            #"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","#
                + #""tool_name":"mcp__files__read","input":{"path":"/tmp"}}}"#)
    }

    /// The `control_response`'s own answer, inside its `response` envelope.
    static func innerResponse(of data: Data) throws -> [String: Any] {
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let envelope = try #require(decoded["response"] as? [String: Any])
        return try #require(envelope["response"] as? [String: Any])
    }
}
