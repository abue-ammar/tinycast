import SwiftUI

struct SnippetTagsField: View {
    @Bindable var editor: SnippetEditorSession
    @Binding var focused: Bool
    let catalog: [SnippetTag]
    let viewport: CGRect
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    @Environment(PaletteState.self) private var palette
    @State private var selection = 0
    @State private var fieldFrame: CGRect = .zero

    private var menuSpace: (height: CGFloat, above: Bool) {
        let gap = metrics.spacing.xs + metrics.spacing.sm
        let below = max(0, viewport.maxY - fieldFrame.maxY - gap)
        let above = max(0, fieldFrame.minY - viewport.minY - gap)
        let opensAbove = below < metrics.size.menuRowHeight + metrics.spacing.sm * 2 && above > below
        return (opensAbove ? above : below, opensAbove)
    }

    private var suggestions: [SnippetTag] { editor.tagSuggestions(in: catalog) }
    private var suggestionHeight: CGFloat {
        let suggestions = suggestions
        let hasCreation = suggestions.last.map { last in !catalog.contains { $0.id == last.id } } ?? false
        let separator =
            hasCreation && suggestions.count > 1
            ? 1 / displayScale + metrics.spacing.sm * 2 + metrics.size.menuRowSpacing : 0
        return min(
            CGFloat(suggestions.count) * metrics.size.menuRowHeight
                + CGFloat(max(0, suggestions.count - 1)) * metrics.size.menuRowSpacing
                + metrics.spacing.sm * 2 + separator, metrics.size.menuRowsMaxHeight, menuSpace.height)
    }

    var body: some View {
        let font = metrics.typography.textNSFont(.body)
        let height = metrics.size.dialogButtonHeight - metrics.spacing.sm * 2
        let inset = (height - ceil(font.ascender - font.descender + font.leading)) / 2
        return SnippetTagLayout(
            spacing: metrics.spacing.xs, lineHeight: height,
            inputMinimumWidth: metrics.spacing.xl * 2, inputInset: metrics.spacing.xxs
        ) {
            ForEach(editor.tags) { tag in
                SnippetTagChip(tag: tag) { editor.tags.removeAll { $0.id == tag.id } }
            }
            FormTextArea(
                text: $editor.tagQuery, selection: .constant(nil), focused: $focused,
                minimumHeight: height, label: "Snippet tags",
                allowsLineBreaks: false, moveFocus: editor.advanceFocus,
                insets: NSSize(width: metrics.spacing.xxs, height: inset), onCommand: command,
                scrollsHorizontally: true
            )
            .overlay(alignment: .topLeading) {
                if editor.tags.isEmpty, editor.tagQuery.isEmpty {
                    Text("Tags")
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(height: height)
                        .padding(.leading, metrics.spacing.xxs)
                        .allowsHitTesting(false)
                }
            }
            .padding(.leading, editor.tags.isEmpty ? metrics.spacing.md - metrics.spacing.xxs : 0)
            .padding(.trailing, metrics.spacing.md - metrics.spacing.xxs)
        }
        .padding(metrics.spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .formFieldChrome(focused: focused)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fieldFrame = $0 }
        .overlay(alignment: .bottomLeading) {
            if focused, !editor.tagSuggestionsDismissed, !suggestions.isEmpty {
                suggestionMenu
                    .offset(
                        y: menuSpace.above
                            ? -fieldFrame.height - metrics.spacing.xs
                            : suggestionHeight + metrics.spacing.xs)
            }
        }
        .onChange(of: editor.tagQuery) {
            selection = 0; editor.tagSuggestionsDismissed = false
        }
        .onChange(of: focused) { _, focused in
            if focused { editor.tagSuggestionsDismissed = false } else { editor.commitTag(in: catalog) }
        }
        .accessibilityHint(
            "Enter a tag, then press Return. Delete removes the last tag when the field is empty."
        )
        .zIndex(1)
    }

    private var suggestionMenu: some View {
        let suggestions = suggestions
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: metrics.size.menuRowSpacing) {
                    ForEach(suggestions.enumerated(), id: \.element.id) { index, tag in
                        let isExisting = catalog.contains { $0.id == tag.id }
                        if index > 0, !isExisting {
                            Rectangle()
                                .fill(Theme.Colors.separator)
                                .frame(height: 1 / displayScale)
                                .padding(.horizontal, metrics.spacing.md)
                                .padding(.vertical, metrics.spacing.sm)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        let item = PopoverMenuItem(
                            title: isExisting ? tag.name : "Create: \(tag.name)",
                            icon: .symbol("circle.fill"), iconTint: tag.color.tint
                        ) { choose(tag) }
                        PopoverMenuRow(item: item, selected: selection == index, onActivate: item.action)
                            .onHover { hovered in
                                if hovered, palette.hoverHighlightArmed { selection = index }
                            }
                            .id(tag.id)
                    }
                }
                .padding(metrics.spacing.sm)
            }
            .scrollClipDisabled(false)
            .scrollIndicators(.hidden)
            .frame(height: suggestionHeight)
            .onChange(of: selection) {
                if suggestions.indices.contains(selection) { proxy.scrollTo(suggestions[selection].id) }
            }
        }
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous))
    }

    private func choose(_ tag: SnippetTag) {
        editor.addTag(tag)
        selection = 0
        focused = true
    }

    private func command(_ selector: Selector) -> Bool {
        let suggestions = suggestions
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if !editor.tagSuggestionsDismissed, suggestions.indices.contains(selection) {
                choose(suggestions[selection])
            } else {
                editor.commitTag(in: catalog)
            }
            return true
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            guard !suggestions.isEmpty else { return false }
            let delta = selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            selection = (selection + delta + suggestions.count) % suggestions.count
            editor.tagSuggestionsDismissed = false
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            guard editor.tagQuery.isEmpty, !editor.tags.isEmpty else { return false }
            editor.tags.removeLast()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            return editor.dismissTagSuggestions(in: catalog)
        default: return false
        }
    }
}
