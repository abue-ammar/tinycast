import SwiftUI

/// The category picker shared by the Backup pane and onboarding.
struct RaycastImportSelection: View {
    @Environment(\.locale) private var localizationLocale
    @Binding var selection: RaycastImportOptions

    private struct Category: Identifiable {
        let option: RaycastImportOptions
        let symbol: String
        let label: String
        var id: Int { option.rawValue }
    }

    private static var categories: [Category] {
        [
            .init(
                option: .shortcuts, symbol: "command",
                label: String(localized: "Shortcuts", bundle: .appLanguage)),
            .init(
                option: .favorites, symbol: "star",
                label: String(localized: "Favorites", bundle: .appLanguage)),
            .init(
                option: .aliases, symbol: "character.cursor.ibeam",
                label: String(localized: "Aliases", bundle: .appLanguage)),
            .init(
                option: .emojiSkinTone, symbol: "face.smiling",
                label: String(localized: "Emoji skin tone", bundle: .appLanguage)),
            .init(
                option: .launchAtLogin, symbol: "power",
                label: String(localized: "Launch at login", bundle: .appLanguage)),
            .init(
                option: .menuBarVisibility, symbol: "menubar.rectangle",
                label: String(
                    localized: "Menu-bar icon",
                    bundle: .appLanguage)),
            .init(
                option: .clipboardHistory, symbol: "doc.on.clipboard",
                label: String(
                    localized: "Clipboard history",
                    bundle: .appLanguage)),
            .init(
                option: .snippets, symbol: "curlybraces",
                label: String(localized: "Snippets", bundle: .appLanguage)),
            .init(
                option: .quicklinks, symbol: Quicklink.sfSymbol,
                label: String(localized: "Quicklinks", bundle: .appLanguage)),
            .init(
                option: .popToRoot, symbol: "arrow.uturn.backward",
                label: String(localized: "Pop to root", bundle: .appLanguage)),
            .init(
                option: .compactMode, symbol: "macwindow",
                label: String(localized: "Compact mode", bundle: .appLanguage))
        ]
    }

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading), count: 3)

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
                            Image(systemName: category.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(category.label).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button(
                selection == .all
                    ? String(
                        localized: "Deselect All",
                        bundle: .appLanguage)
                    : String(
                        localized: "Select All",
                        bundle: .appLanguage)
            ) {
                selection = selection == .all ? [] : .all
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
