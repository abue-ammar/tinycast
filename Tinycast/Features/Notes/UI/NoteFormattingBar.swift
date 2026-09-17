import SwiftUI

/// The title bar capsule's recipe along the bottom, one button per Markdown edit.
struct NoteFormattingBar: View {
    @Environment(NotesCoordinator.self) private var notes

    private struct Control: Sendable {
        let symbol: String
        let title: String
        let shortcut: String
        let action: NoteEditAction
        let isLit: @Sendable (NoteFormatting) -> Bool
    }

    private static let styles = [
        Control(symbol: "bold", title: "Bold", shortcut: "⌘B", action: .toggleInline(.bold)) {
            $0.inlineStyles.contains(.bold)
        },
        Control(symbol: "italic", title: "Italic", shortcut: "⌘I", action: .toggleInline(.italic)) {
            $0.inlineStyles.contains(.italic)
        },
        Control(
            symbol: "strikethrough", title: "Strikethrough", shortcut: "⇧⌘X",
            action: .toggleInline(.strikethrough)
        ) { $0.inlineStyles.contains(.strikethrough) },
        Control(
            symbol: "chevron.left.forwardslash.chevron.right", title: "Inline Code", shortcut: "⌘E",
            action: .toggleInline(.code)
        ) { $0.inlineStyles.contains(.code) },
        Control(symbol: "link", title: "Link", shortcut: "⌘K", action: .toggleLink) { $0.isLink }
    ]

    private static let blocks = [
        Control(symbol: "curlybraces", title: "Code Block", shortcut: "⌥⌘C", action: .toggleCodeBlock) {
            $0.isCodeBlock
        },
        Control(symbol: "text.quote", title: "Quote", shortcut: "⇧⌘B", action: .toggleQuote) { $0.isQuote }
    ]

    private static let lists = [
        Control(symbol: "list.number", title: "Numbered List", shortcut: "⇧⌘7", action: .toggleList(.ordered)) {
            $0.list == .ordered
        },
        Control(symbol: "list.bullet", title: "Bullet List", shortcut: "⇧⌘8", action: .toggleList(.bullet)) {
            $0.list == .bullet
        },
        Control(symbol: "checklist", title: "Task List", shortcut: "⇧⌘9", action: .toggleList(.task)) {
            $0.list == .task
        }
    ]

    var body: some View {
        let formatting = notes.formatting
        let isExpanded = notes.isFormattingBarExpanded
        HStack(spacing: Theme.Spacing.sm) {
            NoteFormattingToggle(isExpanded: isExpanded, action: notes.toggleFormattingBar)
                // Drawn above the buttons, so they grow out from behind it.
                .zIndex(1)
            if isExpanded {
                HStack(spacing: Theme.Spacing.sm) {
                    NoteHeadingButton(
                        level: formatting.headingLevel, isOpen: notes.isHeadingMenuPresented,
                        action: notes.toggleHeadingMenu)
                    group(Self.styles, formatting)
                    group(Self.blocks, formatting)
                    group(Self.lists, formatting, lastIsTrailing: true)
                }
                // Grows out of the round button; nothing leaves the capsule, so no clip is needed.
                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
            }
        }
        .padding(Theme.Spacing.xs)
        // Behind the buttons, not around them: glass clips content, tooltips draw outside it.
        .background { Capsule().fill(Color.clear).frosted(in: Capsule()) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private func group(
        _ controls: [Control], _ formatting: NoteFormatting, lastIsTrailing: Bool = false
    ) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(controls, id: \.title) { control in
                let lit = control.isLit(formatting)
                let isLast = lastIsTrailing && control.title == controls.last?.title
                BarButton(isSelected: lit, isCompact: true, action: { notes.format(control.action) }) {
                    NoteBarGlyph(name: control.symbol)
                }
                .focusable(false)
                .accessibilityLabel(control.title)
                .accessibilityAddTraits(lit ? .isSelected : [])
                .tooltip("\(control.title)  \(control.shortcut)", alignment: isLast ? .trailing : .center)
            }
        }
    }
}

/// The bar's handle: one round button that shows and hides every other control.
private struct NoteFormattingToggle: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        BarButton(isSelected: isExpanded, isCompact: true, action: action) {
            NoteBarGlyph(name: "paintbrush")
        }
        .focusable(false)
        .accessibilityLabel("Formatting")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        // Against the window's leading edge, so a centred label would run off it.
        .tooltip("Formatting  ⌥⌘T", alignment: .leading)
    }
}

/// Symbols differ in width, so a fixed frame keeps every button the same square.
private struct NoteBarGlyph: View {
    let name: String

    var body: some View {
        SymbolImage(name: name, size: Theme.Size.noteGlyph)
            .frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
    }
}

private struct NoteHeadingButton: View {
    let level: Int?
    let isOpen: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHeading: Bool { (1...6).contains(level ?? 0) }

    var body: some View {
        BarButton(isSelected: isHeading || isOpen, isCompact: true, action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                NoteBarGlyph(name: "textformat.size")
                // Rotates rather than swaps, so opening the menu cannot shift the bar.
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
        }
        .focusable(false)
        .accessibilityLabel("Heading")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isHeading ? .isSelected : [])
        .tooltip(isOpen ? nil : "Heading")
    }

    private var accessibilityValue: String {
        switch level {
        case .some(0): "Text"
        case .some(let level) where level > 0: "Heading \(level)"
        default: ""
        }
    }
}
