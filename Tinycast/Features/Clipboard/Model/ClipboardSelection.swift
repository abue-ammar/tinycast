import Foundation

/// A ⇧-extended range of clipboard rows, held as ids so a row deleted mid-selection drops out.
struct ClipboardSelection: Equatable, Sendable {
    /// The row every extension measures from; nil until the first ⇧ gesture.
    private(set) var anchorID: ClipboardItem.ID?
    private(set) var ids: Set<ClipboardItem.ID> = []

    var isMultiple: Bool { ids.count > 1 }

    mutating func clear() {
        anchorID = nil
        ids = []
    }

    /// Extends from the fixed anchor to `index`, anchoring on `selection`'s row the first time.
    mutating func extend(to index: Int, from selection: Int, rows: [ClipboardItem]) {
        guard rows.indices.contains(index) else { return }
        let anchor =
            anchorID.flatMap { id in rows.firstIndex { $0.id == id } }
            ?? min(max(selection, 0), rows.count - 1)
        anchorID = rows[anchor].id
        ids = Set(rows[min(anchor, index)...max(anchor, index)].map(\.id))
    }

    /// The selected rows in visible order, so a paste follows the list top to bottom.
    func items(in rows: [ClipboardItem]) -> [ClipboardItem] {
        guard isMultiple else { return [] }
        return rows.filter { ids.contains($0.id) }
    }
}
