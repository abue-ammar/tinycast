import Foundation
import Synchronization

@main
@MainActor
struct TranslationTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        languagesPreserveDirection()
        try deepLWireBoundaries()
        try await aiOutputBoundaries()
        try await deepLNetworking()
        try preferencesRemainIndependent()
        await sessionDebounceAndCancellation()
        await sessionRejectsLateCompletions()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func languagesPreserveDirection() {
        let catalog = TranslationLanguages.ai(locale: Locale(identifier: "en"))
        expect(TranslationLanguages.matches("ZH_hAnt", "zh-Hant"), "case and separator normalize")
        expect(!TranslationLanguages.matches("zh-Hans", "zh-Hant"), "scripts remain distinct")
        expect(!TranslationLanguages.matches("en-US", "en-GB"), "regions remain distinct")
        let request = TranslationRequest(text: "Hello", sourceLanguage: nil, targetLanguage: "zh-Hans")
        expect(TranslationLanguages.supports(request, in: catalog), "AI supports automatic source")
        expect(!TranslationLanguages.supports(
            TranslationRequest(text: "Hello", sourceLanguage: "zz", targetLanguage: "zh-Hans"),
            in: catalog), "unknown source cannot send")
        expect(!TranslationLanguages.supports(
            TranslationRequest(text: "Hello", sourceLanguage: nil, targetLanguage: "auto"),
            in: catalog), "automatic detection cannot be a target")
        let languages = [
            TranslationLanguage(id: "en", name: "English", usableAsSource: true, usableAsTarget: false),
            TranslationLanguage(id: "en-US", name: "American English", usableAsSource: false, usableAsTarget: true),
            TranslationLanguage(id: "zh", name: "Chinese", usableAsSource: true, usableAsTarget: false),
            TranslationLanguage(id: "zh-Hans", name: "Simplified", usableAsSource: false, usableAsTarget: true),
            TranslationLanguage(id: "zh-Hant", name: "Traditional", usableAsSource: false, usableAsTarget: true)
        ]
        let swapped = TranslationLanguages.swapped(
            source: nil, target: "ZH_hAnt", detectedSource: "EN", in: languages)
        expect(swapped?.source == "zh" && swapped?.target == "en-US", "swap uses direction-specific mappings")
        expect(TranslationLanguages.swapped(
            source: nil, target: "zh-Hans", detectedSource: nil, in: languages) == nil,
            "automatic source cannot swap without a detection")
        expect(TranslationLanguages.swapped(
            source: "en-GB", target: "zh-Hans", detectedSource: nil, in: languages) == nil,
            "swap cannot silently change a region")
        expect(TranslationLanguages.swapped(
            source: "zh", target: "en-US", detectedSource: nil, in: languages)?.target == "zh-Hans",
            "a detected Chinese base maps only to Simplified Chinese")
    }

    static func preferencesRemainIndependent() throws {
        let suite = "TranslationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let ai = AISettingsStore(defaults: defaults)
        let connection = AIConnection(provider: .openAICompatible, models: ["chat", "translator"])
        ai.save(connection)
        ai.select(.api(connection: connection.id, model: "chat", effort: nil))
        let store = TranslationSettingsStore(defaults: defaults)
        expect(store.model == nil, "translation never adopts a configured chat route")
        let selection = AIModelSelection.api(connection: connection.id, model: "translator", effort: "low")
        store.select(selection)
        expect(ai.defaultModel?.model == "chat", "translation choice leaves chat route unchanged")
        store.select(.appleIntelligence)
        expect(store.model == selection, "non-API selections cannot overwrite the translation route")
        let binding = TranslationSettingsFile.modelBinding(store: store)
        let json = binding.read()
        store.select(nil)
        expect(binding.write(json).isEmpty && store.model == selection, "model JSON round-trips with effort")
        let invalid: [SettingsFileJSON] = [
            "model", .object(["connection": "bad", "model": "translator", "effort": .null]),
            .object(["connection": .string(connection.id.uuidString), "model": "  ", "effort": .null]),
            .object(["connection": .string(connection.id.uuidString), "model": "translator", "effort": 42]),
            .object(["connection": .string(connection.id.uuidString), "model": "translator"])
        ]
        for value in invalid {
            expect(binding.write(value) == [.invalidValue(.translationModel)], "malformed model is rejected")
            expect(store.model == selection, "malformed import preserves the previous route")
        }
        let missingConnection = UUID()
        let imported = SettingsFileJSON.object([
            "connection": .string(missingConnection.uuidString), "model": "not-installed", "effort": .null
        ])
        expect(binding.write(imported).isEmpty, "import order does not discard a route")
        expect(store.model == .api(connection: missingConnection, model: "not-installed", effort: nil),
            "missing destination is preserved for execution-time validation")
        let source = SettingsFileBinding(.translationSourceLanguage, store, \.sourceLanguage,
                                        accept: TranslationSettingsStore.sourceCode)
        let target = SettingsFileBinding(.translationTargetLanguage, store, \.targetLanguage,
                                        accept: TranslationSettingsStore.targetCode)
        expect(target.write("AUTO") == [.invalidValue(.translationTargetLanguage)], "target refuses auto")
        expect(source.write("  \n").count == 1, "source refuses whitespace")
        expect(target.write("future-Latn-XX").isEmpty, "unknown language survives until catalog validation")
        let reopened = TranslationSettingsStore(defaults: defaults)
        expect(reopened.model == store.model && reopened.targetLanguage == "future-Latn-XX",
            "independent model and unknown language survive a relaunch")
        expect(binding.write(.null).isEmpty && store.model == nil, "explicit null clears only translation route")
        expect(ai.defaultModel?.model == "chat", "clearing translation leaves chat unchanged")
    }

    static func expectFailure<T>(
        _ expected: DeepLTranslationAPI.Failure, _ message: String, _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            expect(false, message)
        } catch {
            expect(error as? DeepLTranslationAPI.Failure == expected, message)
        }
    }

    static func deepLWireBoundaries() throws {
        let text = "  Hello, 世界！\n\"quoted\" \\ path 😀  "
        let automatic = TranslationRequest(text: text, sourceLanguage: nil, targetLanguage: "zh-Hans")
        let body = try DeepLTranslationAPI.requestBody(for: automatic)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        expect(json?["source_lang"] == nil, "automatic source is absent from wire body")
        expect(json?["text"] as? [String] == [text], "wire text retains spaces, escapes, emoji and paragraphs")
        expect(json?["preserve_formatting"] as? Bool == true, "DeepL preserves original formatting")
        let explicit = try DeepLTranslationAPI.requestBody(for:
            TranslationRequest(text: text, sourceLanguage: "en-GB", targetLanguage: "zh-Hant"))
        let explicitJSON = try JSONSerialization.jsonObject(with: explicit) as? [String: Any]
        expect(explicitJSON?["source_lang"] as? String == "en-GB", "explicit source retains its region")
        expect(explicitJSON?["target_lang"] as? String == "zh-Hant", "target retains its script")
        let boundaryText = text + String(repeating: "x", count: 131_072 - body.count)
        let boundary = TranslationRequest(text: boundaryText, sourceLanguage: nil, targetLanguage: "zh-Hans")
        let boundaryBody = try DeepLTranslationAPI.requestBody(for: boundary)
        expect(boundaryBody.count == 131_072,
               "complete encoded body accepts the inclusive byte limit")
        expectFailure(.tooLong, "one encoded byte over limit is rejected") {
            try DeepLTranslationAPI.requestBody(for:
                TranslationRequest(text: boundaryText + "x", sourceLanguage: nil, targetLanguage: "zh-Hans"))
        }
        let result = try DeepLTranslationAPI.result(from:
            Data(#"{"translations":[{"text":"  你好！\n世界 😀  ","detected_source_language":"EN"}]}"#.utf8))
        expect(result.text == "  你好！\n世界 😀  " && result.detectedSourceLanguage == "EN",
               "successful translation preserves returned whitespace and detection")
        for invalid in [
            #"{"translations":[]}"#, #"{"translations":[{"text":"one"},{"text":"two"}]}"#,
            #"{"translations":[{"text":" \n "}]}"#, #"{"translations":[{"text":7}]}"#,
            #"{"translations":{}}"#, "not JSON"
        ] {
            expectFailure(.invalidTranslation, "malformed or blank response cannot be copied") {
                try DeepLTranslationAPI.result(from: Data(invalid.utf8))
            }
        }
        let catalog = try DeepLTranslationAPI.languages(from: Data(Self.languageJSON.utf8))
        expect(TranslationLanguages.supports(
            TranslationRequest(text: "test", sourceLanguage: "EN", targetLanguage: "ZH_hAnt"), in: catalog),
            "v3 directional catalog handles case and separators")
        expect(!TranslationLanguages.supports(
            TranslationRequest(text: "test", sourceLanguage: "en-US", targetLanguage: "en"), in: catalog),
            "target-only and source-only entries cannot reverse their capabilities")
        for invalid in ["[]", "{}", #"[{"lang":"en","name":"English","usable_as_source":true,"usable_as_target":false}]"#,
                        #"[{"lang":"en","name":"English","usable_as_source":"true","usable_as_target":true}]"#] {
            expectFailure(.invalidLanguages, "unusable language catalogs cannot enable requests") {
                try DeepLTranslationAPI.languages(from: Data(invalid.utf8))
            }
        }
        expect(DeepLTranslationAPI.failure(for: 401) == .invalidKey
               && DeepLTranslationAPI.failure(for: 403) == .invalidKey, "auth failures share key recovery")
        expect(DeepLTranslationAPI.failure(for: 429) == .rateLimited, "rate limiting differs from quota")
        expect(DeepLTranslationAPI.failure(for: 456) == .quotaExceeded, "character quota has its own recovery")
        expect(DeepLTranslationAPI.failure(for: 413) == .tooLong, "remote and local size rejection agree")
        expect(DeepLTranslationAPI.failure(for: 503) == .unavailable, "service failure is not an auth failure")
        expect(DeepLTranslationAPI.failure(for: 400) == .rejected(400), "other rejection retains status only")
    }

    static func aiOutputBoundaries() async throws {
        let provider = FixtureAI(events: [.thinking, .reasoning("private reasoning"), .text("  你好"),
                                          .usage(AIUsage(outputTokens: 4)), .text("！\n世界 😀  "), .finished])
        let request = TranslationRequest(text: "  Hello!\nWorld 😀  ", sourceLanguage: nil, targetLanguage: "zh-Hans")
        let result = try await AITranslationService.translate(request, using: provider)
        expect(result.text == "  你好！\n世界 😀  ", "only completed answer text becomes a translation")
        let sent = provider.requests.withLock { $0 }
        expect(sent.count == 1 && sent[0].messages == [AIMessage(role: .user, text: request.text)],
               "translation sends one isolated user message without conversation history")
        expect(sent.first?.webSearch == false && sent.first?.tools.isEmpty == true,
               "translation cannot grant search or tools")
        expect(sent.first?.instructions?.contains(request.text) == false,
               "user material never becomes system instructions")
        let blank = FixtureAI(events: [.reasoning("not a translation"), .text(" \n "), .finished])
        do {
            _ = try await AITranslationService.translate(request, using: blank)
            expect(false, "empty AI output is a failure")
        } catch {
            expect(error is AIProviderError, "empty AI output is reported through provider error")
        }
        let identity = TranslationRequest(text: request.text, sourceLanguage: "en_US", targetLanguage: "EN-us")
        let unchanged = try await AITranslationService.translate(identity, using: provider)
        expect(unchanged.text == request.text && provider.requests.withLock { $0.count } == 1,
               "exact normalized language identity returns original without billing")
        _ = try await AITranslationService.translate(
            TranslationRequest(text: "简体", sourceLanguage: "zh-Hans", targetLanguage: "zh-Hant"), using: provider)
        expect(provider.requests.withLock { $0.count } == 2, "script conversion still reaches the provider")
    }

    static let languageJSON = #"""
        [
          {"lang":"en","name":"English","usable_as_source":true,"usable_as_target":false},
          {"lang":"en-US","name":"English (American)","usable_as_source":false,"usable_as_target":true},
          {"lang":"zh","name":"Chinese","usable_as_source":true,"usable_as_target":false},
          {"lang":"zh-Hans","name":"Chinese (simplified)","usable_as_source":false,"usable_as_target":true},
          {"lang":"zh-Hant","name":"Chinese (traditional)","usable_as_source":false,"usable_as_target":true}
        ]
        """#

    static func deepLNetworking() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let service = DeepLTranslationService(configuration: configuration)
        let request = TranslationRequest(text: "Hello", sourceLanguage: nil, targetLanguage: "zh-Hans")
        FixtureProtocol.configure(.response(200, Data(languageJSON.utf8)))
        _ = try await service.languages(plan: .free, apiKey: "fixture-free")
        let directoryRequest = FixtureProtocol.requests[0]
        expect(directoryRequest.url?.path == "/v3/languages"
               && directoryRequest.url?.query == "resource=translate_text", "directory uses current official v3 contract")
        expect(directoryRequest.url?.host == "api-free.deepl.com"
               && directoryRequest.value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key fixture-free",
               "Free credentials go only to the Free endpoint")
        FixtureProtocol.configure(.response(200, Data(#"{"translations":[{"text":"你好","detected_source_language":"EN"}]}"#.utf8)))
        let translated = try await service.translate(request, plan: .pro, apiKey: "fixture-pro")
        let proRequest = FixtureProtocol.requests[0]
        expect(translated.text == "你好" && proRequest.url?.host == "api.deepl.com"
               && proRequest.value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key fixture-pro",
               "Pro translation uses only the supplied Pro account credential")
        expect(proRequest.httpMethod == "POST" && proRequest.url?.path == "/v2/translate",
               "text translation uses v2 POST, not the language directory")
        FixtureProtocol.configure(.response(403, Data("private response body".utf8)))
        do {
            _ = try await service.translate(request, plan: .free, apiKey: "fixture-free")
            expect(false, "rejected credential is an error")
        } catch {
            expect(error as? DeepLTranslationAPI.Failure == .invalidKey, "HTTP failures expose only classified errors")
        }
        let started = AsyncStream<Void>.makeStream()
        let stopped = AsyncStream<Void>.makeStream()
        FixtureProtocol.configure(.pending,
            onStart: { started.continuation.yield(); started.continuation.finish() },
            onStop: { stopped.continuation.yield(); stopped.continuation.finish() })
        let task = Task { try await service.translate(request, plan: .free, apiKey: "fixture-free") }
        for await _ in started.stream { break }
        task.cancel()
        for await _ in stopped.stream { break }
        do {
            _ = try await task.value
            expect(false, "cancelled request cannot succeed")
        } catch {
            expect(error is CancellationError || (error as? URLError)?.code == .cancelled,
                   "task cancellation reaches URLSession without a user-visible failure")
        }
        FixtureProtocol.configure(.redirect)
        do {
            _ = try await service.translate(request, plan: .free, apiKey: "fixture-free")
            expect(false, "redirect is refused")
        } catch {
            expect(FixtureProtocol.requests.count == 1
                   && FixtureProtocol.requests[0].url?.host == "api-free.deepl.com",
                   "injected protocol retains production cross-host redirect rejection")
        }
        FixtureProtocol.configure(.response(200, Data()))
        let identity = try await service.translate(
            TranslationRequest(text: "  keep\n😀", sourceLanguage: "en_US", targetLanguage: "en-US"),
            plan: .free, apiKey: "fixture-free")
        expect(identity.text == "  keep\n😀" && FixtureProtocol.requests.isEmpty,
               "DeepL identical language short-circuit never starts a request")
        do {
            _ = try await service.translate(
                TranslationRequest(text: String(repeating: "中", count: 50_000),
                                   sourceLanguage: nil, targetLanguage: "en-US"),
                plan: .free, apiKey: "fixture-free")
            expect(false, "oversized service request is rejected locally")
        } catch {
            expect(error as? DeepLTranslationAPI.Failure == .tooLong && FixtureProtocol.requests.isEmpty,
                   "oversized text never leaves the process")
        }
        let transportErrors: [(URLError.Code, DeepLTranslationAPI.Failure)] = [
            (.notConnectedToInternet, .offline), (.timedOut, .timedOut), (.networkConnectionLost, .network)
        ]
        for (code, failure) in transportErrors {
            FixtureProtocol.configure(.failure(code))
            do {
                _ = try await service.translate(request, plan: .free, apiKey: "fixture-free")
                expect(false, "transport failure cannot produce a translation")
            } catch {
                expect(error as? DeepLTranslationAPI.Failure == failure && FixtureProtocol.requests.count == 1,
                       "transport error is sanitized and never automatically retried")
            }
        }
    }

    static func waitUntil(_ condition: @MainActor () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    static func sessionDebounceAndCancellation() async {
        let gate = SleepGate()
        let session = TranslationSession(sleep: { try await gate.sleep($0) })
        var sent: [String] = []
        let operation: @MainActor (TranslationRequest) async throws -> TranslationResult = { request in
            sent.append(request.text)
            return TranslationResult(text: "translated: " + request.text, detectedSourceLanguage: "en")
        }
        for (index, text) in ["H", "Hello", "Hello, world!\n😀"].enumerated() {
            session.schedule(TranslationRequest(text: text, sourceLanguage: nil, targetLanguage: "zh-Hans"),
                             using: operation)
            await waitUntil { gate.count == index + 1 }
        }
        expect(session.state == .waiting && sent.isEmpty, "debounce never sends before being released")
        gate.releaseAll()
        await waitUntil { session.state == .completed }
        expect(sent == ["Hello, world!\n😀"], "continuous edits coalesce to the last unchanged text")
        expect(session.result?.text == "translated: Hello, world!\n😀", "newlines and emoji survive session")
        let completed = session.result
        session.cancel()
        expect(session.state == .completed && session.result == completed,
               "suspending completed work preserves its copyable result without sending")
        let whitespace = TranslationRequest(text: " \n\t", sourceLanguage: nil, targetLanguage: "zh-Hans")
        session.schedule(whitespace, using: operation)
        expect(session.state == .idle && session.result == nil && session.successfulRequest == nil,
               "whitespace clears old content without scheduling")
        for reason in ["clear", "marked text", "hidden"] {
            let before = gate.count
            session.schedule(TranslationRequest(text: reason, sourceLanguage: nil, targetLanguage: "zh-Hans"),
                             using: operation)
            await waitUntil { gate.count == before + 1 }
            if reason == "clear" { session.reset() } else { session.cancel() }
            gate.releaseAll()
            expect(session.state == .idle && sent.count == 1, "\(reason) cancels pending send")
        }
        let request = TranslationRequest(text: "retry me", sourceLanguage: nil, targetLanguage: "ja")
        session.retry(request) { _ in throw AIProviderError.responseFailed("fixture failure") }
        await waitUntil { if case .failed = session.state { return true }; return false }
        session.cancel()
        expect(session.state == .failed("fixture failure"), "hide retains failure without retrying")
        let sleeps = gate.count
        session.retry(request, using: operation)
        await waitUntil { session.state == .completed }
        expect(gate.count == sleeps && sent.last == "retry me", "explicit retry skips debounce")
        session.reset()
        expect(session.state == .idle && session.result == nil && session.successfulRequest == nil,
               "leaving a translation session drops result and successful input")
    }

    static func sessionRejectsLateCompletions() async {
        for lateFailure in [false, true] {
            for sameRequest in [false, true] {
                let session = TranslationSession()
                let gate = OperationGate()
                let first = TranslationRequest(text: "A", sourceLanguage: nil, targetLanguage: "zh-Hans")
                let second = sameRequest ? first : TranslationRequest(
                    text: "B", sourceLanguage: "en", targetLanguage: "ja")
                session.retry(first) { request in try await gate.run("old", request: request) }
                await waitUntil { gate.pending["old"] != nil }
                session.retry(second) { request in try await gate.run("new", request: request) }
                await waitUntil { gate.pending["new"] != nil }
                if lateFailure {
                    gate.finish("old", with: .failure(AIProviderError.responseFailed("stale failure")))
                } else {
                    gate.finish("old", with: .success(TranslationResult(text: "stale", detectedSourceLanguage: "en")))
                }
                await waitUntil { gate.returned.contains("old") }
                expect(session.state == .translating && session.result == nil,
                       "late old completion cannot replace newer work, even for same input on another route")
                gate.finish("new", with: .success(TranslationResult(text: "current", detectedSourceLanguage: "en")))
                await waitUntil { session.state == .completed }
                expect(session.result?.text == "current" && session.successfulRequest == second,
                       "copy content belongs only to current generation")
            }
        }
        let session = TranslationSession()
        let gate = OperationGate()
        let request = TranslationRequest(text: "same text, changed account", sourceLanguage: nil, targetLanguage: "ja")
        session.retry(request) { try await gate.run("old", request: $0) }
        await waitUntil { gate.pending["old"] != nil }
        session.retry(request) { try await gate.run("new", request: $0) }
        await waitUntil { gate.pending["new"] != nil }
        gate.finish("old", with: .success(TranslationResult(text: "stale", detectedSourceLanguage: nil)))
        await waitUntil { gate.returned.contains("old") }
        session.cancel()
        gate.finish("new", with: .success(TranslationResult(text: "cancelled", detectedSourceLanguage: nil)))
        await waitUntil { gate.returned.contains("new") }
        expect(gate.cancelled.contains("new"), "old finally never clears the new task's cancellation handle")
        expect(session.state == .idle && session.result == nil, "cancelled in-flight success stays invisible")
        session.retry(request) { try await gate.run("reset", request: $0) }
        await waitUntil { gate.pending["reset"] != nil }
        session.reset()
        gate.finish("reset", with: .failure(AIProviderError.responseFailed("cancelled error")))
        await waitUntil { gate.returned.contains("reset") }
        expect(session.state == .idle && session.result == nil, "reset rejects late errors without presenting failure")
    }

    @MainActor
    final class SleepGate {
        var count = 0
        var pending: [CheckedContinuation<Void, Error>] = []

        func sleep(_ duration: Duration) async throws {
            try await withCheckedThrowingContinuation { continuation in
                count += 1
                pending.append(continuation)
            }
        }

        func releaseAll() {
            let continuations = pending
            pending.removeAll()
            for continuation in continuations { continuation.resume() }
        }
    }

    @MainActor
    final class OperationGate {
        var pending: [String: CheckedContinuation<TranslationResult, Error>] = [:]
        var returned: Set<String> = []
        var cancelled: Set<String> = []

        func run(_ id: String, request: TranslationRequest) async throws -> TranslationResult {
            defer {
                returned.insert(id)
                if Task.isCancelled { cancelled.insert(id) }
            }
            return try await withCheckedThrowingContinuation { pending[id] = $0 }
        }

        func finish(_ id: String, with result: Result<TranslationResult, Error>) {
            pending.removeValue(forKey: id)?.resume(with: result)
        }
    }

    final class FixtureAI: AIProvider {
        let events: [AIStreamEvent]
        let requests = Mutex<[AIRequest]>([])

        init(events: [AIStreamEvent]) { self.events = events }

        func stream(_ request: AIRequest) -> AIProviderStream {
            requests.withLock { $0.append(request) }
            return AIProviderStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    // URLProtocol callbacks share only the mutex-protected fixture, never actor-bound test state.
    final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        enum Reply: Sendable {
            case response(Int, Data)
            case failure(URLError.Code)
            case pending
            case redirect
        }

        struct State: Sendable {
            var reply: Reply = .pending
            var requests: [URLRequest] = []
            var onStart: @Sendable () -> Void = {}
            var onStop: @Sendable () -> Void = {}
        }

        static let state = Mutex(State())
        static var requests: [URLRequest] { state.withLock { $0.requests } }

        static func configure(
            _ reply: Reply, onStart: @escaping @Sendable () -> Void = {},
            onStop: @escaping @Sendable () -> Void = {}
        ) {
            state.withLock { $0 = State(reply: reply, onStart: onStart, onStop: onStop) }
        }

        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let fixture = Self.state.withLock { state in
                state.requests.append(request)
                return (state.reply, state.onStart)
            }
            fixture.1()
            switch fixture.0 {
            case .pending: break
            case .failure(let code): client?.urlProtocol(self, didFailWithError: URLError(code))
            case .response(let status, let body):
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: "HTTP/1.1", headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            case .redirect:
                let destination = URL(string: "https://credential-leak.invalid/translate")!
                let response = HTTPURLResponse(url: request.url!, statusCode: 302,
                    httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: response)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data())
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() { Self.state.withLock { $0.onStop }() }
    }
}
