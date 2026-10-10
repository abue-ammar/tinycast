import SwiftUI

struct QuicklinkEditorView: View {
    @Bindable var editor: QuicklinkEditorSession
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    @Environment(QuicklinkCoordinator.self) private var coordinator
    @Environment(AppIndex.self) private var appIndex
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedField: QuicklinkEditorSession.Field?
    @FocusState private var focusedControl: QuicklinkEditorSession.Field?
    @State private var iconMenuFrame: CGRect = .zero
    @State private var insertMenuFrame: CGRect = .zero
    @State private var applicationMenuFrame: CGRect = .zero

    var body: some View {
        ScrollView {
            VStack(spacing: metrics.spacing.xxl) {
                FormRow("Link", alignment: .top) { linkEditor }
                FormRow("Name & Icon") { nameField }
                FormRow("Open With") { applicationMenu }
                FormRow("") {
                    VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                        option(
                            "Show in root search", detail: "List this quicklink alongside apps and commands.",
                            value: $editor.showsInRootSearch, focus: .rootSearch)
                        option(
                            "Pin to top", detail: "Keep it above the other quicklinks.",
                            value: $editor.isPinned, focus: .pin)
                        if let errorMessage = editor.errorMessage {
                            Text(errorMessage)
                                .font(metrics.typography.rowTrailing)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
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
        .task(id: palette.focusToken) {
            palette.noteEditingField(true)
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = editor.focusedField
        }
        .onChange(of: editor.focusedField) { _, field in focusedField = field }
        .onChange(of: focusedField) { _, field in
            if let field { editor.focusedField = field }
            focusedControl = field == .link || field == .name ? nil : field
        }
        .onChange(of: focusedControl) { _, field in
            if let field { focusedField = field }
        }
        .onDisappear {
            coordinator.editorDidClose(editor)
            palette.noteEditingField(false)
        }
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            VStack(spacing: metrics.spacing.xs) {
                FormTextArea(
                    text: $editor.link, selection: $editor.selection, focused: focusBinding(.link),
                    minimumHeight: metrics.size.headerHeight * 2 + metrics.spacing.xl
                        - metrics.spacing.md * 2 - metrics.spacing.xs
                        - metrics.typography.textNSFont(.body).boundingRectForFont.height,
                    label: "Quicklink link", allowsLineBreaks: false, moveFocus: editor.advanceFocus
                )
                HStack {
                    Spacer()
                    insertMenu
                }
                .padding(.horizontal, metrics.spacing.xl)
                .foregroundStyle(Theme.Colors.textSecondary)
                .zIndex(1)
            }
            .padding(.bottom, metrics.spacing.md)
            .formFieldChrome(focused: focusedField == .link)
            destinationPreview
        }
    }

    @ViewBuilder
    private var destinationPreview: some View {
        let value = editor.link.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if value.isEmpty {
                EmptyView()
            } else if QuicklinkDestination.containsPlaceholder(value) {
                Text("Resolved when you open it — placeholders are filled in first.")
            } else if let destination = QuicklinkDestination.detect(value) {
                Label {
                    Text(destination.displayText).lineLimit(1).truncationMode(.middle)
                } icon: {
                    SymbolImage(name: destination.defaultSymbol, size: metrics.size.menuIcon)
                }
            } else {
                Text("This doesn't look like a URL, file path, or deeplink.")
                    .foregroundStyle(.orange)
            }
        }
        .font(metrics.typography.rowTrailing)
        .foregroundStyle(Theme.Colors.textSecondary)
    }

    private var insertMenu: some View {
        Button("Insert…") {
            let items = [
                placeholder("Argument", "{argument}"),
                placeholder("Named Argument", "{argument name=\"Query\"}"),
                placeholder("Clipboard", "{clipboard}", startsSection: true),
                placeholder("Selected Text", "{selection}"),
                placeholder("Date", "{date}", startsSection: true),
                placeholder("Time", "{time}"),
                placeholder("Date & Time", "{datetime}"),
                placeholder("Custom Date Format", "{date format=\"yyyy-MM-dd\"}"),
                placeholder("UUID", "{uuid}", startsSection: true)
            ]
            openInputMenu(PopoverMenuContent(items: items), .belowControl(insertMenuFrame), 0)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            insertMenuFrame = $0
        }
        .tooltip("Insert a dynamic placeholder", alignment: .trailing, dismissOnPress: true)
        .accessibilityLabel("Insert a placeholder")
    }

    private func placeholder(
        _ title: String, _ token: String, startsSection: Bool = false
    ) -> PopoverMenuItem {
        let insertionSelection = editor.selection
        return PopoverMenuItem(title: title, icon: .blank, startsSection: startsSection) {
            editor.selection = insertionSelection
            editor.insert(token)
            focusedField = .link
        }
    }

    private var nameField: some View {
        HStack(spacing: 0) {
            FormTextInput(
                text: $editor.name, focused: focusBinding(.name), placeholder: "Search GitHub",
                label: "Quicklink name", moveFocus: editor.advanceFocus
            )
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: Theme.Size.hairline, height: metrics.size.menuIcon)
            iconMenu
        }
        .frame(height: metrics.size.dialogButtonHeight)
        .formFieldChrome(focused: focusedField == .name || focusedField == .icon)
    }

    private static let iconSymbols = [
        "globe", "folder", "doc.text", "link", "star", "bookmark", "magnifyingglass", "cart",
        "envelope", "message", "calendar", "clock", "checklist", "chart.bar", "hammer", "wrench",
        "ladybug", "terminal", "chevron.left.forwardslash.chevron.right", "cloud", "server.rack",
        "lock", "person.2", "building.2", "graduationcap", "book", "music.note", "play.rectangle",
        "photo", "paintbrush", "creditcard", "map"
    ]

    private var iconMenu: some View {
        HStack(spacing: metrics.spacing.sm) {
            SymbolImage(
                name: editor.iconSymbol ?? QuicklinkDestination.detect(editor.link)?.defaultSymbol
                    ?? Quicklink.sfSymbol,
                size: metrics.scaled(Theme.Typography.menuSymbolSize))
            menuChevron(for: iconMenuFrame)
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
        .accessibilityLabel("Quicklink icon")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showIconMenu() }
    }

    private func showIconMenu() {
        let items =
            [
                PopoverMenuItem(title: "Automatic", systemImage: Quicklink.sfSymbol) {
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

    private func menuChevron(for frame: CGRect) -> some View {
        let isOpen = openMenuCorner == .belowControl(frame)
        return Image(systemName: "chevron.down")
            .font(metrics.typography.disclosure)
            .foregroundStyle(Theme.Colors.textSecondary)
            .rotationEffect(.degrees(isOpen ? 180 : 0))
            .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
    }

    private var applicationMenu: some View {
        let application = editor.openWithBundleID.map { AppPresentation.resolve(bundleID: $0, in: appIndex) }
        return HStack(spacing: metrics.spacing.lg) {
            if let application {
                Image(nsImage: application.icon).resizable()
                    .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                Text(application.name).lineLimit(1)
            } else {
                Text("Default app")
            }
            Spacer(minLength: 0)
            menuChevron(for: applicationMenuFrame)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.spacing.xl)
        .frame(height: metrics.size.dialogButtonHeight)
        .contentShape(.rect)
        .onTapGesture(perform: showApplicationMenu)
        .focusable()
        .focused($focusedControl, equals: .application)
        .onKeyPress(keys: [.return, .space, .downArrow]) { _ in
            showApplicationMenu()
            return .handled
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            applicationMenuFrame = $0
        }
        .formFieldChrome(focused: focusedField == .application)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open With")
        .accessibilityValue(application?.name ?? "Default app")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showApplicationMenu() }
    }

    private func showApplicationMenu() {
        let applications = appIndex.apps.filter { $0.kind == .application && $0.bundleID != nil }
        let items =
            [
                PopoverMenuItem(title: "Default app", icon: .blank) { editor.openWithBundleID = nil }
            ]
            + applications.enumerated().map { index, app in
                PopoverMenuItem(title: app.name, icon: .file(path: app.url.path), startsSection: index == 0) {
                    editor.openWithBundleID = app.bundleID
                }
            }
        let selected = applications.firstIndex { $0.bundleID == editor.openWithBundleID }.map { $0 + 1 } ?? 0
        openInputMenu(PopoverMenuContent(items: items), .belowControl(applicationMenuFrame), selected)
    }

    private func focusBinding(_ field: QuicklinkEditorSession.Field) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { value in
                if value { focusedField = field } else if focusedField == field { focusedField = nil }
            })
    }

    private func option(
        _ title: String, detail: String, value: Binding<Bool>, focus: QuicklinkEditorSession.Field
    ) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(title)
                Text(detail).font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .focusable()
        .focused($focusedControl, equals: focus)
        .onKeyPress(.space) {
            value.wrappedValue.toggle()
            return .handled
        }
    }
}
