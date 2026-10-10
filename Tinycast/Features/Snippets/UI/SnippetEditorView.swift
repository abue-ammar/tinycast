import SwiftUI

struct SnippetEditorView: View {
    @Bindable var editor: SnippetEditorSession
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    @Environment(SnippetCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @State private var focusedField: SnippetEditorSession.Field?
    @FocusState private var focusedControl: SnippetEditorSession.Field?
    @State private var placeholderMenuFrame: CGRect = .zero

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: metrics.spacing.xxl) {
                templateEditor
                properties
            }
            .padding(.horizontal, metrics.spacing.xxxl * 2)
            .padding(.vertical, metrics.spacing.md)
        }
        .scrollClipDisabled()
        .edgeDissolve()
        .disabled(editor.isSaving)
        .focusEffectDisabled()
        .task(id: palette.focusToken) {
            palette.noteEditingField(true)
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = editor.focusedField
        }
        .task(id: editor.isSaving) {
            if editor.isSaving { await coordinator.saveSnippet(editor) }
        }
        .onChange(of: editor.focusedField) { _, field in focusedField = field }
        .onChange(of: focusedField) { _, field in
            if let field { editor.focusedField = field }
            focusedControl = field == .enabled || field == .confirmation ? field : nil
        }
        .onChange(of: focusedControl) { _, field in
            if let field { focusedField = field }
        }
        .onDisappear {
            coordinator.editorDidClose(editor)
            palette.noteEditingField(false)
        }
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            fieldTitle("Snippet")
            VStack(spacing: metrics.spacing.xs) {
                FormTextArea(
                    text: $editor.text, selection: $editor.selection, focused: focusBinding(.template),
                    minimumHeight: metrics.size.panelHeight - metrics.size.headerHeight * 4
                        - metrics.spacing.xl - metrics.spacing.md * 2 - metrics.spacing.xs
                        - metrics.typography.textNSFont(.callout).boundingRectForFont.height,
                    label: "Snippet template", moveFocus: editor.advanceFocus
                )
                .accessibilityHint("Enter the text Tinycast expands.")
                HStack {
                    placeholderMenu
                    Spacer()
                }
                .padding(.horizontal, metrics.spacing.xl)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .zIndex(1)
            }
            .padding(.bottom, metrics.spacing.md)
            .formFieldChrome(focused: focusedField == .template)
            Text("Use placeholders for the clipboard, current date, arguments and more.")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholderMenu: some View {
        Button("Insert…", action: showPlaceholderMenu)
            .buttonStyle(.plain)
            .fixedSize()
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                placeholderMenuFrame = $0
            }
            .tooltip("Insert a dynamic placeholder", alignment: .leading, dismissOnPress: true)
            .accessibilityLabel("Insert a placeholder")
    }

    private func showPlaceholderMenu() {
        let insertionSelection = editor.selection
        let groups: [(title: String, tokens: [String])] = [
            ("Text", ["{cursor}", "{clipboard}", "{selection}", "{uuid}"]),
            ("Date & Time", ["{date}", "{time}", "{datetime}", "{day}"]),
            ("Arguments", ["{argument name=\"Name\"}"]),
            ("Snippets", ["{snippet name=\"Name\"}"])
        ]
        let items = groups.flatMap { group in
            group.tokens.enumerated().map { index, token in
                PopoverMenuItem(
                    title: token, icon: .blank, sectionTitle: index == 0 ? group.title : nil,
                    startsSection: index == 0
                ) {
                    editor.selection = insertionSelection
                    editor.insert(token)
                    focusedField = .template
                }
            }
        }
        openInputMenu(
            PopoverMenuContent(items: items), .belowControl(placeholderMenuFrame, trailing: false), 0)
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
            field(
                "Name", placeholder: "Snippet name", text: $editor.name,
                focus: .name,
                hint: "Required. Shown in the library and launcher.")
            field(
                "Keyword", placeholder: "Optional, for example !notes", text: $editor.keyword,
                focus: .keyword, hint: "Optional. Type this to expand the snippet.")
            option(
                "Enabled", detail: "Disabled snippets cannot be expanded.",
                value: $editor.isEnabled, focus: .enabled)
            option(
                "Show confirmation", detail: "Confirm on screen after this snippet is inserted.",
                value: $editor.showsConfirmation, focus: .confirmation)
            if let errorMessage = editor.errorMessage {
                Text(errorMessage)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .font(metrics.typography.rowTitle)
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func field(
        _ title: String, placeholder: String, text: Binding<String>,
        focus: SnippetEditorSession.Field, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            fieldTitle(title)
            FormTextInput(
                text: text, focused: focusBinding(focus), placeholder: placeholder,
                label: "Snippet \(title.lowercased())", moveFocus: editor.advanceFocus
            )
            .frame(height: metrics.size.dialogButtonHeight)
            .formFieldChrome(focused: focusedField == focus)
            .accessibilityHint(hint)
        }
    }

    private func focusBinding(_ field: SnippetEditorSession.Field) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { value in
                if value { focusedField = field } else if focusedField == field { focusedField = nil }
            })
    }

    private func option(
        _ title: String, detail: String, value: Binding<Bool>, focus: SnippetEditorSession.Field
    ) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .focusable()
        .focused($focusedControl, equals: focus)
        .onKeyPress(.space) {
            value.wrappedValue.toggle()
            return .handled
        }
    }
}
