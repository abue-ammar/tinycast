// The on-device route; the end-to-end leg skips with a reason on a Mac that cannot run it.

import FoundationModels
import Foundation

@main
@MainActor
struct AppleIntelligenceTests {
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
        statusCopyCoversEveryReason()
        deltasFollowCumulativeSnapshots()
        turnsSplitThePromptFromItsHistory()
        generationErrorsBecomeReadableFailures()
        await onDeviceModelAnswers()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func statusCopyCoversEveryReason() {
        expect(AppleIntelligenceStatus.available.message == nil, "available reads as no failure")
        expect(AppleIntelligenceStatus.available.isAvailable, "available is available")

        let unavailable: [AppleIntelligenceStatus] = [
            .deviceNotEligible, .notEnabled, .modelNotReady
        ]
        for status in unavailable {
            expect(!status.isAvailable, "\(status) is not available")
            expect(status.message?.isEmpty == false, "\(status) explains itself")
        }
        expect(
            Set(unavailable.compactMap(\.message)).count == unavailable.count,
            "each reason reads differently")
    }

    static func deltasFollowCumulativeSnapshots() {
        var delta = AppleIntelligenceDelta()
        let emitted = ["He", "Hello", "Hello!"].map { delta.delta(from: $0) }
        expect(emitted == ["He", "llo", "!"], "cumulative snapshots become deltas, got \(emitted)")

        // A revision replaces what came before, so dropping a stale prefix would truncate it.
        var revised = AppleIntelligenceDelta()
        _ = revised.delta(from: "Hello")
        expect(revised.delta(from: "Goodbye") == "Goodbye", "a revised snapshot is emitted whole")

        var repeated = AppleIntelligenceDelta()
        _ = repeated.delta(from: "Hello")
        expect(repeated.delta(from: "Hello").isEmpty, "an unchanged snapshot emits nothing")
    }

    static func turnsSplitThePromptFromItsHistory() {
        let request = AIRequest(
            instructions: "Be brief.",
            messages: [
                AIMessage(role: .user, text: "first"),
                AIMessage(role: .assistant, text: "answer"),
                AIMessage(role: .user, text: "  second  ")
            ])
        let turn = AppleIntelligenceProvider.turn(for: request)

        expect(turn.prompt == "second", "the newest user turn is the prompt, got \(turn.prompt ?? "nil")")
        let entries = Array(turn.transcript)
        expect(entries.count == 3, "instructions plus two history turns, got \(entries.count)")
        if case .instructions(let instructions) = entries.first {
            expect(text(instructions.segments) == "Be brief.", "instructions lead the transcript")
        } else {
            expect(false, "the transcript opens with instructions")
        }
        if case .prompt(let prompt) = entries.dropFirst().first {
            expect(text(prompt.segments) == "first", "the older user turn is a transcript prompt")
        } else {
            expect(false, "the older user turn is a transcript prompt")
        }
        if case .response(let response) = entries.last {
            expect(text(response.segments) == "answer", "the reply is a transcript response")
        } else {
            expect(false, "the reply is a transcript response")
        }
        expect(
            !entries.contains { entryText($0).contains("second") },
            "the prompt is not also in the history it resumes from")

        // Instructions are dropped upstream when the reader turns the system prompt off.
        let bare = AppleIntelligenceProvider.turn(
            for: AIRequest(messages: [AIMessage(role: .user, text: "hi")]))
        expect(Array(bare.transcript).isEmpty, "a turn with no history carries an empty transcript")
        expect(bare.prompt == "hi", "a lone user turn is still the prompt")

        // An image-only message has no text to send; the model takes no pictures either way.
        let empty = AppleIntelligenceProvider.turn(
            for: AIRequest(messages: [AIMessage(role: .assistant, text: "orphan")]))
        expect(empty.prompt == nil, "a request with no user turn has no prompt")
    }

    static func generationErrorsBecomeReadableFailures() {
        let context = LanguageModelSession.GenerationError.Context(
            debugDescription: "internal-detail-42")
        let errors: [LanguageModelSession.GenerationError] = [
            .exceededContextWindowSize(context), .guardrailViolation(context),
            .unsupportedLanguageOrLocale(context), .assetsUnavailable(context),
            .rateLimited(context), .concurrentRequests(context)
        ]
        var messages: [String] = []
        for error in errors {
            let message = AppleIntelligenceProvider.providerError(error).localizedDescription
            expect(!message.isEmpty, "\(error) explains itself")
            expect(
                !message.contains("internal-detail-42"),
                "\(error) does not leak its debug description")
            messages.append(message)
        }
        expect(Set(messages).count == messages.count, "each failure reads differently")
        expect(
            AppleIntelligenceProvider.providerError(.decodingFailure(context))
                == .malformedResponse,
            "a decoding failure is the shared malformed-response case")
    }

    /// The real thing, end to end, when this Mac can run it.
    static func onDeviceModelAnswers() async {
        let status = AppleIntelligenceProvider.status()
        guard status.isAvailable else {
            print("skip  on-device stream — \(status.message ?? "unavailable")")
            return
        }
        let request = AIRequest(
            instructions: "Reply with one short sentence.",
            messages: [AIMessage(role: .user, text: "Name one colour.")])
        var text = ""
        var finished = false
        do {
            for try await event in AppleIntelligenceProvider().stream(request) {
                switch event {
                case .text(let chunk): text += chunk
                case .finished: finished = true
                default: break
                }
            }
        } catch {
            expect(false, "the on-device stream failed: \(error.localizedDescription)")
            return
        }
        expect(!text.isEmpty, "the on-device model answered")
        expect(finished, "the on-device stream terminated with .finished")
    }

    private static func text(_ segments: [Transcript.Segment]) -> String {
        segments.compactMap { if case .text(let segment) = $0 { segment.content } else { nil } }
            .joined()
    }

    private static func entryText(_ entry: Transcript.Entry) -> String {
        switch entry {
        case .instructions(let value): return text(value.segments)
        case .prompt(let value): return text(value.segments)
        case .response(let value): return text(value.segments)
        case .toolCalls, .toolOutput: return ""
        @unknown default: return ""
        }
    }
}
