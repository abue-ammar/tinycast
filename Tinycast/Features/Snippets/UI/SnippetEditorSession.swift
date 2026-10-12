import SwiftUI

@MainActor
@Observable
final class SnippetEditorSession {
    enum Field: CaseIterable, Hashable {
        case template, name, keyword, tags, enabled, confirmation
    }

    let record: StoredSnippet?
    var name: String
    var keyword: String
    var text: String
    var isEnabled: Bool
    var showsConfirmation: Bool
    var tags: [SnippetTag]
    var tagQuery = ""
    var tagSuggestionsDismissed = false
    var selection: TextSelection?
    var focusedField: Field = .template
    var errorMessage: String?
    var isSaving = false

    init(record: StoredSnippet?) {
        self.record = record
        let snippet = record?.snippet
        name = snippet?.name ?? ""
        keyword = snippet?.keyword ?? ""
        text = snippet?.text ?? ""
        isEnabled = snippet?.isEnabled ?? true
        showsConfirmation = snippet?.showsConfirmation ?? false
        tags = snippet?.tags ?? []
    }

    var canSave: Bool {
        !isSaving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var snippet: Snippet {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return Snippet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), text: text,
            keyword: keyword.isEmpty ? nil : keyword, isEnabled: isEnabled,
            showsConfirmation: showsConfirmation, tags: tags)
    }

    func tagSuggestions(in catalog: [SnippetTag]) -> [SnippetTag] {
        let query = tagQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches = catalog.filter { tag in
            !tags.contains(where: { $0.id == tag.id })
                && (query.isEmpty || tag.name.localizedStandardContains(query))
        }
        if let proposed = SnippetTag.proposed(name: query, among: catalog + tags),
            !catalog.contains(where: { $0.id == proposed.id }),
            !tags.contains(where: { $0.id == proposed.id })
        {
            matches.append(proposed)
        }
        return matches
    }

    func addTag(_ tag: SnippetTag) {
        tags = SnippetTag.unique(tags + [tag])
        tagQuery = ""
    }

    func commitTag(in catalog: [SnippetTag]) {
        guard let tag = SnippetTag.proposed(name: tagQuery, among: catalog + tags) else { return }
        addTag(tag)
    }

    func dismissTagSuggestions(in catalog: [SnippetTag]) -> Bool {
        guard focusedField == .tags, !tagSuggestionsDismissed, !tagSuggestions(in: catalog).isEmpty else {
            return false
        }
        tagSuggestionsDismissed = true
        return true
    }

    func advanceFocus(backwards: Bool) {
        let fields = Field.allCases
        guard let index = fields.firstIndex(of: focusedField) else { return }
        focusedField = fields[(index + (backwards ? fields.count - 1 : 1)) % fields.count]
    }

    func insert(_ token: String) {
        let offset: Int
        if let selection, case .selection(let range) = selection.indices,
            range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
        {
            offset = text.distance(from: text.startIndex, to: range.lowerBound)
            text.replaceSubrange(range, with: token)
        } else {
            offset = text.count
            text += token
        }
        let caret = text.index(text.startIndex, offsetBy: offset + token.count)
        selection = TextSelection(range: caret..<caret)
        focusedField = .template
    }
}
