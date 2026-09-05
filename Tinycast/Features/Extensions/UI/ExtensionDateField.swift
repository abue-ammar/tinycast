import SwiftUI

/// `Form.DatePicker`: presets plus an expression, typed into the control itself.
struct ExtensionDateField: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    @State private var open = false
    @State private var query = ""
    @State private var highlighted = 0
    @State private var hovered = false
    /// Where this control sits in the form, which is what its list is placed against.
    @State private var anchor = ExtensionControlAnchor()
    /// Told while the list is up, so the palette leaves every navigation key to it.
    @Environment(PaletteState.self) private var palette

    /// A `date` picker holds a day; anything else holds a time as well.
    private var includesTime: Bool { node.string("type") != "date" }
    private var value: Date? { node.date("value") }
    private var isFocused: Bool { focus == index }

    private var label: String {
        guard let value else { return "No Date" }
        return ExtensionDateExpression.detail(
            for: value, calendar: .current, includesTime: includesTime)
    }

    private var suggestions: [ExtensionDateExpression.Suggestion] {
        ExtensionDateExpression.suggestions(
            query: query, now: Date(), calendar: .current, includesTime: includesTime)
    }

    /// What the control does, then whatever the extension explains about the field.
    private var hint: String {
        let state = open ? "Showing dates" : "Opens a list of dates"
        guard let info = node.string("info"), !info.isEmpty else { return state }
        return state + ". " + info
    }

    var body: some View {
        control
            .focusable()
            .focused($focus, equals: index)
            .focusEffectDisabled()
            .overlay(alignment: .topLeading) { listLayer }
            // One handler: the list is an overlay, which a press on the control never reaches.
            .onKeyPress(phases: [.down, .repeat]) { press in
                switch ExtensionListKey(press: press, listOpen: open) {
                case .openList: return openList()
                case .moveUp: return move(-1)
                case .moveDown: return move(1)
                case .commit:
                    choose(suggestions, at: highlighted)
                    return .handled
                case .dismiss:
                    close()
                    return .handled
                case .append(let characters): return typed(characters)
                case .deleteBackward:
                    guard !query.isEmpty else { return .handled }
                    query.removeLast()
                    highlighted = 0
                    return .handled
                // A date has no value to step: its arrows belong to the list or to nothing.
                case .stepValue, .ignored: return .ignored
                }
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
            // While the list is open the control is the expression field, caret and all.
            if open {
                Text(query.isEmpty ? "tomorrow at 10am" : query)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(
                        query.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary
                    )
                    .lineLimit(1)
                    .truncationMode(.head)
                ExtensionCaret()
            } else {
                Text(label)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(
                        value == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            ExtensionDisclosureChevron(open: open, flipped: placement.flipped)
        }
        .extensionFieldChrome(focused: isFocused, open: open, hovered: hovered)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(node.string("title") ?? "Date"))
        // While open the control is an expression field, so it announces what is typed.
        .accessibilityValue(Text(open && !query.isEmpty ? query : label))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(.isButton)
        .onHover { hovered = $0 }
        .onTapGesture {
            focus = index
            if open { close() } else { _ = openList() }
        }
        // The control is what the list is placed against; the list must never measure itself.
        .extensionControlAnchor { anchor = $0 }
    }

    @ViewBuilder
    private var listLayer: some View {
        if open {
            let rows = suggestions
            ExtensionPickerList(
                items: rows.map {
                    ExtensionPickerItem(value: $0.title, title: $0.title, detail: $0.detail)
                },
                selection: highlighted, chosen: [], assetsPath: nil,
                onSelect: { choose(rows, at: $0) },
                onHighlight: { highlighted = $0 }
            )
            .offset(y: placement.y - anchor.frame.minY)
            .zIndex(1)
        }
    }

    /// Where the list opens, decided by the shipped rule against the control's measured place.
    private var placement: ExtensionFormMetrics.Placement {
        ExtensionFormMetrics.placement(
            anchor: anchor.frame,
            popoverHeight: ExtensionFormMetrics.popoverHeight(
                rows: suggestions.count, hasSearchField: false),
            containerHeight: anchor.containerHeight)
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
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let rows = suggestions.count
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
