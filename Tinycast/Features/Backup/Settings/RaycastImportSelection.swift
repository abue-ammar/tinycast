import SwiftUI

struct RaycastImportSelection: View {
    @Binding var selection: RaycastImportOptions

    private struct Category: Identifiable {
        let option: RaycastImportOptions
        let symbol: String
        let tint: IconTint
        let label: String
        var id: Int { option.rawValue }
    }

    private static let categories: [Category] = [
        .init(
            option: .shortcuts, symbol: "command", tint: SettingsTab.commands.tint,
            label: String(localized: "Shortcuts")),
        .init(option: .favorites, symbol: "star.fill", tint: .gray, label: String(localized: "Favorites")),
        .init(
            option: .aliases, symbol: "character.cursor.ibeam", tint: SettingsTab.commands.tint,
            label: String(localized: "Aliases")),
        .init(
            option: .emojiSkinTone, symbol: SettingsTab.emoji.systemImage, tint: SettingsTab.emoji.tint,
            label: String(localized: "Emoji skin tone")),
        .init(
            option: .launchAtLogin, symbol: "power", tint: .gray,
            label: String(localized: "Launch at login")),
        .init(
            option: .menuBarVisibility, symbol: "menubar.rectangle", tint: .gray,
            label: String(localized: "Menu-bar icon")),
        .init(
            option: .clipboardHistory, symbol: SettingsTab.clipboard.systemImage,
            tint: SettingsTab.clipboard.tint, label: String(localized: "Clipboard history")),
        .init(
            option: .snippets, symbol: SettingsTab.snippets.systemImage, tint: SettingsTab.snippets.tint,
            label: String(localized: "Snippets")),
        .init(
            option: .quicklinks, symbol: Quicklink.sfSymbol, tint: SettingsTab.quicklinks.tint,
            label: String(localized: "Quicklinks")),
        .init(
            option: .popToRoot, symbol: "arrow.uturn.backward", tint: .gray,
            label: String(localized: "Pop to root")),
        .init(
            option: .compactMode, symbol: "macwindow", tint: .gray, label: String(localized: "Compact mode"))
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
                            SettingsSymbolTile(symbol: category.symbol, tint: category.tint)
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
