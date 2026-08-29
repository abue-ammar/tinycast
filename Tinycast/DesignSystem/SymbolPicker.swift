import SwiftUI

/// A grid of SF Symbols with an Automatic escape hatch; the symbols are the caller's.
struct SymbolPicker: View {
    @Binding var selection: String?
    /// Drawn on the Automatic row, and what the row falls back to when nothing is picked.
    let fallback: String
    let symbols: [String]
    let onPick: () -> Void

    private static let cell: CGFloat = 30
    private static let cellHeight: CGFloat = 26
    private static let columnCount = 6

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.cell), spacing: Theme.Spacing.sm), count: Self.columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                selection = nil
                onPick()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: fallback, size: 14)
                    Text("Automatic")
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        selection = symbol
                        onPick()
                    } label: {
                        SymbolImage(name: symbol, size: 15)
                            .frame(width: Self.cell, height: Self.cellHeight)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                                    .fill(selection == symbol ? Theme.Colors.selection : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: Self.width)
    }

    private static let width: CGFloat = 244
}
