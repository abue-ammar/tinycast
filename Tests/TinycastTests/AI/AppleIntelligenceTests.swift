import Foundation
import FoundationModels
import Testing

@testable import Tinycast

struct AppleIntelligenceTests {
    static let unavailable: [AppleIntelligenceStatus] = [.deviceNotEligible, .notEnabled, .modelNotReady]

    static let context = LanguageModelSession.GenerationError.Context(debugDescription: "internal-detail-42")
    static let generationErrors: [LanguageModelSession.GenerationError] = [
        .exceededContextWindowSize(context), .guardrailViolation(context),
        .unsupportedLanguageOrLocale(context), .assetsUnavailable(context),
        .rateLimited(context), .concurrentRequests(context)
    ]

    @Test func availableReadsAsNoFailure() {
        #expect(AppleIntelligenceStatus.available.message == nil, "available reads as no failure")
        #expect(AppleIntelligenceStatus.available.isAvailable, "available is available")
    }

    @Test(arguments: unavailable)
    func unavailableStatusExplainsItself(_ status: AppleIntelligenceStatus) {
        #expect(!status.isAvailable, "\(status) is not available")
        #expect(status.message?.isEmpty == false, "\(status) explains itself")
    }

    @Test func eachUnavailableReasonReadsDifferently() {
        #expect(Set(Self.unavailable.compactMap(\.message)).count == Self.unavailable.count)
    }

    @Test func supportIsWhatAChangeInSystemSettingsCouldFix() {
        #expect(!AppleIntelligenceStatus.deviceNotEligible.isSupported, "ineligible hardware is unsupported")
        #expect(
            AppleIntelligenceStatus.notEnabled.isSupported
                && AppleIntelligenceStatus.modelNotReady.isSupported,
            "a Mac that could run it after a change in System Settings is supported")
    }

    @Test func deltasFollowCumulativeSnapshots() {
        var delta = AppleIntelligenceDelta()
        let emitted = ["He", "Hello", "Hello!"].map { delta.delta(from: $0) }
        #expect(emitted == ["He", "llo", "!"], "cumulative snapshots become deltas")

        // A revision replaces what came before, so dropping a stale prefix would truncate it.
        var revised = AppleIntelligenceDelta()
        _ = revised.delta(from: "Hello")
        #expect(revised.delta(from: "Goodbye") == "Goodbye", "a revised snapshot is emitted whole")

        var repeated = AppleIntelligenceDelta()
        _ = repeated.delta(from: "Hello")
        #expect(repeated.delta(from: "Hello").isEmpty, "an unchanged snapshot emits nothing")
    }

    @Test func turnsSplitThePromptFromItsHistory() throws {
        let request = AIRequest(
            instructions: "Be brief.",
            messages: [
                AIMessage(role: .user, text: "first"),
                AIMessage(role: .assistant, text: "answer"),
                AIMessage(role: .user, text: "  second  ")
            ])
        let turn = AppleIntelligenceProvider.turn(for: request)

        #expect(turn.prompt == "second", "the newest user turn is the prompt")
        let history = Array(turn.transcript).map(Entry.init)
        #expect(history == [.instructions("Be brief."), .prompt("first"), .response("answer")])
        #expect(!history.contains { $0.text.contains("second") }, "the prompt is not also in its history")
    }

    /// Instructions are dropped upstream when the reader turns the system prompt off.
    @Test func aLoneUserTurnCarriesAnEmptyTranscript() {
        let bare = AppleIntelligenceProvider.turn(
            for: AIRequest(messages: [AIMessage(role: .user, text: "hi")]))
        #expect(Array(bare.transcript).isEmpty, "a turn with no history carries an empty transcript")
        #expect(bare.prompt == "hi", "a lone user turn is still the prompt")
    }

    /// An image-only message has no text to send; the model takes no pictures either way.
    @Test func aRequestWithNoUserTurnHasNoPrompt() {
        let empty = AppleIntelligenceProvider.turn(
            for: AIRequest(messages: [AIMessage(role: .assistant, text: "orphan")]))
        #expect(empty.prompt == nil)
    }

    @Test(arguments: generationErrors)
    func generationErrorExplainsItselfWithoutLeaking(_ error: LanguageModelSession.GenerationError) {
        let message = AppleIntelligenceProvider.providerError(error).localizedDescription
        #expect(!message.isEmpty, "explains itself")
        #expect(!message.contains("internal-detail-42"), "does not leak its debug description")
    }

    @Test func eachGenerationErrorReadsDifferently() {
        let messages = Self.generationErrors.map {
            AppleIntelligenceProvider.providerError($0).localizedDescription
        }
        #expect(Set(messages).count == messages.count)
    }

    @Test func aDecodingFailureIsTheSharedMalformedResponse() {
        #expect(AppleIntelligenceProvider.providerError(.decodingFailure(Self.context)) == .malformedResponse)
    }

    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["TINYCAST_TEST_APPLE_INTELLIGENCE"] == "1"),
        .enabled(
            if: AppleIntelligenceProvider.status().isAvailable, "this Mac cannot run the on-device model"),
        .timeLimit(.minutes(1))
    )
    func onDeviceModelAnswers() async throws {
        let request = AIRequest(
            instructions: "Reply with one short sentence.",
            messages: [AIMessage(role: .user, text: "Name one colour.")])
        var text = ""
        var finished = false
        for try await event in AppleIntelligenceProvider().stream(request) {
            switch event {
            case .text(let chunk): text += chunk
            case .finished: finished = true
            default: break
            }
        }
        #expect(!text.isEmpty, "the on-device model answered")
        #expect(finished, "the on-device stream terminated with .finished")
    }

    /// A transcript entry reduced to what a check compares: its role and its text.
    private enum Entry: Equatable {
        case instructions(String), prompt(String), response(String), other

        init(_ entry: Transcript.Entry) {
            switch entry {
            case .instructions(let value): self = .instructions(Self.text(value.segments))
            case .prompt(let value): self = .prompt(Self.text(value.segments))
            case .response(let value): self = .response(Self.text(value.segments))
            default: self = .other
            }
        }

        var text: String {
            switch self {
            case .instructions(let text), .prompt(let text), .response(let text): text
            case .other: ""
            }
        }

        private static func text(_ segments: [Transcript.Segment]) -> String {
            segments.compactMap { if case .text(let segment) = $0 { segment.content } else { nil } }
                .joined()
        }
    }
}
