import SwiftUI

/// Search Quicklinks: the library filtered by the search field, pinned entries first.
struct QuicklinkListScreen: PaletteScreen {
    let store: QuicklinkStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void
    /// Opens the palette's own menu for an `options=` field, keyed by argument name.
    let openArgumentOptions: (String) -> Void

    var rows: [Quicklink] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.enabled }
        return store.enabled.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var primaryActionTitle: String { String(localized: "Open Quicklink", bundle: .appLanguage) }

    private func quicklink(at selection: Int) -> Quicklink? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let quicklink = quicklink(at: selection) else { return nil }
        return QuicklinkActionsMenu.content(
            quicklink: quicklink, core: core,
            values: QuicklinkArgumentsAccessory.values(for: quicklink, core: core, vm: vm))
    }

    func activate(at selection: Int) {
        guard let quicklink = quicklink(at: selection) else { return }
        core.quicklinkCoordinator.openQuicklink(
            id: quicklink.id,
            values: QuicklinkArgumentsAccessory.values(for: quicklink, core: core, vm: vm))
    }

    /// The header's argument fields, which is where a templated link collects its values.
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        QuicklinkArgumentsAccessory.make(
            quicklink: quicklink(at: selection), core: core, vm: vm, focus: focus,
            placement: .besideSearchField, onOpenOptions: openArgumentOptions,
            onSubmit: { activate(at: selection) })
    }

    /// ⌘↵ bypasses a saved "open with" app; without one there is nothing to bypass.
    func secondary(at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection), quicklink.openWithBundleID != nil else {
            return false
        }
        core.quicklinkCoordinator.openQuicklink(
            id: quicklink.id, forcingDefaultApp: true,
            values: QuicklinkArgumentsAccessory.values(for: quicklink, core: core, vm: vm))
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
                text: store.enabled.isEmpty
                    ? String(
                        localized: "No quicklinks yet",
                        bundle: .appLanguage) : String(
                        localized: "No matching quicklinks",
                        bundle: .appLanguage))
        } else {
            let selected = quicklink(at: selection)
            HStack(spacing: 0) {
                QuicklinkList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { link in
                        if let index = rows.firstIndex(of: link) { vm.selection = index }
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { link in
                        if let index = rows.firstIndex(of: link) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: Theme.Size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                QuicklinkPreview(quicklink: selected)
            }
        }
    }
}

/// The ⌘K menu for a quicklink row.
@MainActor
enum QuicklinkActionsMenu {
    /// `values` are the header's argument fields, so a menu row opens with what ↵ would have used.
    static func content(
        quicklink: Quicklink, core: AppCore, values: [String: String]
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(title: String(
                localized: "Open Quicklink",
                bundle: .appLanguage), systemImage: quicklink.symbol, shortcut: "↵") {
                core.quicklinkCoordinator.openQuicklink(id: quicklink.id, values: values)
            }
        ]
        // A flat menu has no picker, so the palette offers only the system-handler bypass.
        if quicklink.openWithBundleID != nil {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Open With Default App", bundle: .appLanguage), systemImage: "arrow.up.forward.app",
                    shortcut: "⌘↵"
                ) {
                    core.quicklinkCoordinator.openQuicklink(
                        id: quicklink.id, forcingDefaultApp: true, values: values)
                })
        }
        items.append(
            PopoverMenuItem(title: String(localized: "Edit Quicklink", bundle: .appLanguage), systemImage: "pencil") {
                core.paletteCoordinator.hidePalette(restoreFocus: false)
                core.quicklinkCoordinator.editQuicklink(quicklink)
            })
        items.append(
            PopoverMenuItem(title: String(
                localized: "Duplicate Quicklink",
                bundle: .appLanguage), systemImage: "plus.square.on.square") {
                core.quicklinkCoordinator.duplicateQuicklink(id: quicklink.id)
            })
        items.append(
            quicklink.isPinned
                ? PopoverMenuItem(title: String(
                    localized: "Unpin Quicklink",
                    bundle: .appLanguage), systemImage: "pin.slash", shortcut: "⌘.") {
                    core.quicklinkCoordinator.toggleQuicklinkPinned(id: quicklink.id)
                }
                : PopoverMenuItem(title: String(
                    localized: "Pin Quicklink",
                    bundle: .appLanguage), systemImage: "pin", shortcut: "⌘.") {
                    core.quicklinkCoordinator.toggleQuicklinkPinned(id: quicklink.id)
                })
        items.append(
            PopoverMenuItem(
                title: quicklink.showsInRootSearch
                    ? String(
                        localized: "Hide from Root Search",
                        bundle: .appLanguage) : String(
                        localized: "Show in Root Search",
                        bundle: .appLanguage),
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
                PopoverMenuItem(title: String(
                    localized: "Show in Finder",
                    bundle: .appLanguage), systemImage: "folder", shortcut: "⌘F") {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    AppLauncher.showInFinder(URL(fileURLWithPath: path))
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Delete Quicklink", bundle: .appLanguage), systemImage: "trash", shortcut: "⌘⌫",
                isDestructive: true
            ) {
                Task { await core.quicklinkCoordinator.deleteQuicklink(id: quicklink.id) }
            })
        return PopoverMenuContent(header: quicklink.name, items: items)
    }
}
