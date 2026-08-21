import AppKit
import Foundation

/// State and execution engine for an interactive AI transform session in the palette.
@MainActor
@Observable
final class AITransformSession {
    enum Phase: Equatable {
        case idle
        case processing(model: String)
        case completed(output: String, model: String)
        case failed(error: String, model: String)
    }

    struct HistoryEntry: Identifiable, Equatable {
        let id: UUID
        let instruction: String
        let output: String
        let model: String
        let date: Date

        init(id: UUID = UUID(), instruction: String, output: String, model: String, date: Date = Date()) {
            self.id = id
            self.instruction = instruction
            self.output = output
            self.model = model
            self.date = date
        }
    }

    private(set) var preset: AITransform?
    private(set) var originalSelection: String = ""
    private(set) var currentModel: String = ""
    private(set) var currentReasoning: AIReasoningEffort?
    private(set) var targetApp: NSRunningApplication?
    private(set) var phase: Phase = .idle
    private(set) var history: [HistoryEntry] = []
    private var activeTask: Task<Void, Never>?

    var isActive: Bool { preset != nil }
    var presetName: String { preset?.name ?? "AI Transform" }

    var currentOutput: String {
        if case .completed(let output, _) = phase { output } else { "" }
    }

    var isProcessing: Bool {
        if case .processing = phase { true } else { false }
    }

    var placeholder: String {
        switch phase {
        case .idle:
            return "Search or choose transform…"
        case .processing(let model):
            return "Transforming with \(model)…"
        case .completed:
            return "Type to refine (e.g. “make it more casual”, “translate to French”)…"
        case .failed:
            return "Press ↵ to retry or type new prompt…"
        }
    }

    func begin(
        preset: AITransform,
        selection: String,
        targetApp: NSRunningApplication?,
        defaultModel: String,
        reasoning: AIReasoningEffort?,
        apiKey: String,
        baseURL: String
    ) {
        cancel()
        self.preset = preset
        self.originalSelection = selection
        self.targetApp = targetApp
        self.currentReasoning = reasoning
        let chosenModel = preset.model ?? (defaultModel.isEmpty ? AIClient.defaultModel : defaultModel)
        if selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.phase = .idle
        } else {
            execute(
                instruction: preset.prompt,
                input: selection,
                model: chosenModel,
                apiKey: apiKey,
                baseURL: baseURL
            )
        }
    }

    func executeCustomInput(_ input: String, apiKey: String, baseURL: String) {
        guard let preset else { return }
        self.originalSelection = input
        execute(
            instruction: preset.prompt,
            input: input,
            model: currentModel,
            apiKey: apiKey,
            baseURL: baseURL
        )
    }
    func regenerate(apiKey: String, baseURL: String) {
        guard let preset else { return }
        let promptToUse = history.last?.instruction ?? preset.prompt
        let inputToUse = originalSelection
        execute(
            instruction: promptToUse,
            input: inputToUse,
            model: currentModel,
            apiKey: apiKey,
            baseURL: baseURL
        )
    }

    func switchModelAndRegenerate(to newModel: String, apiKey: String, baseURL: String) {
        self.currentModel = newModel
        regenerate(apiKey: apiKey, baseURL: baseURL)
    }

    func refine(followUp: String, apiKey: String, baseURL: String) {
        let trimmed = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let preset else { return }

        // Contextual refinement instruction incorporating prior context
        let combinedInstruction = """
            Original Goal: \(preset.prompt)

            Follow-up Refinement: \(trimmed)
            """

        let baseInput = currentOutput.isEmpty ? originalSelection : currentOutput
        execute(
            instruction: combinedInstruction,
            input: baseInput,
            model: currentModel,
            apiKey: apiKey,
            baseURL: baseURL
        )
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        preset = nil
        originalSelection = ""
        targetApp = nil
        phase = .idle
        history = []
    }

    private func execute(
        instruction: String,
        input: String,
        model: String,
        apiKey: String,
        baseURL: String
    ) {
        activeTask?.cancel()
        guard !apiKey.isEmpty else {
            phase = .failed(error: "No API key configured.", model: model)
            return
        }
        guard let url = AICompletionRequest.endpointURL(fromBase: baseURL, path: "/chat/completions") else {
            phase = .failed(error: "Invalid base URL: \(baseURL)", model: model)
            return
        }

        phase = .processing(model: model)
        let request = AICompletionRequest(
            baseURL: url,
            apiKey: apiKey,
            model: model,
            instruction: instruction,
            selection: input,
            reasoningEffort: currentReasoning
        )
        activeTask = Task { [weak self] in
            do {
                let result = try await AIClient.complete(request)
                guard !Task.isCancelled else { return }
                self?.phase = .completed(output: result, model: model)
                self?.history.append(HistoryEntry(instruction: instruction, output: result, model: model))
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(error: error.localizedDescription, model: model)
            }
        }
    }
}
