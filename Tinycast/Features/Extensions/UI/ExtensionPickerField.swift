import SwiftUI

/// A form control that drops a searchable list: `Form.Dropdown` and `Form.TagPicker` alike.
/// The popover is drawn in an overlay above the form rather than in a window of its own, so it
/// scrolls with the field it belongs to and never outlives the screen that owns it.
struct ExtensionPickerField: View {
    let items: [ExtensionPickerItem]
    /// Every value currently held; a dropdown has one, a tag picker any number.
    let chosen: [String]
    let placeholder: String
    let assetsPath: String?
    let allowsMultipleSelection: Bool
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: ([String]) -> Void
    let onSubmit: () -> Void

    @State private var open = false
    @State private var query = ""
    @State private var highlighted = 0
    /// True while the list opened upward, so the chevron points the way it actually went.
    @State private var flipped = false
    /// Read from the view, so a resolved icon repaints when the surface flips appearance.
    @Environment(\.isDarkAppearance) private var isDark
    /// Told while the list is up, so the palette leaves every navigation key to it.
    @Environment(PaletteState.self) private var palette

    /// What the closed control reads as: the chosen titles, or the placeholder.
    private var label: String {
        let titles = chosen.compactMap { value in items.first { $0.value == value }?.title }
        return titles.isEmpty ? placeholder : titles.joined(separator: ", ")
    }

    private var leadingIcon: ExtensionImage.Resolved? {
        guard !allowsMultipleSelection, let value = chosen.first else { return nil }
        let icon = items.first { $0.value == value }?.iconValue
        return ExtensionImage.resolve(icon, assetsPath: assetsPath, isDark: isDark)
    }

    private var matches: [ExtensionPickerItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        let needle = FuzzyMatch.Query(trimmed)
        return items.filter { FuzzyMatch.score(needle, candidate: $0.title) != nil }
    }

    var body: some View {
        control
            .focusable()
            .focused($focus, equals: index)
            // The chrome draws the focused edge, so AppKit's blue ring would be a second one.
            .focusEffectDisabled()
            .overlay(alignment: .topLeading) { popoverLayer }
            // Every key the open list uses is claimed here: the popover is drawn in an overlay,
            // which a key press from the focused control never travels into.
            .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { _ in
                open ? move(-1) : .ignored
            }
            .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { _ in
                open ? move(1) : openList()
            }
            .onKeyPress(.space) { open ? .ignored : openList() }
            .onKeyPress(keys: [.return], phases: .down) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                guard open else { return openList() }
                choose(at: highlighted)
                return .handled
            }
            .onKeyPress(.escape) {
                guard open else { return .ignored }
                close()
                return .handled
            }
            // Typing filters the open list; the control stays first responder throughout.
            .onKeyPress(characters: .alphanumerics.union(.whitespaces).union(.punctuationCharacters), phases: .down) { press in
                guard open, press.modifiers.isEmpty, !press.characters.isEmpty else { return .ignored }
                query += press.characters
                highlighted = 0
                return .handled
            }
            .onKeyPress(keys: [.delete], phases: [.down, .repeat]) { _ in
                guard open, !query.isEmpty else { return .ignored }
                query.removeLast()
                highlighted = 0
                return .handled
            }
            // Closed, the arrows step the value without opening — a short dropdown needs no list.
            .onKeyPress(.leftArrow) { open ? .handled : step(-1) }
            .onKeyPress(.rightArrow) { open ? .handled : step(1) }
            .onChange(of: open) { palette.noteControlListOpen(open) }
            .onDisappear { if open { palette.noteControlListOpen(false) } }
            .onChange(of: focus) { _, focus in
                // Focus leaving the field takes its list with it.
                if focus != index { close() }
            }
    }

    private var control: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let leadingIcon {
                ExtensionIconView(resolved: leadingIcon, size: 14)
            }
            Text(label)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(chosen.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            ExtensionDisclosureChevron(open: open, flipped: flipped)
        }
        .extensionFieldChrome(focused: focus == index, open: open)
        .contentShape(Rectangle())
        .onTapGesture {
            focus = index
            if open { close() } else { _ = openList() }
        }
    }

    /// Drawn in an overlay so it sits above the rows below it without a window of its own.
    @ViewBuilder
    private var popoverLayer: some View {
        if open {
            ExtensionPickerPopover(
                items: matches, selection: highlighted, chosen: Set(chosen),
                assetsPath: assetsPath, searchPlaceholder: "Search…",
                query: query, onSelect: { choose(at: $0) }
            )
            .extensionPopoverPlacement(
                rowCount: matches.count, hasSearchField: true, onFlip: { flipped = $0 }
            )
            // Above every later row, so a picker near the top is not covered by the fields under it.
            .zIndex(1)
        }
    }

    private func openList() -> KeyPress.Result {
        guard !open else { return .handled }
        query = ""
        highlighted = items.firstIndex { chosen.contains($0.value) } ?? 0
        open = true
        return .handled
    }

    private func close() {
        guard open else { return }
        open = false
        query = ""
        flipped = false
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let count = matches.count
        guard count > 0 else { return .handled }
        highlighted = min(max(highlighted + delta, 0), count - 1)
        return .handled
    }

    /// Clamped rather than wrapping, so holding an arrow settles at an end like every other list.
    private func step(_ delta: Int) -> KeyPress.Result {
        guard !allowsMultipleSelection, !items.isEmpty else { return .ignored }
        let current = items.firstIndex { chosen.contains($0.value) } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        guard next != current else { return .handled }
        onChange([items[next].value])
        return .handled
    }

    private func choose(at index: Int) {
        let matches = matches
        guard matches.indices.contains(index) else { return }
        let value = matches[index].value
        guard allowsMultipleSelection else {
            onChange([value])
            close()
            focus = self.index
            return
        }
        // Multi-select stays open, the way ticking several tags off a list wants to work.
        var next = chosen
        if let existing = next.firstIndex(of: value) {
            next.remove(at: existing)
        } else {
            next.append(value)
        }
        onChange(next)
    }
}
