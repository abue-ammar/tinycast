import SwiftUI

/// Search Quicklinks: the library filtered by the search field, pinned entries first.
struct QuicklinkListScreen: PaletteScreen {
    let store: QuicklinkStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [Quicklink] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.quicklinks }
        return store.quicklinks.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var primaryActionTitle: String { "Open Quicklink" }

    private func quicklink(at selection: Int) -> Quicklink? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let quicklink = quicklink(at: selection) else { return nil }
        return QuicklinkActionsMenu.content(quicklink: quicklink, core: core)
    }

    func activate(at selection: Int) {
        guard let quicklink = quicklink(at: selection) else { return }
        core.quicklinkCoordinator.openQuicklink(id: quicklink.id)
    }

    /// ⌘↵ bypasses a saved "open with" app; without one there is nothing to bypass.
    func secondary(at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection), quicklink.openWithBundleID != nil else {
            return false
        }
        core.quicklinkCoordinator.openQuicklink(id: quicklink.id, forcingDefaultApp: true)
        return true
    }

    /// ⌘. — mirrors the Actions menu row; pinning lifts the row into the Pinned section.
    func pin(at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection) else { return false }
        core.quicklinkCoordinator.toggleQuicklinkPinned(id: quicklink.id)
        return true
    }

    /// ⌘⌫ — deletion honours the "confirm before deleting" setting inside `AppCore`.
    func delete(at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection) else { return false }
        Task { await core.quicklinkCoordinator.deleteQuicklink(id: quicklink.id) }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: store.quicklinks.isEmpty ? "No quicklinks yet" : "No matching quicklinks")
        } else {
            QuicklinkList(
                results: rows,
                selectedID: rows.indices.contains(selection) ? rows[selection].id : nil,
                scroll: scroll,
                onSelect: { link in
                    if let index = rows.firstIndex(of: link) { vm.selection = index }
                },
                onActivate: { activate(at: vm.selection) },
                onActions: { link in
                    if let index = rows.firstIndex(of: link) { vm.selection = index }
                    openActions()
                }
            )
        }
    }
}

/// The ⌘K menu for a quicklink row.
@MainActor
enum QuicklinkActionsMenu {
    static func content(quicklink: Quicklink, core: AppCore) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(title: "Open Quicklink", systemImage: symbol(quicklink), shortcut: "↵") {
                core.quicklinkCoordinator.openQuicklink(id: quicklink.id)
            }
        ]
        // A flat menu has no picker, so the palette offers only the system-handler bypass.
        if quicklink.openWithBundleID != nil {
            items.append(
                PopoverMenuItem(
                    title: "Open With Default App", systemImage: "arrow.up.forward.app",
                    shortcut: "⌘↵"
                ) {
                    core.quicklinkCoordinator.openQuicklink(id: quicklink.id, forcingDefaultApp: true)
                })
        }
        items.append(
            PopoverMenuItem(title: "Edit Quicklink", systemImage: "pencil") {
                core.paletteCoordinator.hidePalette(restoreFocus: false)
                core.quicklinkCoordinator.editQuicklink(quicklink)
            })
        items.append(
            PopoverMenuItem(title: "Duplicate Quicklink", systemImage: "plus.square.on.square") {
                core.quicklinkCoordinator.duplicateQuicklink(id: quicklink.id)
            })
        items.append(
            quicklink.isPinned
                ? PopoverMenuItem(title: "Unpin Quicklink", systemImage: "pin.slash", shortcut: "⌘.") {
                    core.quicklinkCoordinator.toggleQuicklinkPinned(id: quicklink.id)
                }
                : PopoverMenuItem(title: "Pin Quicklink", systemImage: "pin", shortcut: "⌘.") {
                    core.quicklinkCoordinator.toggleQuicklinkPinned(id: quicklink.id)
                })
        items.append(
            PopoverMenuItem(
                title: quicklink.showsInRootSearch
                    ? "Hide from Root Search" : "Show in Root Search",
                systemImage: quicklink.showsInRootSearch ? "eye.slash" : "eye"
            ) {
                core.quicklinkCoordinator.setQuicklinkShowsInRootSearch(
                    !quicklink.showsInRootSearch, id: quicklink.id)
            })
        // Revealing needs a real path, which a template lacks until it expands.
        if case .path(let path)? = QuicklinkDestination.detect(quicklink.link),
            !QuicklinkDestination.containsPlaceholder(quicklink.link)
        {
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘F") {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    AppLauncher.showInFinder(URL(fileURLWithPath: path))
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Delete Quicklink", systemImage: "trash", shortcut: "⌘⌫",
                isDestructive: true
            ) {
                Task { await core.quicklinkCoordinator.deleteQuicklink(id: quicklink.id) }
            })
        return PopoverMenuContent(header: quicklink.name, items: items)
    }

    private static func symbol(_ quicklink: Quicklink) -> String {
        quicklink.iconSymbol ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol
            ?? Quicklink.sfSymbol
    }
}
