import SwiftUI

/// The running view command's screen: its rows, what ↵ and ⌘K send, and the tree it last rendered.
struct ExtensionScreen: PaletteScreen {
    let coordinator: ExtensionCoordinator
    let query: String
    /// The palette's raw selection, clamped as the palette clamps it, for the one title it can't pass.
    let selection: Int

    private var session: ExtensionSession? { coordinator.shown?.session }

    var rows: [ExtensionUI.Row] { session?.ui?.rows ?? [] }

    var primaryActionTitle: String {
        guard !rows.isEmpty else { return "" }
        return rows[min(max(selection, 0), rows.count - 1)].actions.first?.title ?? ""
    }

    private func row(at selection: Int) -> ExtensionUI.Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasPrimaryAction(at selection: Int) -> Bool { row(at: selection)?.actions.isEmpty == false }

    func hasActions(at selection: Int) -> Bool { hasPrimaryAction(at: selection) }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let row = row(at: selection), !row.actions.isEmpty else { return nil }
        return PopoverMenuContent(
            items: row.actions.enumerated().map { index, action in
                PopoverMenuItem(
                    title: action.title, icon: Self.icon(for: action.image),
                    shortcut: index == 0 ? "↵" : nil
                ) {
                    coordinator.perform(action.id)
                }
            })
    }

    func activate(at selection: Int) {
        guard let action = row(at: selection)?.actions.first else { return }
        coordinator.perform(action.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ExtensionScreenView(
                coordinator: coordinator, session: session, query: query, selectedRow: row(at: selection)?.id)
        )
    }

    /// An asset path lives in the bundle, which a menu row can't resolve, so it draws no glyph.
    private static func icon(for image: ExtensionUI.Image?) -> PopoverMenuIcon {
        guard case .symbol(let name)? = image else { return .blank }
        return .symbol(name)
    }
}
