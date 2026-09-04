import SwiftUI

/// `Form.DatePicker` — a control that drops presets and parses what is typed into it,
/// the way Raycast's own date field reads "tomorrow at 10am".
struct ExtensionDateField: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    @State private var open = false
    @State private var query = ""
    @State private var highlighted = 0
    /// True while the list opened upward, so the chevron points the way it actually went.
    @State private var flipped = false
    /// Told while the list is up, so the palette leaves every navigation key to it.
    @Environment(PaletteState.self) private var palette

    /// A `date` picker holds a day; anything else holds a time as well.
    private var includesTime: Bool { node.string("type") != "date" }
    private var value: Date? { node.date("value") }

    private var label: String {
        guard let value else { return "No Date" }
        return ExtensionDateExpression.detail(
            for: value, calendar: .current, includesTime: includesTime)
    }

    private var suggestions: [ExtensionDateExpression.Suggestion] {
        ExtensionDateExpression.suggestions(
            query: query, now: Date(), calendar: .current, includesTime: includesTime)
    }

    var body: some View {
        control
            .focusable()
            .focused($focus, equals: index)
            .focusEffectDisabled()
            .overlay(alignment: .topLeading) { popoverLayer }
            // Every key the open list uses is claimed here: the popover is an overlay, which a
            // key press from the focused control never travels into.
            .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { _ in
                open ? move(-1) : .ignored
            }
            .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { _ in
                open ? move(1) : openList()
            }
            .onKeyPress(.space) { open ? typed(" ") : openList() }
            .onKeyPress(keys: [.return], phases: .down) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                guard open else { return openList() }
                choose(suggestions, at: highlighted)
                return .handled
            }
            .onKeyPress(.escape) {
                guard open else { return .ignored }
                close()
                return .handled
            }
            // An expression is typed straight into the control, which never gives up focus.
            .onKeyPress(
                characters: .alphanumerics.union(.punctuationCharacters), phases: .down
            ) { press in
                guard open, press.modifiers.isEmpty, !press.characters.isEmpty else {
                    return .ignored
                }
                return typed(press.characters)
            }
            .onKeyPress(keys: [.delete], phases: [.down, .repeat]) { _ in
                guard open, !query.isEmpty else { return .ignored }
                query.removeLast()
                highlighted = 0
                return .handled
            }
            .onChange(of: open) { palette.noteControlListOpen(open) }
            .onDisappear { if open { palette.noteControlListOpen(false) } }
            .onChange(of: focus) { _, focus in
                if focus != index { close() }
            }
    }

    private var control: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "calendar")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(label)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(value == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
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

    @ViewBuilder
    private var popoverLayer: some View {
        if open {
            let rows = suggestions
            ExtensionPickerPopover(
                items: rows.map {
                    ExtensionPickerItem(value: $0.title, title: $0.title, detail: $0.detail)
                },
                selection: highlighted, chosen: [], assetsPath: nil,
                searchPlaceholder: "Enter expression: tomorrow at 10am",
                query: query, onSelect: { choose(rows, at: $0) }
            )
            .extensionPopoverPlacement(
                rowCount: rows.count, hasSearchField: true, onFlip: { flipped = $0 }
            )
            .zIndex(1)
        }
    }

    private func typed(_ characters: String) -> KeyPress.Result {
        query += characters
        highlighted = 0
        return .handled
    }

    private func openList() -> KeyPress.Result {
        guard !open else { return .handled }
        query = ""
        highlighted = 0
        open = true
        return .handled
    }

    private func close() {
        guard open else { return }
        open = false
        query = ""
        flipped = false
    }

    private func move(_ delta: Int, count: Int? = nil) -> KeyPress.Result {
        let rows = count ?? suggestions.count
        guard rows > 0 else { return .handled }
        highlighted = min(max(highlighted + delta, 0), rows - 1)
        return .handled
    }

    private func choose(_ rows: [ExtensionDateExpression.Suggestion], at index: Int) {
        guard rows.indices.contains(index) else { return }
        guard let date = rows[index].date else {
            onChange(node, NSNull())
            close()
            focus = self.index
            return
        }
        onChange(node, ["$date": ISO8601DateFormatter().string(from: date)])
        close()
        focus = self.index
    }
}
