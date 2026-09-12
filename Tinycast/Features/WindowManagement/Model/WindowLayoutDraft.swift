import CoreGraphics
import Foundation

/// One in-flight edit of a layout. Owned by the editor sheet and gone when it closes.
@MainActor
@Observable
final class WindowLayoutDraft {
    /// What the editor's steppers allow; the model itself accepts any fraction in 0…1.
    static let percentRange: ClosedRange<Int> = 5...100
    static let offsetRange: ClosedRange<Int> = -4000...4000

    /// Nil for a new layout; kept so saving an edit keeps the UUID and every reference on it.
    let existingID: UUID?
    let isCapture: Bool
    var name: String
    var iconSymbol: String?
    var usesPreferredGap: Bool
    private(set) var entries: [WindowLayoutEntry]
    /// Identity, never an index: removing an entry must not strand a field's binding.
    private(set) var selectedEntryID: UUID?
    private(set) var selectedDisplayUUID: String?
    private let createdAt: Date

    init(layout: WindowLayout?, isCapture: Bool = false, displays: [WindowLayoutDisplay]) {
        existingID = layout?.id
        self.isCapture = isCapture
        name = layout?.name ?? ""
        iconSymbol = layout?.iconSymbol
        usesPreferredGap = layout?.usesPreferredGap ?? true
        entries = layout?.entries ?? []
        createdAt = layout?.createdAt ?? Date()
        selectedEntryID = entries.first?.id
        selectedDisplayUUID = entries.first?.display.uuid ?? displays.first?.uuid
    }

    var symbol: String { iconSymbol ?? WindowLayout.sfSymbol }
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !entries.isEmpty
    }

    var selectedEntry: WindowLayoutEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    func entries(onDisplay uuid: String) -> [WindowLayoutEntry] {
        entries.filter { $0.display.uuid == uuid }
    }

    /// Every display the sheet must offer a tab for: the connected ones plus any an entry names.
    func tabs(connected: [WindowLayoutDisplay]) -> [WindowLayoutDisplay] {
        var seen = Set(connected.map(\.uuid))
        var result = connected
        for entry in entries where seen.insert(entry.display.uuid).inserted {
            result.append(entry.display)
        }
        return result
    }

    // MARK: - Selection

    /// One selection with two views of it, so the tab and the entry picker can never disagree.
    func select(entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        selectedEntryID = entryID
        selectedDisplayUUID = entry.display.uuid
    }

    func select(displayUUID: String) {
        selectedDisplayUUID = displayUUID
        if selectedEntry?.display.uuid != displayUUID {
            selectedEntryID = entries(onDisplay: displayUUID).first?.id
        }
    }

    // MARK: - Editing

    func addEntry(bundleID: String, on display: WindowLayoutDisplay) {
        let entry = WindowLayoutEntry(bundleID: bundleID, display: display)
        entries.append(entry)
        select(entryID: entry.id)
    }

    func removeSelectedEntry() {
        guard let id = selectedEntryID else { return }
        entries.removeAll { $0.id == id }
        selectedEntryID =
            selectedDisplayUUID.flatMap { entries(onDisplay: $0).first?.id }
            ?? entries.first?.id
    }

    func setArgument(_ argument: String?) {
        update { $0.argument = argument?.isEmpty == true ? nil : argument }
    }

    func setDisplay(_ display: WindowLayoutDisplay) {
        update { $0.display = display }
        selectedDisplayUUID = display.uuid
    }

    func setAnchor(_ anchor: WindowLayoutAnchor) {
        update { $0.anchor = anchor }
    }

    func setWidthPercent(_ percent: Int) {
        update { $0.widthFraction = Self.fraction(percent) }
    }

    func setHeightPercent(_ percent: Int) {
        update { $0.heightFraction = Self.fraction(percent) }
    }

    func setOffsetX(_ points: Int) {
        update { $0.offset.x = CGFloat(points.clamped(to: Self.offsetRange)) }
    }

    func setOffsetY(_ points: Int) {
        update { $0.offset.y = CGFloat(points.clamped(to: Self.offsetRange)) }
    }

    // MARK: - Output

    /// What the preview draws — unvalidated, so an unnamed draft still shows its windows.
    var previewLayout: WindowLayout {
        WindowLayout(
            id: existingID ?? UUID(), name: name, iconSymbol: iconSymbol,
            usesPreferredGap: usesPreferredGap, entries: entries, createdAt: createdAt)
    }

    /// What Save persists; the sheet never assembles a record itself.
    func layout() -> WindowLayout {
        var value = previewLayout
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    // MARK: - Primitives

    static func percent(_ fraction: CGFloat) -> Int {
        guard fraction.isFinite else { return 100 }
        return Int((fraction * 100).rounded()).clamped(to: percentRange)
    }

    private static func fraction(_ percent: Int) -> CGFloat {
        CGFloat(percent.clamped(to: percentRange)) / 100
    }

    private func update(_ change: (inout WindowLayoutEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == selectedEntryID }) else { return }
        change(&entries[index])
    }
}

extension Int {
    /// Saturating, so a typed-in number is corrected rather than rejected.
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
