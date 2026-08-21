import Foundation

struct AITransform: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "ai-transform:"
    /// One glyph for every AI transform, so every surface reads as the same thing.
    static let sfSymbol = "wand.and.stars"
    static let maxNameLength = 60
    static let maxPromptLength = 4_000

    let id: UUID
    var name: String
    /// Instruction for the model; the selected text is sent as the user message.
    var prompt: String
    /// Optional override of the global model, so one preset can pin a stronger one.
    var model: String?

    init(id: UUID = UUID(), name: String, prompt: String, model: String? = nil) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.model = model
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }
}

enum AITransformValidationError: LocalizedError, Equatable {
    case emptyName
    case emptyPrompt
    case nameTooLong
    case promptTooLong
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the transform."
        case .emptyPrompt: return "Enter an instruction for the transform."
        case .nameTooLong: return "Names must be 60 characters or fewer."
        case .promptTooLong: return "Prompts must be 4,000 characters or fewer."
        case .duplicateName: return "An AI transform with this name already exists."
        }
    }
}

@MainActor
@Observable
final class AITransformStore {
    private static let defaultsKey = "aiTransforms"

    private let defaults: UserDefaults
    private(set) var transforms: [AITransform]
    @ObservationIgnored var onChange: (([AITransform]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([AITransform].self, from: $0) } ?? []
        transforms = Self.sanitized(decoded)
        if transforms != decoded { persist() }
    }

    func transform(id: UUID) -> AITransform? {
        transforms.first { $0.id == id }
    }

    func transform(entryID: String) -> AITransform? {
        AITransform.id(fromEntryID: entryID).flatMap(transform)
    }

    // Takes a whole draft, so adding an option doesn't churn every call site.
    @discardableResult
    func add(_ draft: AITransform) throws -> AITransform {
        let value = try validated(draft)
        commit(transforms + [value])
        return value
    }

    func update(_ draft: AITransform) throws {
        guard let index = transforms.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = transforms
        updated[index] = value
        commit(updated)
    }

    @discardableResult
    func remove(id: UUID) -> AITransform? {
        guard let index = transforms.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = transforms
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    /// Replaces the whole set on backup import, dropping invalid and duplicate records.
    @discardableResult
    func replace(with newTransforms: [AITransform]) -> Int {
        let updated = Self.sanitized(newTransforms)
        commit(updated)
        return updated.count
    }

    /// Seeds first-run presets when empty. Called once when the feature is enabled.
    func seedBuiltInsIfEmpty() {
        guard transforms.isEmpty else { return }
        commit(Self.builtIns)
    }

    private static let builtIns = [
        AITransform(
            name: "Fix Spelling & Grammar",
            prompt:
                "Fix all spelling and grammar mistakes in the text. Preserve the author's voice, "
                + "formatting, line breaks, and meaning. Do not rewrite style."),
        AITransform(
            name: "Polish Writing",
            prompt:
                "Improve clarity, flow, and word choice. Keep the author's intent, tone, "
                + "formatting, and approximate length."),
        AITransform(
            name: "Make Concise",
            prompt:
                "Rewrite the text to be as concise as possible while preserving every fact, "
                + "requirement, and nuance. Keep formatting."),
        AITransform(
            name: "Summarize",
            prompt: "Summarize the text into a short paragraph capturing the key points.")
    ]

    private func validated(_ draft: AITransform) throws -> AITransform {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = draft.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = (model?.isEmpty ?? true) ? nil : model
        guard !value.name.isEmpty else { throw AITransformValidationError.emptyName }
        guard !value.prompt.isEmpty else { throw AITransformValidationError.emptyPrompt }
        guard value.name.count <= AITransform.maxNameLength else {
            throw AITransformValidationError.nameTooLong
        }
        guard value.prompt.count <= AITransform.maxPromptLength else {
            throw AITransformValidationError.promptTooLong
        }
        guard
            !transforms.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw AITransformValidationError.duplicateName }
        return value
    }

    private func commit(_ updated: [AITransform]) {
        guard updated != transforms else { return }
        transforms = updated
        persist()
        onChange?(updated)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(transforms) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [AITransform]) -> [AITransform] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [AITransform] = []
        for value in values {
            // Copy-and-clean rather than rebuild, so a new option can never be dropped on import.
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.prompt = value.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = value.model?.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.model = (model?.isEmpty ?? true) ? nil : model
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: .current)
            guard
                !cleaned.name.isEmpty, !cleaned.prompt.isEmpty,
                cleaned.name.count <= AITransform.maxNameLength,
                cleaned.prompt.count <= AITransform.maxPromptLength,
                ids.insert(cleaned.id).inserted, names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result
    }
}
