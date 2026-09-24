import AppKit
import SwiftUI

// The few pieces more than one Settings pane or editor needs; everything else stays feature-owned.

/// The Settings sidebar tile, shared with the matching feature switches.
struct SettingsTabIcon: View {
    let systemImage: String
    let tint: Color
    var size = Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2

    var body: some View {
        let scale = size / (Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2)
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .frame(
                width: Theme.Size.settingsSidebarGlyph * scale,
                height: Theme.Size.settingsSidebarGlyph * scale
            )
            .foregroundStyle(tint)
            .padding(Theme.Spacing.xs * scale)
            .background(
                tint.opacity(0.1),
                in: RoundedRectangle(
                    cornerRadius: Theme.Radius.thumbnail * scale, style: .continuous))
    }
}

struct SettingsFeatureToggleLabel: View {
    let anchor: SettingsAnchor
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            SettingsTabIcon(
                systemImage: anchor.tab.systemImage, tint: .accentColor,
                size: Theme.Size.settingsRowIcon * 1.5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                SettingsRowTitle(anchor, title)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Not `LabeledContent`: its selectable text field eats the taps a `ShortcutRecorder` needs.
struct SettingsRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var subtitleLineLimit = 1
    var alignment: VerticalAlignment = .center
    /// Set when a search result points at this row, so its title can carry the pulse.
    var anchor: SettingsAnchor?
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: alignment, spacing: Theme.Spacing.lg) {
            icon
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Group {
                    if let anchor {
                        SettingsRowTitle(anchor, title)
                    } else {
                        Text(title)
                    }
                }
                .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            Spacer(minLength: Theme.Spacing.lg)
            trailing
        }
    }
}

extension SettingsRow where Icon == EmptyView {
    init(
        title: String, subtitle: String? = nil, subtitleLineLimit: Int = 1,
        alignment: VerticalAlignment = .center, anchor: SettingsAnchor? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title, subtitle: subtitle, subtitleLineLimit: subtitleLineLimit,
            alignment: alignment,
            anchor: anchor, icon: { EmptyView() },
            trailing: trailing)
    }
}

extension View {
    /// Dims as well as disables; `.disabled` alone leaves the title at full strength.
    func settingsEnabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }

    func settingsEditorTextField() -> some View {
        modifier(SettingsEditorTextField())
    }

    func settingsEditorTextArea(height: CGFloat) -> some View {
        modifier(SettingsEditorTextArea(height: height))
    }

    func settingsEditorPanelSurface() -> some View {
        modifier(SettingsEditorPanelSurface())
    }

    /// The one place that says hiding a row from the launcher never unbinds its shortcut.
    func launcherVisibilityHelp() -> some View {
        help("Show in launcher. Its shortcut works either way.")
    }
}

struct SettingsEditorHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.panelTitle)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsEditorField<Content: View>: View {
    let title: String
    var labelFont: Font?
    @ViewBuilder var content: Content

    init(
        _ title: String, labelFont: Font? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.labelFont = labelFont
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            content
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title).font(labelFont)
        }
    }
}

private struct SettingsEditorTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Size.dialogButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}

private struct SettingsEditorTextArea: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(Theme.Spacing.sm)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}

private struct SettingsEditorPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        content
            .background(Theme.Colors.panelScrim, in: shape)
            .glassEffect(.regular, in: shape)
    }
}

/// A feature pane's opening section: the master switch, then its launcher-visibility companion.
struct FeatureSwitchSection: View {
    let anchor: SettingsAnchor
    let enableTitle: String
    var enableSubtitle: String?
    @Binding var isEnabled: Bool
    @Binding var showsInLauncher: Bool
    var showsIcon = false
    var showsHeader = true

    var body: some View {
        if showsHeader {
            section
        } else {
            section.settingsAnchor(anchor)
        }
    }

    private var section: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                if showsIcon, let enableSubtitle {
                    SettingsFeatureToggleLabel(
                        anchor: anchor, title: enableTitle, subtitle: enableSubtitle)
                } else {
                    SettingsRowTitle(anchor, enableTitle)
                    if let enableSubtitle { Text(enableSubtitle) }
                }
            }
            Toggle("Show in launcher", isOn: $showsInLauncher)
                // The switch above stays live so the feature can always be turned back on.
                .settingsEnabled(isEnabled)
        } header: {
            if showsHeader { SettingsSectionHeader(anchor) }
        }
    }
}

/// The filter row above a long list, shaped like a search field rather than a form text field.
struct SettingsFilterField: View {
    let prompt: String
    @Binding var query: String
    /// The plain field has no bezel: without this only the glyphs are a target.
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            // `prompt:` + `labelsHidden`, or the form makes the placeholder a left-column heading.
            TextField("", text: $query, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($focused)
                .pointerStyle(.horizontalText)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }
}

private struct AliasTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let onCancel: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let editor = NSTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        editor.textContainerInset = NSSize(width: 0, height: 5.5)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.maximumNumberOfLines = 1
        editor.textContainer?.lineBreakMode = .byTruncatingTail
        editor.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        editor.setAccessibilityRole(.textField)
        return editor
    }

    func updateNSView(_ editor: NSTextView, context: Context) {
        context.coordinator.field = self
        if editor.string != text { editor.string = text }
        editor.isEditable = isEnabled
        editor.isSelectable = isEnabled
        editor.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        if !focused, editor.window?.firstResponder === editor {
            editor.window?.makeFirstResponder(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var field: AliasTextField

        init(_ field: AliasTextField) {
            self.field = field
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            field.text = editor.string
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn range: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString, replacementString.contains(where: \.isNewline) else {
                return true
            }
            textView.insertText(
                String(replacementString.map { $0.isNewline ? " " : $0 }),
                replacementRange: range)
            return false
        }

        func textDidBeginEditing(_ notification: Notification) {
            field.focused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            field.focused = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                textView.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.recalculateKeyViewLoop()
                textView.window?.selectNextKeyView(textView)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.recalculateKeyViewLoop()
                textView.window?.selectPreviousKeyView(textView)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                field.onCancel()
                textView.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

/// Dressed like `ShortcutRecorder`; the persistent AppKit field preserves focus across updates.
struct AliasField: View {
    /// The owner's `preferenceKey`, taken raw so a row without an `AppEntry` can carry one too.
    let key: String
    let name: String
    @Environment(AliasStore.self) private var aliases
    @State private var draft = ""
    @State private var focused = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        HStack(spacing: Theme.Spacing.xs) {
            ZStack(alignment: .leading) {
                if draft.isEmpty {
                    Text("Add Alias")
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                AliasTextField(text: $draft, focused: $focused, onCancel: revert)
                    .focusEffectDisabled()
                    // The pane's `releasesFocusOnOutsideClick` resigns; this catches it landing.
                    .onChange(of: focused) { _, now in
                        if !now { commit() }
                    }
            }
            if !draft.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear alias for \(name)")
            }
        }
        .onAppear { draft = aliases.alias(for: key) ?? "" }
        // A backup import replaces the table out from under an unfocused row.
        .onChange(of: aliases.revision) { _, _ in
            if !focused { draft = aliases.alias(for: key) ?? "" }
        }
        // A reused table row hands the field another entry; unsaved text belongs to the old one.
        .onChange(of: key) { old, new in
            if focused {
                aliases.setAlias(draft, for: old)
                focused = false
            }
            draft = aliases.alias(for: new) ?? ""
        }
        .padding(.horizontal, Theme.Spacing.sm + 1)
        .frame(width: Theme.Size.shortcutRecorder, height: 24)
        .background(shape.fill(Theme.Colors.cardFill))
        .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
        .clipShape(shape)
        .accessibilityLabel("Alias for \(name)")
    }

    /// The one commit path — ↵ or focus landing elsewhere; a blank draft removes the alias.
    private func commit() {
        aliases.setAlias(draft, for: key)
        draft = aliases.alias(for: key) ?? ""
    }

    private func revert() {
        draft = aliases.alias(for: key) ?? ""
        focused = false
    }

    private func clear() {
        draft = ""
        commit()
    }
}

extension AliasField {
    init(entry: AppEntry) {
        self.init(key: entry.preferenceKey, name: entry.name)
    }
}
