import SwiftUI

/// React owns the values; every edit dispatches back and the re-render draws it.
struct ExtensionFormView: View {
    let screen: ExtensionScreen
    let assetsPath: String?
    /// The focused field, as the flat index the palette navigates with.
    let selection: Int
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void
    /// Told when a control owns the keyboard, so a bare backspace edits instead of backing out.
    @Environment(PaletteState.self) private var palette
    @FocusState private var focused: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(screen.fields) { field in
                        row(field)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: focusedRowID, atOrigin: selection == 0, proxy: proxy)
        }
        // A form arrives with whatever row the screen before it left behind, so it states its own.
        .onAppear { focus(screen.autoFocusedField) }
        .onDisappear { palette.noteEditingField(false) }
        // The palette moves the selection with ↑/↓ and ⇥; focus follows it, and a click leads it.
        .onChange(of: selection) { focus(selection) }
        .onChange(of: focused) { _, field in
            palette.noteEditingField(field != nil)
            if let field, field != selection { onSelect(field) }
        }
    }

    private func focus(_ index: Int) {
        guard screen.items.indices.contains(index) else { return }
        focused = index
        if index != selection { onSelect(index) }
    }

    /// Scroll id of the focused field, or nil when the form has nothing to land on.
    private var focusedRowID: String? {
        screen.items.indices.contains(selection) ? screen.items[selection].id : nil
    }

    /// One drawn field, wired into the focus order `ExtensionScreen` decided.
    @ViewBuilder
    private func row(_ field: RenderNode) -> some View {
        if let item = screen.focusItem(for: field) {
            fieldView(field, index: item.index)
                .id(item.id)
                .selectionFrame(item.index == selection)
        } else {
            fieldView(field, index: nil)
        }
    }

    /// `index` is nil for a field nothing lands on — a separator, a description, an accessory.
    @ViewBuilder
    private func fieldView(_ field: RenderNode, index: Int?) -> some View {
        switch field.type {
        case "Form.Separator":
            Rectangle().fill(Theme.Colors.separator).frame(height: 1)

        case "Form.Description":
            labelled(field, showTitle: field.string("title") != nil) {
                Text(field.string("text") ?? "")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

        case "Form.TextField", "Form.PasswordField":
            labelled(field) {
                ExtensionTextField(
                    node: field, secure: field.type == "Form.PasswordField", index: index,
                    focus: $focused, onChange: onChange, onSubmit: onSubmit)
            }

        case "Form.TextArea":
            labelled(field) {
                ExtensionTextArea(
                    node: field, index: index, focus: $focused, onChange: onChange)
            }

        case "Form.Checkbox":
            HStack(spacing: Theme.Spacing.sm) {
                ExtensionCheckbox(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }
            .padding(.leading, Theme.Size.formLabelWidth + Theme.Spacing.md)

        case "Form.Dropdown":
            labelled(field) {
                ExtensionDropdown(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.TagPicker":
            labelled(field) {
                ExtensionTagPicker(
                    node: field, assetsPath: assetsPath, index: index, focus: $focused,
                    onChange: onChange, onSubmit: onSubmit)
            }

        case "Form.DatePicker":
            labelled(field) {
                ExtensionDatePicker(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.FilePicker":
            labelled(field) {
                ExtensionFilePicker(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.LinkAccessory":
            EmptyView()

        default:
            labelled(field) {
                Text("\(field.type) isn't supported yet")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Raycast forms are label-left / control-right; the fixed label column keeps controls aligned.
    @ViewBuilder
    private func labelled<Content: View>(
        _ field: RenderNode, showTitle: Bool = true, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(showTitle ? (field.string("title") ?? "") : "")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.formLabelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                content()
                if let info = field.string("info"), !info.isEmpty {
                    Text(info)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(.tertiary)
                }
                if let error = field.string("error"), !error.isEmpty {
                    Text(error)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Written here rather than in `DesignSystem`: how an extension's form shows focus is its own.
private struct FormFocusRing: ViewModifier {
    let showing: Bool

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                .strokeBorder(showing ? ExtensionColors.fieldFocusStroke : .clear, lineWidth: 2)
                .padding(-Theme.Spacing.xxs)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// A drawn ring for the controls AppKit rings for nobody; a text field shows its own.
    fileprivate func formFocusRing(_ showing: Bool) -> some View {
        modifier(FormFocusRing(showing: showing))
    }

    /// ↵ from a control that edits no text runs the form's action, exactly as Raycast does.
    fileprivate func submitsOnReturn(_ onSubmit: @escaping () -> Void) -> some View {
        onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            onSubmit()
            return .handled
        }
    }
}

/// Local state absorbs typing so the caret never jumps; a programmatic reset wins.
private struct ExtensionTextField: View {
    let node: RenderNode
    let secure: Bool
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void
    @State private var text: String = ""

    var body: some View {
        Group {
            if secure {
                SecureField(node.string("placeholder") ?? "", text: $text)
            } else {
                TextField(node.string("placeholder") ?? "", text: $text)
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 320)
        .focused($focus, equals: index)
        .onSubmit(onSubmit)
        .onAppear { text = node.string("value") ?? "" }
        .onChange(of: node.string("value") ?? "") { _, incoming in
            if incoming != text { text = incoming }
        }
        .onChange(of: text) { _, outgoing in
            guard outgoing != (node.string("value") ?? "") else { return }
            onChange(node, outgoing)
        }
    }
}

private struct ExtensionTextArea: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    @State private var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .font(Theme.Typography.rowTitle)
            .scrollContentBackground(.hidden)
            .padding(Theme.Spacing.xs)
            .frame(maxWidth: 420, minHeight: 72, maxHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            )
            .focused($focus, equals: index)
            .formFocusRing(focus == index)
            .onAppear { text = node.string("value") ?? "" }
            .onChange(of: node.string("value") ?? "") { _, incoming in
                if incoming != text { text = incoming }
            }
            .onChange(of: text) { _, outgoing in
                guard outgoing != (node.string("value") ?? "") else { return }
                onChange(node, outgoing)
            }
    }
}

/// Its own control, not `Toggle`: a `Toggle` takes focus only under Full Keyboard Access.
private struct ExtensionCheckbox: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    private var isOn: Bool { node.bool("value") ?? false }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(isOn ? Color.accentColor : Theme.Colors.textSecondary)
                Text(node.string("label") ?? node.string("title") ?? "")
                    .font(Theme.Typography.rowTitle)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus, equals: index)
        .formFocusRing(focus == index)
        .onKeyPress(.space) {
            toggle()
            return .handled
        }
        .submitsOnReturn(onSubmit)
    }

    private func toggle() { onChange(node, !isOn) }
}

/// A native pop-up button, so its menu opens from the keyboard as well as from a click.
private struct ExtensionDropdown: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void
    /// Owned here so the menu opens from a key press rather than from inside a view update.
    @State private var opener = ExtensionMenuOpener()

    var body: some View {
        let items = ExtensionDropdownItem.all(in: node)
        ExtensionPopUpButton(
            items: items, selected: node.string("value") ?? "", opener: opener,
            onSelect: { onChange(node, $0) }
        )
        .frame(maxWidth: 260, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .focusable()
        .focused($focus, equals: index)
        .formFocusRing(focus == index)
        // Space and ↵ both open it, the way a focused pop-up button behaves everywhere else.
        .onKeyPress(.space) { open() }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            return open()
        }
        .onKeyPress(.leftArrow) { step(-1, in: items) }
        .onKeyPress(.rightArrow) { step(1, in: items) }
    }

    private func open() -> KeyPress.Result {
        opener.open()
        return .handled
    }

    /// Clamped rather than wrapping, so holding an arrow settles at an end like every other list.
    private func step(_ delta: Int, in items: [ExtensionDropdownItem]) -> KeyPress.Result {
        let current = items.firstIndex { $0.value == node.string("value") ?? "" } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        guard items.indices.contains(next), next != current else { return .handled }
        onChange(node, items[next].value)
        return .handled
    }
}

/// `Form.TagPicker` — multi-select over its items, rendered as toggleable chips.
private struct ExtensionTagPicker: View {
    @Environment(\.isDarkAppearance) private var isDark
    let node: RenderNode
    let assetsPath: String?
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void
    /// Which chip the arrows act on: the field's own cursor, kept apart from the form's focus.
    @State private var cursor = 0

    private var items: [RenderNode] { node.children.filter { $0.type.hasSuffix(".Item") } }
    private var selected: [String] { node.array("value").compactMap(\.stringValue) }

    var body: some View {
        let items = items
        FlowLayout(spacing: Theme.Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                chip(item, at: position)
            }
        }
        .focusable()
        .focused($focus, equals: index)
        .formFocusRing(focus == index)
        .onKeyPress(.leftArrow) { move(-1, count: items.count) }
        .onKeyPress(.rightArrow) { move(1, count: items.count) }
        .onKeyPress(.space) {
            guard items.indices.contains(cursor) else { return .ignored }
            toggle(items[cursor].string("value") ?? "")
            return .handled
        }
        .submitsOnReturn(onSubmit)
    }

    private func chip(_ item: RenderNode, at position: Int) -> some View {
        let value = item.string("value") ?? ""
        let isOn = selected.contains(value)
        return Button {
            cursor = position
            toggle(value)
        } label: {
            HStack(spacing: 3) {
                if let icon = item.props["icon"] {
                    ExtensionIconView(
                        resolved: ExtensionImage.resolve(
                            icon, assetsPath: assetsPath, isDark: isDark),
                        size: 12)
                }
                Text(item.string("title") ?? value).font(Theme.Typography.rowTrailing)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(isOn ? Theme.Colors.selection : ExtensionColors.tagFill))
            .overlay(
                Capsule().stroke(
                    stroke(isOn: isOn, isCursor: focus == index && position == cursor),
                    lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func stroke(isOn: Bool, isCursor: Bool) -> Color {
        if isCursor { return ExtensionColors.fieldFocusStroke }
        return isOn ? ExtensionColors.tagSelectedStroke : .clear
    }

    private func move(_ delta: Int, count: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        cursor = min(max(cursor + delta, 0), count - 1)
        return .handled
    }

    private func toggle(_ value: String) {
        onChange(
            node, selected.contains(value) ? selected.filter { $0 != value } : selected + [value])
    }
}

private struct ExtensionDatePicker: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    var body: some View {
        DatePicker(
            "",
            selection: Binding(
                get: { node.date("value") ?? Date() },
                set: { onChange(node, ["$date": ISO8601DateFormatter().string(from: $0)]) }),
            displayedComponents: node.string("type") == "date" ? [.date] : [.date, .hourAndMinute]
        )
        .labelsHidden()
        .focused($focus, equals: index)
        .formFocusRing(focus == index)
        .submitsOnReturn(onSubmit)
    }
}

private struct ExtensionFilePicker: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    private var paths: [String] { node.array("value").compactMap(\.stringValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button("Choose…") { choose() }
            ForEach(paths, id: \.self) { path in
                Text((path as NSString).lastPathComponent)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
        .focusable()
        .focused($focus, equals: index)
        .formFocusRing(focus == index)
        .onKeyPress(.space) {
            choose()
            return .handled
        }
        .submitsOnReturn(onSubmit)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = node.bool("allowMultipleSelection") ?? true
        panel.canChooseDirectories = node.bool("canChooseDirectories") ?? false
        panel.canChooseFiles = node.bool("canChooseFiles") ?? true
        guard panel.runModal() == .OK else { return }
        onChange(node, panel.urls.map(\.path))
    }
}
