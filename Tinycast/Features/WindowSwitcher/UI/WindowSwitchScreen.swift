import SwiftUI

struct WindowSwitchScreen: PaletteScreen {
    let session: WindowSwitchSession
    let core: AppCore

    var rows: [WindowSwitchEntry] { session.filtered }

    var primaryActionTitle: String { "Switch to Window" }

    private func entry(at selection: Int) -> WindowSwitchEntry? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasActions(at selection: Int) -> Bool { entry(at: selection) != nil }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        let coordinator = core.windowSwitchCoordinator
        var items = [
            PopoverMenuItem(title: "Switch to Window", systemImage: "macwindow", shortcut: "↵") {
                coordinator.activate(entry)
            }
        ]
        if !entry.isMinimized {
            items.append(
                PopoverMenuItem(title: "Minimize Window", systemImage: "minus.rectangle") {
                    coordinator.minimize(entry)
                })
        }
        items.append(
            PopoverMenuItem(title: "Hide Application", systemImage: "eye.slash", startsSection: true) {
                coordinator.hideApplication(entry)
            })
        items.append(
            PopoverMenuItem(title: "Quit Application", systemImage: "power", shortcut: "⌃⇧Q") {
                coordinator.quitApplication(entry)
            })
        return PopoverMenuContent(header: entry.displayTitle, items: items)
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        core.windowSwitchCoordinator.activate(entry)
    }

    func secondary(at selection: Int) -> Bool { false }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .quit, let entry = entry(at: selection) else { return false }
        core.windowSwitchCoordinator.quitApplication(entry)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if rows.isEmpty {
            EmptyResults(text: session.snapshot.isEmpty ? "No open windows" : "No windows found")
        } else {
            WindowSwitchList(
                entries: rows,
                selectedID: entry(at: selection)?.id,
                scroll: scroll,
                onActivate: { core.windowSwitchCoordinator.activate($0) })
        }
    }
}
