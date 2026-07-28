import SwiftUI

/// The `Form` screen. Field values live in the extension (React owns them); every edit dispatches back
/// through the field's `onTinycastChange`, and the re-render is what updates what's drawn here.
struct ExtensionFormView: View {
    let screen: ExtensionScreen
    let assetsPath: String?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(screen.fields) { field in
                    fieldView(field)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
    }

    @ViewBuilder
    private func fieldView(_ field: RenderNode) -> some View {
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
                    node: field, secure: field.type == "Form.PasswordField", onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.TextArea":
            labelled(field) {
                ExtensionTextArea(node: field, onChange: onChange)
            }

        case "Form.Checkbox":
            HStack(spacing: Theme.Spacing.sm) {
                Toggle(
                    field.string("label") ?? field.string("title") ?? "",
                    isOn: Binding(
                        get: { field.bool("value") ?? false },
                        set: { onChange(field, $0) })
                )
                .toggleStyle(.checkbox)
            }
            .padding(.leading, Theme.Size.formLabelWidth + Theme.Spacing.md)

        case "Form.Dropdown":
            labelled(field) {
                Picker(
                    "",
                    selection: Binding(
                        get: { field.string("value") ?? "" },
                        set: { onChange(field, $0) })
                ) {
                    ForEach(dropdownItems(field), id: \.value) { item in
                        Text(item.title).tag(item.value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)
            }

        case "Form.TagPicker":
            labelled(field) {
                ExtensionTagPicker(node: field, assetsPath: assetsPath, onChange: onChange)
            }

        case "Form.DatePicker":
            labelled(field) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { field.date("value") ?? Date() },
                        set: { onChange(field, ["$date": ISO8601DateFormatter().string(from: $0)]) }),
                    displayedComponents: field.string("type") == "date"
                        ? [.date] : [.date, .hourAndMinute]
                )
                .labelsHidden()
            }

        case "Form.FilePicker":
            labelled(field) {
                ExtensionFilePicker(node: field, onChange: onChange)
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

    private struct DropdownItem: Hashable {
        let title: String
        let value: String
    }

    /// Items may be direct children or grouped in sections.
    private func dropdownItems(_ field: RenderNode) -> [DropdownItem] {
        var items: [DropdownItem] = []
        func walk(_ node: RenderNode) {
            for child in node.children {
                if child.type.hasSuffix(".Item") {
                    let value = child.string("value") ?? ""
                    items.append(DropdownItem(title: child.string("title") ?? value, value: value))
                } else if child.type.hasSuffix(".Section") {
                    walk(child)
                }
            }
        }
        walk(field)
        return items
    }
}

/// A text field whose value is owned by the extension: local state absorbs typing so the caret never
/// jumps, and a render carrying a different value (a programmatic reset) wins.
private struct ExtensionTextField: View {
    let node: RenderNode
    let secure: Bool
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
                    .fill(Color.white.opacity(0.06))
            )
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

/// `Form.TagPicker` — multi-select over its items, rendered as toggleable chips.
private struct ExtensionTagPicker: View {
    let node: RenderNode
    let assetsPath: String?
    let onChange: (RenderNode, Any) -> Void

    private var selected: [String] { node.array("value").compactMap(\.stringValue) }

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.xs) {
            ForEach(node.children.filter { $0.type.hasSuffix(".Item") }) { item in
                let value = item.string("value") ?? ""
                let isOn = selected.contains(value)
                Button {
                    onChange(node, isOn ? selected.filter { $0 != value } : selected + [value])
                } label: {
                    HStack(spacing: 3) {
                        if let icon = item.props["icon"] {
                            ExtensionIconView(
                                resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath),
                                size: 12)
                        }
                        Text(item.string("title") ?? value).font(Theme.Typography.rowTrailing)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isOn ? Theme.Colors.selection : Color.white.opacity(0.05))
                    )
                    .overlay(
                        Capsule().stroke(
                            isOn ? Color.white.opacity(0.3) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ExtensionFilePicker: View {
    let node: RenderNode
    let onChange: (RenderNode, Any) -> Void

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
