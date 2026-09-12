import Foundation

struct QuickActionSettings: Equatable, Sendable {
    /// Only what the reader chose: an absent action takes its default, so a default may move later.
    var previewChoices: [BuiltInQuickAction: Bool] = [:]

    /// BCP-47, e.g. `es-419`. Empty means the Mac's own language.
    var targetLanguage: String = ""
    private(set) var instructionOverrides: [BuiltInQuickAction: String] = [:]

    func previewsResult(_ action: QuickAction) -> Bool {
        switch action {
        case .builtIn(let builtIn): return previewsResult(builtIn)
        case .custom(let custom): return custom.previewsResult
        }
    }

    func previewsResult(_ action: BuiltInQuickAction) -> Bool {
        if action.alwaysPreviews { return true }
        return previewChoices[action] ?? !action.replacesDirectlyByDefault
    }

    mutating func setPreviewsResult(_ previews: Bool, for action: BuiltInQuickAction) {
        guard !action.alwaysPreviews else { return }
        previewChoices[action] = previews
    }

    func instructionOverride(for action: QuickAction) -> String? {
        action.builtInAction.flatMap(instructionOverride)
    }

    func instructionOverride(for action: BuiltInQuickAction) -> String? {
        instructionOverrides[action]
    }

    mutating func setInstructionOverride(_ instructions: String?, for action: BuiltInQuickAction) {
        guard !action.usesTranslationFramework else { return }
        instructionOverrides[action] = instructions
    }

    /// Round-trips through `UserDefaults`; an unknown key is an action that no longer exists.
    var storedPreviewChoices: [String: Bool] {
        get { Dictionary(uniqueKeysWithValues: previewChoices.map { ($0.rawValue, $1) }) }
        set {
            previewChoices = Dictionary(
                uniqueKeysWithValues: newValue.compactMap { key, value in
                    BuiltInQuickAction(rawValue: key).map { ($0, value) }
                })
        }
    }

    var storedInstructionOverrides: [String: String] {
        get { Dictionary(uniqueKeysWithValues: instructionOverrides.map { ($0.rawValue, $1) }) }
        set {
            instructionOverrides = Dictionary(
                uniqueKeysWithValues: newValue.compactMap { key, value in
                    guard let action = BuiltInQuickAction(rawValue: key),
                        !action.usesTranslationFramework
                    else { return nil }
                    return (action, value)
                })
        }
    }
}
