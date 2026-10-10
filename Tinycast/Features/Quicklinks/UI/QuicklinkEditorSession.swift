import SwiftUI

@MainActor
@Observable
final class QuicklinkEditorSession {
    enum Field: CaseIterable, Hashable {
        case link, name, icon, application, rootSearch, pin
    }

    let original: Quicklink?
    let id: UUID
    var name: String
    var link: String
    var iconSymbol: String?
    var openWithBundleID: String?
    var showsInRootSearch: Bool
    var isPinned: Bool
    var selection: TextSelection?
    var focusedField: Field = .link
    var errorMessage: String?

    init(quicklink: Quicklink?) {
        original = quicklink
        id = quicklink?.id ?? UUID()
        name = quicklink?.name ?? ""
        link = quicklink?.link ?? ""
        iconSymbol = quicklink?.iconSymbol
        openWithBundleID = quicklink?.openWithBundleID
        showsInRootSearch = quicklink?.showsInRootSearch ?? true
        isPinned = quicklink?.isPinned ?? false
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func draft(now: Date) -> Quicklink {
        Quicklink(
            id: id, name: name, link: link, openWithBundleID: openWithBundleID,
            iconSymbol: iconSymbol, isEnabled: original?.isEnabled ?? true,
            showsInRootSearch: showsInRootSearch,
            pinnedAt: isPinned ? (original?.pinnedAt ?? now) : nil,
            createdAt: original?.createdAt ?? now)
    }

    func advanceFocus(backwards: Bool) {
        let fields = Field.allCases
        let index = fields.firstIndex(of: focusedField) ?? 0
        focusedField = fields[(index + (backwards ? fields.count - 1 : 1)) % fields.count]
    }

    func insert(_ token: String) {
        let offset: Int
        if let selection, case .selection(let range) = selection.indices,
            range.lowerBound >= link.startIndex, range.upperBound <= link.endIndex
        {
            offset = link.distance(from: link.startIndex, to: range.lowerBound)
            link.replaceSubrange(range, with: token)
        } else {
            offset = link.count
            link += token
        }
        let caret = link.index(link.startIndex, offsetBy: offset + token.count)
        selection = TextSelection(range: caret..<caret)
        focusedField = .link
    }
}
