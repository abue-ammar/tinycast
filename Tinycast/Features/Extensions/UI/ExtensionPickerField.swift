import SwiftUI

/// `Form.Dropdown` and `Form.TagPicker`: one control, typing and caret in the field itself.
struct ExtensionPickerField: View {
    let items: [ExtensionPickerItem]
    /// Every value currently held; a dropdown has one, a tag picker any number.
    let chosen: [String]
    let placeholder: String
    /// The field's own title, so the control announces what it is rather than as a chevron.
    let title: String
    /// The field's own explanation, spoken after the state so both are heard.
    let info: String?
    /// Whatever the extension reports wrong with the field, spoken before anything else.
    let error: String?
    let assetsPath: String?
    let allowsMultipleSelection: Bool
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: ([String]) -> Void
    let onSubmit: () -> Void

    @State private var open = false
    @State private var query = ""
    /// When the query last changed, which is where the caret's blink restarts from.
    @State private var typedAt = Date()
    @State private var highlighted = 0
    @State private var hovered = false
    /// Reported by the panel once it has placed itself, for the chevron that points its way.
    @State private var flipped = false
    /// Read from the view, so a resolved icon repaints when the surface flips appearance.
    @Environment(\.isDarkAppearance) private var isDark
    /// Told while the list is up, so the palette leaves every navigation key to it.
    @Environment(PaletteState.self) private var palette

    private var isFocused: Bool { focus == index }

    /// What a screen reader hears: the query while searching, else the value held.
    private var announcedValue: String {
        guard open, !query.isEmpty else { return chosen.isEmpty ? placeholder : label }
        return chosen.isEmpty ? query : "\(label), searching \(query)"
    }

    /// What the control does, then whatever the extension explains about the field.
    private var hint: String {
        let state = open ? "Showing choices" : "Opens a list of choices"
        let parts = [error, info].compactMap { $0 }.filter { !$0.isEmpty }
        return ([state] + parts).joined(separator: ". ")
    }

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

    /// Headings the open list draws, which its height and its flip decision both count.
    private var sectionCount: Int {
        let matches = matches
        return matches.indices.reduce(into: 0) { total, index in
            guard let section = matches[index].section else { return }
            if index == 0 || matches[index - 1].section != section { total += 1 }
        }
    }

    var body: some View {
        control
            .focusable()
            .focused($focus, equals: index)
            // The chrome draws the focused edge, so AppKit's blue ring would be a second one.
            .focusEffectDisabled()
            .extensionListPanel(
                open: open, height: listHeight, revision: revision, flipped: $flipped
            ) {
                ExtensionPickerList(
                    items: matches, selection: highlighted, chosen: Set(chosen),
                    assetsPath: assetsPath, onSelect: { choose(at: $0) },
                    onHighlight: { highlighted = $0 })
            }
            // One handler: the list's panel never takes key, so every press lands here.
            .onKeyPress(phases: [.down, .repeat]) { press in
                switch ExtensionListKey(press: press, listOpen: open) {
                case .openList: return openList()
                case .moveUp: return move(-1)
                case .moveDown: return move(1)
                case .commit:
                    choose(at: highlighted)
                    return .handled
                case .dismiss:
                    close()
                    return .handled
                case .append(let characters):
                    query += characters
                    highlighted = 0
                    return .handled
                case .deleteBackward:
                    guard !query.isEmpty else { return .handled }
                    query.removeLast()
                    highlighted = 0
                    return .handled
                case .stepValue(let delta): return step(delta)
                case .submitForm:
                    onSubmit()
                    return .handled
                case .ignored: return .ignored
                }
            }
            .onChange(of: open) { palette.noteControlListOpen(open) }
            .onChange(of: query) { typedAt = Date() }
            .onScrollVisibilityChange { if !$0 { close() } }
            .onDisappear { if open { palette.noteControlListOpen(false) } }
            .onChange(of: focus) { _, focus in
                // Focus leaving the field takes its list with it.
                if focus != index { close() }
            }
    }

    private var control: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let leadingIcon, query.isEmpty {
                ExtensionIconView(resolved: leadingIcon, size: 14)
            }
            // While the list is open the control is the search field, caret and all.
            if open {
                // A multi-select keeps its chosen values in view while the query is typed.
                if allowsMultipleSelection, !chosen.isEmpty {
                    Text(label)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Text("·")
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                ExtensionQueryText(query: query, prompt: "Search…", phase: typedAt)
            } else {
                Text(label)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(
                        chosen.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            ExtensionDisclosureChevron(open: open, flipped: flipped)
        }
        .extensionFieldChrome(focused: isFocused, open: open, hovered: hovered)
        .contentShape(Rectangle())
        // Without this the control reads as its chevron: no name, no value, no role.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        // While open the control is a search field, so it announces what is being typed.
        .accessibilityValue(Text(announcedValue))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(.isButton)
        .onHover { hovered = $0 }
        .onTapGesture {
            focus = index
            if open { close() } else { _ = openList() }
        }
    }

    /// The panel's own height, which the placement rule then seats above or below the control.
    private var listHeight: CGFloat {
        ExtensionFormMetrics.popoverHeight(
            rows: matches.count, hasSearchField: false, headers: sectionCount)
    }

    /// What the hosted list draws; a change to any of it re-pushes the panel's tree.
    private struct Revision: Equatable {
        let query: String
        let highlighted: Int
        let isDark: Bool
        let chosen: [String]
        let items: [ExtensionPickerItem]
        let assetsPath: String?
    }

    private var revision: Revision {
        Revision(
            query: query, highlighted: highlighted, isDark: isDark,
            chosen: chosen, items: matches, assetsPath: assetsPath)
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
