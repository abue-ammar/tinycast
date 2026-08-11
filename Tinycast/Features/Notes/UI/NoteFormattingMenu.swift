import SwiftUI

struct NoteFormattingMenu: View {
    let onSelect: (NoteMarkdownCommand) -> Void
    @FocusState private var focused: NoteMarkdownCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            row([
                Item(.normal, "Normal", "textformat"),
                Item(.heading1, "H1", nil),
                Item(.heading2, "H2", nil),
                Item(.heading3, "H3", nil)
            ])
            row([
                Item(.bold, "Bold", "bold"),
                Item(.italic, "Italic", "italic"),
                Item(.strikethrough, "Strikethrough", "strikethrough"),
                Item(.inlineCode, "Inline Code", "chevron.left.forwardslash.chevron.right"),
                Item(.link, "Link", "link")
            ])
            row([
                Item(.blockquote, "Quote", "text.quote"),
                Item(.unorderedList, "Bullets", "list.bullet"),
                Item(.orderedList, "Numbering", "list.number"),
                Item(.taskList, "Task", "checklist"),
                Item(.codeBlock, "Code Block", "curlybraces"),
                Item(.horizontalRule, "Horizontal Rule", "minus")
            ])
        }
        .padding(Theme.Spacing.md)
        .background(Color.black.opacity(0.22))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focused = .normal
            }
        }
        .onMoveCommand(perform: moveFocus)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note Formatting")
    }

    private func row(_ items: [Item]) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(items) { item in
                Button {
                    onSelect(item.command)
                } label: {
                    Group {
                        if let symbol = item.symbol {
                            Image(systemName: symbol)
                        } else {
                            Text(item.label)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(width: 27, height: 25)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                        .fill(focused == item.command ? Theme.Colors.selection : .clear)
                )
                .focused($focused, equals: item.command)
                .help(item.label)
                .accessibilityLabel(item.label)
            }
        }
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        let rows: [[NoteMarkdownCommand]] = [
            [.normal, .heading1, .heading2, .heading3],
            [.bold, .italic, .strikethrough, .inlineCode, .link],
            [.blockquote, .unorderedList, .orderedList, .taskList, .codeBlock, .horizontalRule]
        ]
        guard let focused,
            let row = rows.firstIndex(where: { $0.contains(focused) }),
            let column = rows[row].firstIndex(of: focused)
        else {
            self.focused = .normal
            return
        }
        switch direction {
        case .left:
            self.focused = rows[row][max(0, column - 1)]
        case .right:
            self.focused = rows[row][min(rows[row].count - 1, column + 1)]
        case .up:
            let target = max(0, row - 1)
            self.focused = rows[target][min(column, rows[target].count - 1)]
        case .down:
            let target = min(rows.count - 1, row + 1)
            self.focused = rows[target][min(column, rows[target].count - 1)]
        @unknown default:
            break
        }
    }
}

private struct Item: Identifiable {
    var id: NoteMarkdownCommand { command }
    let command: NoteMarkdownCommand
    let label: String
    let symbol: String?

    init(_ command: NoteMarkdownCommand, _ label: String, _ symbol: String?) {
        self.command = command
        self.label = label
        self.symbol = symbol
    }
}
