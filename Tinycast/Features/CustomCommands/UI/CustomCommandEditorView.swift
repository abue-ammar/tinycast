import SwiftUI

struct CustomCommandEditorView: View {
    @Bindable var editor: CustomCommandEditorSession
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    @Environment(CustomCommandCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedField: CustomCommandEditorSession.Field?
    @FocusState private var focusedControl: CustomCommandEditorSession.Field?
    @State private var iconMenuFrame: CGRect = .zero

    private struct FocusRequest: Hashable {
        let field: CustomCommandEditorSession.Field
        let token: UUID
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: metrics.spacing.xxl) {
                    FormRow("Name & Icon") { nameField }.id(CustomCommandEditorSession.Field.name)
                    FormRow("Command", alignment: .top) {
                        VStack(alignment: .leading, spacing: metrics.spacing.md) {
                            FormTextArea(
                                text: $editor.shellCommand, selection: $editor.selection,
                                focused: focusBinding(.command), minimumHeight: metrics.size.headerHeight * 2,
                                label: "Shell command", isCode: true, moveFocus: editor.advanceFocus
                            )
                            .formFieldChrome(focused: focusedField == .command)
                            detail("Example: /usr/bin/pmset displaysleepnow")
                        }
                    }
                    .id(CustomCommandEditorSession.Field.command)
                    FormRow("Run In", alignment: .top) { workingDirectoryField }
                        .id(CustomCommandEditorSession.Field.workingDirectory)
                    FormRow(
                        "Arguments", alignment: .top,
                        labelInset: editor.arguments.isEmpty ? 0 : metrics.spacing.lg
                    ) { argumentsSection }
                    FormRow("") {
                        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                            option(
                                "Show in root search",
                                detail: "List this command alongside apps and other commands.",
                                value: $editor.showsInRootSearch, focus: .rootSearch)
                            option(
                                "Load shell environment",
                                detail: "Sources ~/.zshrc for aliases, functions and PATH. Slower to start.",
                                value: $editor.loadsShellEnvironment, focus: .shellEnvironment)
                            option(
                                "Needs confirmation", detail: "Ask before running this command.",
                                value: $editor.requiresConfirmation, focus: .confirmation)
                            option(
                                "Show confirmation", detail: "Confirm on screen after the command succeeds.",
                                value: $editor.showsConfirmation, focus: .successConfirmation)
                            option(
                                "Show output", detail: "Open a window with everything the command prints.",
                                value: $editor.showsOutput, focus: .output)
                            if let errorMessage = editor.errorMessage {
                                detail(errorMessage).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, metrics.spacing.xxxl * 2)
                .padding(.vertical, metrics.spacing.md)
            }
            .scrollClipDisabled()
            .edgeDissolve()
            .focusEffectDisabled()
            .task(id: FocusRequest(field: editor.focusedField, token: palette.focusToken)) {
                palette.noteEditingField(true)
                let field = editor.focusedField
                focusedControl = isTextField(field) ? nil : field
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(scrollTarget(for: field))
                focusedField = field
            }
            .onChange(of: focusedField) { _, field in
                if let field, editor.focusedField != field { editor.focusedField = field }
                focusedControl = field.flatMap { isTextField($0) ? nil : $0 }
            }
            .onChange(of: focusedControl) { _, field in
                if let field { focusedField = field }
            }
            .onDisappear {
                coordinator.editorDidClose(editor)
                palette.noteEditingField(false)
            }
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var nameField: some View {
        HStack(spacing: 0) {
            FormTextInput(
                text: $editor.name, focused: focusBinding(.name), placeholder: "Command name",
                label: "Command name", moveFocus: editor.advanceFocus)
            Rectangle().fill(Theme.Colors.separator)
                .frame(width: Theme.Size.hairline, height: metrics.size.menuIcon)
            iconMenu
        }
        .frame(height: metrics.size.dialogButtonHeight)
        .formFieldChrome(focused: focusedField == .name || focusedField == .icon)
    }

    private static let iconSymbols = [
        "terminal", "hammer", "wrench", "gearshape", "bolt", "arrow.clockwise", "trash",
        "shippingbox", "cube", "server.rack", "externaldrive", "internaldrive", "cloud",
        "arrow.up.circle", "arrow.down.circle", "doc.text", "folder", "magnifyingglass",
        "ladybug", "chevron.left.forwardslash.chevron.right", "network", "lock", "key",
        "display", "speaker.wave.2", "moon", "sun.max", "power", "clock", "calendar",
        "chart.bar", "flame"
    ]

    private var iconMenu: some View {
        let isOpen = openMenuCorner == .belowControl(iconMenuFrame)
        return HStack(spacing: metrics.spacing.sm) {
            SymbolImage(
                name: editor.iconSymbol ?? CustomCommand.sfSymbol,
                size: metrics.scaled(Theme.Typography.menuSymbolSize))
            Image(systemName: "chevron.down")
                .font(metrics.typography.disclosure)
                .foregroundStyle(Theme.Colors.textSecondary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .frame(height: metrics.size.dialogButtonHeight)
        .contentShape(.rect)
        .onTapGesture(perform: showIconMenu)
        .fixedSize()
        .focusable()
        .focused($focusedControl, equals: .icon)
        .onKeyPress(keys: [.return, .space]) { _ in
            showIconMenu()
            return .handled
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            iconMenuFrame = $0
        }
        .tooltip("Choose an icon", alignment: .trailing, dismissOnPress: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Command icon")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showIconMenu() }
    }

    private func showIconMenu() {
        let items =
            [
                PopoverMenuItem(title: "Automatic", systemImage: CustomCommand.sfSymbol) {
                    editor.iconSymbol = nil
                }
            ]
            + Self.iconSymbols.enumerated().map { index, symbol in
                PopoverMenuItem(title: symbol, systemImage: symbol, startsSection: index == 0) {
                    editor.iconSymbol = symbol
                }
            }
        let selected = Self.iconSymbols.firstIndex { $0 == editor.iconSymbol }.map { $0 + 1 } ?? 0
        openInputMenu(PopoverMenuContent(items: items), .belowControl(iconMenuFrame), selected)
    }

    private var workingDirectoryField: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            HStack(spacing: 0) {
                FormTextInput(
                    text: $editor.workingDirectory, focused: focusBinding(.workingDirectory),
                    placeholder: "Home folder", label: "Run In", moveFocus: editor.advanceFocus)
                action(.chooseDirectory, perform: coordinator.chooseWorkingDirectory) { Text("Choose…") }
                    .padding(.horizontal, metrics.spacing.xl)
            }
            .frame(height: metrics.size.dialogButtonHeight)
            .formFieldChrome(focused: focusedField == .workingDirectory || focusedField == .chooseDirectory)
            detail("The folder the command starts in. Leave empty for your home folder.")
        }
    }

    private var argumentsSection: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            ForEach($editor.arguments) { $argument in
                let id = argument.id
                HStack(spacing: metrics.spacing.md) {
                    Text("$\((editor.arguments.firstIndex { $0.id == id } ?? 0) + 1)")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    FormTextInput(
                        text: $argument.name, focused: focusBinding(.argumentName(id)),
                        placeholder: "Argument name", label: "Argument name", moveFocus: editor.advanceFocus
                    )
                    .frame(height: metrics.size.dialogButtonHeight)
                    .formFieldChrome(focused: focusedField == .argumentName(id))
                    Toggle("Optional", isOn: $argument.isOptional)
                        .toggleStyle(.checkbox)
                        .focusable()
                        .focused($focusedControl, equals: .argumentOptional(id))
                        .onKeyPress(.space) {
                            argument.isOptional.toggle()
                            return .handled
                        }
                    action(.removeArgument(id), perform: { editor.removeArgument(id: id) }) {
                        Image(systemName: "minus.circle")
                    }
                    .accessibilityLabel("Remove argument")
                }
                .id(CustomCommandEditorSession.Field.argumentName(id))
            }
            action(.addArgument, perform: editor.addArgument) {
                HStack(spacing: metrics.spacing.sm) {
                    SymbolImage(name: "plus", size: metrics.scaled(Theme.Typography.menuSymbolSize))
                        .accessibilityHidden(true)
                    Text("Add Argument")
                }
            }
            .id(CustomCommandEditorSession.Field.addArgument)
            .foregroundStyle(
                editor.arguments.count < CustomCommandArgument.limit
                    ? Theme.Colors.textPrimary : Theme.Colors.textTertiary
            )
            .disabled(editor.arguments.count >= CustomCommandArgument.limit)
            detail(
                editor.arguments.isEmpty
                    ? "Add up to three, filled in beside the search field before the command runs."
                    : "Passed to the command in order as $1, $2 …")
        }
    }

    private func isTextField(_ field: CustomCommandEditorSession.Field) -> Bool {
        switch field {
        case .name, .command, .workingDirectory, .argumentName: true
        default: false
        }
    }

    private func scrollTarget(for field: CustomCommandEditorSession.Field) -> CustomCommandEditorSession.Field
    {
        switch field {
        case .icon: .name
        case .chooseDirectory: .workingDirectory
        case .argumentOptional(let id), .removeArgument(let id): .argumentName(id)
        default: field
        }
    }

    private func action<Label: View>(
        _ field: CustomCommandEditorSession.Field, perform: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        label()
            .contentShape(.rect)
            .onTapGesture(perform: perform)
            .focusable()
            .focused($focusedControl, equals: field)
            .onKeyPress(keys: [.return, .space]) { _ in
                perform()
                return .handled
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { perform() }
    }

    private func focusBinding(_ field: CustomCommandEditorSession.Field) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { value in
                if value { focusedField = field } else if focusedField == field { focusedField = nil }
            })
    }

    private func option(
        _ title: String, detail: String, value: Binding<Bool>, focus: CustomCommandEditorSession.Field
    ) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(title)
                self.detail(detail)
            }
        }
        .toggleStyle(.checkbox)
        .focusable()
        .focused($focusedControl, equals: focus)
        .onKeyPress(.space) {
            value.wrappedValue.toggle()
            return .handled
        }
        .id(focus)
    }
}
