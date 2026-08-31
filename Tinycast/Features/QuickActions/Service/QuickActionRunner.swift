import AppKit

/// Reads the selection and transforms it; replacing the text is the coordinator's call, not this.
@MainActor
final class QuickActionRunner {
    /// The ceiling lives here, not at the provider, where it returns as an opaque context error.
    static let maxSelectionBytes = 32_768

    /// A borrowed ⌘C synthesises a keystroke into somebody's app, so it is never the first try.
    static func selection(
        in targetApp: NSRunningApplication?, using injector: TextInjector
    ) async throws -> String {
        // A shortcut press is an explicit gesture, so it may prompt, as snippet expansion does.
        guard Permissions.ensureAccessibility() else { throw QuickActionFailure.needsAccessibility }
        guard let targetApp,
            targetApp.bundleIdentifier != Bundle.main.bundleIdentifier
        else { throw QuickActionFailure.noTarget }

        let reported = AccessibilityText.read(in: targetApp)
        if case .text(let text) = reported { return try accepted(text) }
        if let copied = await injector.copySelection(from: targetApp) {
            return try accepted(copied)
        }
        // Only when Accessibility saw a text element is "nothing is selected" the honest answer.
        throw reported == .empty
            ? QuickActionFailure.noSelection
            : .unreadableApp(targetApp.localizedName ?? "That app")
    }

    private static func accepted(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickActionFailure.noSelection
        }
        guard text.utf8.count <= maxSelectionBytes else { throw QuickActionFailure.tooLong }
        return text
    }

    /// No transcript to grow, so a caller showing progress reads `onDelta` and the rest just await.
    static func run(
        _ action: QuickAction, selection: String, using provider: any AIProvider,
        instructionOverride: String?,
        onDelta: @MainActor (String) -> Void = { _ in }
    ) async throws -> String {
        let request = AIRequest(
            instructions: QuickActionPrompt.instructions(
                for: action, override: instructionOverride),
            messages: [
                AIMessage(
                    role: .user,
                    text: QuickActionPrompt.message(for: action, selection: selection))
            ],
            maxOutputTokens: maxOutputTokens(for: action, selection: selection))
        var text = ""
        for try await event in provider.stream(request) {
            guard case .text(let delta) = event else { continue }
            text += delta
            onDelta(delta)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIProviderError.responseFailed("The model returned nothing.")
        }
        return trimmed
    }

    /// The on-device window counts the prompt and the reply against one budget, so both need a cap.
    private static func maxOutputTokens(for action: QuickAction, selection: String) -> Int {
        let approximateTokens = max(selection.count / 3, 64)
        return action == .summarize
            ? min(approximateTokens, 512) : min(approximateTokens * 2, 2_048)
    }
}
