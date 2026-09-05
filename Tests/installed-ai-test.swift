import Foundation

@main
@MainActor
struct InstalledAITests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        guard let fixture = Fixture() else {
            expect(false, "the installed CLI fixture starts")
            return
        }
        defer { fixture.tearDown() }
        openCodeCatalogCarriesModelVariants()
        await openCodeRunsWithoutToolsAndDeletesItsSession(fixture)
        await claudeRunsBareWithoutToolsOrHistory(fixture)

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static func openCodeCatalogCarriesModelVariants() {
        let output = """
            provider/model
            {
              "name": "Model",
              "variants": {
                "low": {"reasoningEffort": "low"},
                "high": {"reasoningEffort": "high"}
              }
            }
            provider/plain
            {
              "name": "Plain",
              "variants": {}
            }
            """
        let models = InstalledAIModel.openCodeCatalog(output)
        expect(
            models.first?.efforts.map(\.id) == ["low", "high"],
            "OpenCode discovery keeps each model's supported reasoning variants")
        expect(models.last?.efforts.isEmpty == true, "models without variants show no effort picker")
    }

    private static func openCodeRunsWithoutToolsAndDeletesItsSession(_ fixture: Fixture) async {
        let events = await fixture.events(
            kind: .openCode, model: "provider/model", effort: "high")
        expect(events.contains(.text("OpenCode reply")), "OpenCode text reaches the provider stream")
        expect(events.last == .finished, "OpenCode finishes the provider stream")
        let arguments = fixture.read("opencode-args.log")
        expect(
            arguments.contains("--pure") && arguments.contains("--format")
                && arguments.contains("provider/model") && arguments.contains("--variant")
                && arguments.contains("high"),
            "OpenCode runs pure with JSON output, the chosen model and its variant")
        let configuration = fixture.read("opencode-environment.log")
        expect(
            configuration.contains("\"permission\":\"deny\"")
                && configuration.contains("\"share\":\"disabled\""),
            "OpenCode receives deny-all permissions and disabled sharing")
        let deleted = await fixture.awaitFile("deleted.log", containing: "ses_stub")
        if !deleted { print("OpenCode invocations: \(fixture.read("opencode-args.log"))") }
        expect(deleted, "OpenCode deletes the session created for the reply")
        fixture.expectPrompt("opencode-prompt.log")
    }

    private static func claudeRunsBareWithoutToolsOrHistory(_ fixture: Fixture) async {
        let events = await fixture.events(kind: .claude, model: "sonnet", effort: "xhigh")
        expect(events.contains(.text("Claude reply")), "Claude text reaches the provider stream")
        expect(events.last == .finished, "Claude finishes the provider stream")
        let arguments = fixture.read("claude-args.log")
        for flag in [
            "--bare", "--no-session-persistence", "--disable-slash-commands", "--tools",
            "--disallowedTools", "--strict-mcp-config", "--no-chrome"
        ] {
            expect(arguments.contains(flag), "Claude runs with \(flag)")
        }
        expect(
            arguments.contains("--effort") && arguments.contains("xhigh"),
            "Claude receives the chosen reasoning effort")
        fixture.expectPrompt("claude-prompt.log")
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let workspace: URL
    let executables: [InstalledAIKind: URL]

    init?() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "installed-ai-\(UUID().uuidString)", directoryHint: .isDirectory)
        workspace = root.appending(path: "workspace", directoryHint: .isDirectory)
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            var values: [InstalledAIKind: URL] = [:]
            for kind in [InstalledAIKind.claude, .openCode] {
                let executable = bin.appending(path: kind.command)
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: "Tests/ai-fixtures/installed-cli-stub.js"),
                    to: executable)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: executable.path)
                values[kind] = executable
            }
            executables = values
            let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
            setenv("PATH", bin.path + ":" + inheritedPath, 1)
            setenv("TC_INSTALLED_STUB_ROOT", root.path, 1)
        } catch {
            print("fixture setup failed: \(error)")
            return nil
        }
    }

    func events(kind: InstalledAIKind, model: String, effort: String?) async -> [AIStreamEvent] {
        guard let executable = executables[kind] else { return [] }
        let provider = InstalledCLIProvider(
            kind: kind, executable: kind == .openCode ? nil : executable,
            model: model, effort: effort, workspace: workspace)
        let request = AIRequest(
            instructions: "Follow the custom instruction.",
            messages: [
                AIMessage(role: .user, text: "First question"),
                AIMessage(role: .assistant, text: "First answer"),
                AIMessage(role: .user, text: "Final question")
            ])
        do {
            var events: [AIStreamEvent] = []
            for try await event in provider.stream(request) { events.append(event) }
            return events
        } catch {
            print("\(kind.title) stream failed: \(error)")
            return []
        }
    }

    func expectPrompt(_ name: String) {
        let prompt = read(name)
        InstalledAITests.expect(
            prompt.contains("Follow the custom instruction.")
                && prompt.contains("First question") && prompt.contains("First answer")
                && prompt.contains("Final question"),
            "the installed CLI receives instructions and conversation history through stdin")
    }

    func read(_ name: String) -> String {
        (try? String(contentsOf: root.appending(path: name), encoding: .utf8)) ?? ""
    }

    func awaitFile(_ name: String, containing value: String) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if read(name).contains(value) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return read(name).contains(value)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
