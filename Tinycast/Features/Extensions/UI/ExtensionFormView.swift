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
                VStack(alignment: .leading, spacing: ExtensionFormMetrics.rowSpacing) {
                    ForEach(screen.fields) { field in
                        row(field)
                    }
                }
                // Centred as a block, the way Raycast seats a form in its panel; the label column
                // and the controls keep their own widths inside it.
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExtensionFormMetrics.formVerticalPadding)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            // The space a picker measures itself in, so a list near the bottom can flip upward.
            .coordinateSpace(name: ExtensionFormCoordinateSpace.name)
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
                // A picker's list must cover the fields below it, which a later row would paint over.
                .zIndex(item.index == selection ? 1 : 0)
        } else {
            fieldView(field, index: nil)
        }
    }

    /// `index` is nil for a field nothing lands on — a separator, a description, an accessory.
    @ViewBuilder
    private func fieldView(_ field: RenderNode, index: Int?) -> some View {
        switch field.type {
        case "Form.Separator":
            Rectangle()
                .fill(Theme.Colors.separator)
                // Spans the label column and the control together, as Raycast's rule does.
                .frame(
                    width: Theme.Size.formLabelWidth + Theme.Spacing.md
                        + ExtensionFormMetrics.controlWidth,
                    height: 1)
                .padding(.vertical, ExtensionFormMetrics.separatorSpacing)

        case "Form.Description":
            labelled(field, showTitle: field.string("title") != nil) {
                Text(field.string("text") ?? "")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    // Text with no chrome around it still occupies a control's height, so the
                    // label beside it sits where every other row's label does.
                    .padding(.vertical, ExtensionFormMetrics.verticalInset)
                    .frame(minHeight: ExtensionFormMetrics.controlHeight, alignment: .leading)
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
            labelled(field, showTitle: field.string("title") != nil) {
                ExtensionCheckbox(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.Dropdown":
            labelled(field) {
                ExtensionPickerField(
                    items: ExtensionFormView.items(in: field),
                    chosen: [field.string("value") ?? ""].filter { !$0.isEmpty },
                    placeholder: field.string("placeholder") ?? "Select…",
                    title: field.string("title") ?? "Dropdown",
                    assetsPath: assetsPath,
                    allowsMultipleSelection: false,
                    index: index, focus: $focused,
                    onChange: { onChange(field, $0.first ?? "") },
                    onSubmit: onSubmit)
            }

        case "Form.TagPicker":
            labelled(field) {
                ExtensionPickerField(
                    items: ExtensionFormView.items(in: field),
                    chosen: field.array("value").compactMap(\.stringValue),
                    placeholder: field.string("placeholder") ?? "Select…",
                    title: field.string("title") ?? "Tags",
                    assetsPath: assetsPath,
                    allowsMultipleSelection: true,
                    index: index, focus: $focused,
                    onChange: { onChange(field, $0) },
                    onSubmit: onSubmit)
            }

        case "Form.DatePicker":
            labelled(field) {
                ExtensionDateField(
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

    /// Items may be direct children or grouped in sections.
    static func items(in field: RenderNode) -> [ExtensionPickerItem] {
        var items: [ExtensionPickerItem] = []
        func walk(_ node: RenderNode, section: String?) {
            for child in node.children {
                if child.type.hasSuffix(".Item") {
                    let value = child.string("value") ?? ""
                    items.append(
                        ExtensionPickerItem(
                            value: value, title: child.string("title") ?? value,
                            iconValue: child.props["icon"], section: section))
                } else if child.type.hasSuffix(".Section") {
                    walk(child, section: child.string("title"))
                }
            }
        }
        walk(field, section: nil)
        return items
    }

    /// Raycast forms are label-left / control-right; the fixed label column keeps controls aligned.
    @ViewBuilder
    private func labelled<Content: View>(
        _ field: RenderNode, showTitle: Bool = true, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xxs) {
                Spacer(minLength: 0)
                Text(showTitle ? (field.string("title") ?? "") : "")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                // The info marker Raycast draws beside a label that carries one.
                if let info = field.string("info"), !info.isEmpty {
                    Image(systemName: "info.circle")
                        .font(Theme.Typography.disclosure)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .help(info)
                }
            }
            .frame(width: Theme.Size.formLabelWidth, alignment: .trailing)
            // Centred on the control's first line: Raycast centres a label against a one-line
            // control and holds it level with the first line of a taller one.
            .frame(height: ExtensionFormMetrics.controlHeight)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                content()
                if let error = field.string("error"), !error.isEmpty {
                    Text(error)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(.red)
                }
            }
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
    /// The last edit dispatched, so an echo of an older one cannot overwrite newer typing.
    @State private var sent: String?
    @State private var hovered = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .font(Theme.Typography.rowTitle)
        .focused($focus, equals: index)
        .extensionFieldChrome(focused: focus == index, hovered: hovered)
        .onHover { hovered = $0 }
        .onSubmit(onSubmit)
        // The visible label is a Text in the row beside it, which the field cannot claim itself.
        .accessibilityLabel(Text(node.string("title") ?? node.string("placeholder") ?? "Text"))
        .onAppear { text = node.string("value") ?? "" }
        .onChange(of: node.string("value") ?? "") { _, incoming in
            adopt(incoming)
        }
        .onChange(of: text) { _, outgoing in
            guard outgoing != (node.string("value") ?? "") else { return }
            sent = outgoing
            onChange(node, outgoing)
        }
    }

    /// React answers a keystroke a render late, so an echo arriving mid-word is older than what
    /// has been typed since. Only once the echo catches up does the extension own the value again.
    private func adopt(_ incoming: String) {
        if let sent {
            guard incoming == sent else { return }
            self.sent = nil
            return
        }
        if incoming != text { text = incoming }
    }

    private var prompt: Text {
        Text(node.string("placeholder") ?? "").foregroundStyle(Theme.Colors.textTertiary)
    }
}

private struct ExtensionTextArea: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    @State private var text: String = ""
    /// The last edit dispatched; see `ExtensionTextField.adopt` for why an echo can be stale.
    @State private var sent: String?
    @State private var hovered = false

    var body: some View {
        TextEditor(text: $text)
            .font(Theme.Typography.rowTitle)
            .scrollContentBackground(.hidden)
            // The text system insets its own line fragments, which the chrome's inset then repeats.
            .padding(.horizontal, -ExtensionFormMetrics.textViewGutter)
            .focused($focus, equals: index)
            .extensionFieldChrome(focused: focus == index, hovered: hovered, multiline: true)
            .onHover { hovered = $0 }
            .accessibilityLabel(Text(node.string("title") ?? "Text area"))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(node.string("placeholder") ?? "")
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.horizontal, ExtensionFormMetrics.textInset)
                        .padding(.vertical, ExtensionFormMetrics.verticalInset)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { text = node.string("value") ?? "" }
            .onChange(of: node.string("value") ?? "") { _, incoming in
                if let sent {
                    guard incoming == sent else { return }
                    self.sent = nil
                    return
                }
                if incoming != text { text = incoming }
            }
            .onChange(of: text) { _, outgoing in
                guard outgoing != (node.string("value") ?? "") else { return }
                sent = outgoing
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
    @State private var hovered = false

    private var isOn: Bool { node.bool("value") ?? false }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Spacing.sm) {
                box
                Text(node.string("label") ?? "")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            // No field chrome: a checkbox is its own box, and a second one around it reads as a well.
            .frame(width: ExtensionFormMetrics.controlWidth, alignment: .leading)
            .frame(height: ExtensionFormMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus, equals: index)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .onKeyPress(.space) {
            toggle()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(node.string("label") ?? node.string("title") ?? "Checkbox"))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            onSubmit()
            return .handled
        }
    }

    /// Drawn rather than an SF Symbol pair: the filled and empty symbols differ in optical weight,
    /// so a row of them jitters as it is ticked.
    private var box: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isOn ? Color.accentColor : ExtensionColors.fieldFill)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(
                width: ExtensionFormMetrics.checkboxSize,
                height: ExtensionFormMetrics.checkboxSize)
    }

    private var borderColor: Color {
        if focus == index { return ExtensionColors.fieldFocusStroke }
        if isOn { return .clear }
        return hovered ? ExtensionColors.fieldFocusStroke : ExtensionColors.checkboxStroke
    }

    /// A click takes focus too, so the keyboard carries on from where the pointer left off.
    private func toggle() {
        focus = index
        onChange(node, !isOn)
    }
}

private struct ExtensionFilePicker: View {
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    private var paths: [String] { node.array("value").compactMap(\.stringValue) }
    @State private var hovered = false

    private var label: String {
        guard !paths.isEmpty else { return "Choose…" }
        return paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "doc")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(label)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(paths.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .extensionFieldChrome(focused: focus == index, hovered: hovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus, equals: index)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .onKeyPress(.space) {
            choose()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(node.string("title") ?? "File"))
        .accessibilityValue(Text(label))
        .accessibilityAddTraits(.isButton)
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            choose()
            return .handled
        }
    }

    private func choose() {
        focus = index
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = node.bool("allowMultipleSelection") ?? true
        panel.canChooseDirectories = node.bool("canChooseDirectories") ?? false
        panel.canChooseFiles = node.bool("canChooseFiles") ?? true
        guard panel.runModal() == .OK else { return }
        onChange(node, panel.urls.map(\.path))
    }
}
