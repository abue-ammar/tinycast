import Foundation

/// What `AI.ask` may reach: the reader's own Settings → AI routes, resolved per call by `AppCore`.
struct ExtensionAIAccess {
    /// Read at each launch for `environment.canAccess(AI)`, since AI can be switched off meanwhile.
    let isAvailable: @MainActor () -> Bool
    /// The route for a Raycast model id, or the reader's default when nothing matches it.
    let provider: @MainActor (_ requestedModel: String?) throws -> any AIProvider
}

/// `ai.ask`: one user turn, streamed to JS as progress and settled as the whole text.
@MainActor
enum ExtensionAIBridge {
    enum Failure: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "AI is off in Tinycast. Turn it on and choose a model in Settings \u{2192} AI."
        }
    }

    static func ask(
        _ arguments: [RenderValue], access: ExtensionAIAccess?,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let access, access.isAvailable() else { throw Failure.unavailable }
        let options = arguments.first?.objectValue ?? [:]
        let prompt = options["prompt"]?.stringValue ?? ""
        let model = options["model"]?.stringValue
        let provider = try access.provider(model)
        var temperature = options["creativity"]?.doubleValue
        while true {
            var text = ""
            do {
                let request = AIRequest(
                    messages: [AIMessage(role: .user, text: prompt)], temperature: temperature)
                reply: for try await event in provider.stream(request) {
                    try Task.checkCancellation()
                    switch event {
                    case .text(let delta) where !delta.isEmpty:
                        text += delta
                        progress(ExtensionRuntime.jsonString(from: delta))
                    case .finished:
                        break reply
                    default:
                        continue
                    }
                }
                // A transport ends a cancelled stream quietly, which must not read as an answer.
                try Task.checkCancellation()
                return text
            } catch let error as AIProviderError
                where text.isEmpty && temperature != nil
                && RaycastAIModelMatch.rejectsTemperature(error.localizedDescription)
            {
                temperature = nil
            }
        }
    }
}
