import SwiftUI

struct RaycastImportSelection: View {
    @Binding var selection: RaycastImportOptions
    @Environment(\.colorScheme) private var colorScheme

    private struct Category: Identifiable {
        let option: RaycastImportOptions
        let symbol: String
        let label: String
        var id: Int { option.rawValue }
    }

    private static let categories: [Category] = [
        .init(option: .shortcuts, symbol: "command", label: String(localized: "Shortcuts")),
        .init(option: .favorites, symbol: "star", label: String(localized: "Favorites")),
        .init(
            option: .aliases, symbol: "character.cursor.ibeam", label: String(localized: "Aliases")),
        .init(
            option: .emojiSkinTone, symbol: "face.smiling",
            label: String(localized: "Emoji skin tone")),
        .init(option: .launchAtLogin, symbol: "power", label: String(localized: "Launch at login")),
        .init(
            option: .menuBarVisibility, symbol: "menubar.rectangle",
            label: String(localized: "Menu-bar icon")),
        .init(
            option: .clipboardHistory, symbol: "doc.on.clipboard",
            label: String(localized: "Clipboard history")),
        .init(option: .snippets, symbol: "curlybraces", label: String(localized: "Snippets")),
        .init(
            option: .quicklinks, symbol: Quicklink.sfSymbol, label: String(localized: "Quicklinks")),
        .init(
            option: .popToRoot, symbol: "arrow.uturn.backward",
            label: String(localized: "Pop to root")),
        .init(option: .compactMode, symbol: "macwindow", label: String(localized: "Compact mode"))
    ]

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading), count: 2)

    private func included(_ option: RaycastImportOptions) -> Binding<Bool> {
        Binding(
            get: { selection.contains(option) },
            set: { selection = $0 ? selection.union(option) : selection.subtracting(option) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Self.categories) { category in
                    Toggle(isOn: included(category.option)) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(
                                systemName: SystemSymbolName.resolve(
                                    category.symbol, isDark: colorScheme == .dark)
                            )
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                            Text(category.label).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button(selection == .all ? "Deselect All" : "Select All") {
                selection = selection == .all ? [] : .all
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
