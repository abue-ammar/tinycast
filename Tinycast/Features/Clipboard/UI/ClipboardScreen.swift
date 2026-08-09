import SwiftUI

/// The clipboard browser: a filtered list beside a preview of whichever entry is selected.
struct ClipboardScreen: PaletteScreen {
    let store: ClipboardStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void
    let scrollToFollow: () -> Void

    var rows: [ClipboardItem] { store.search(vm.query) }

    var primaryActionTitle: String { vm.pasteTarget?.pasteTitle ?? "Paste" }

    private func item(at selection: Int) -> ClipboardItem? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let item = item(at: selection) else { return nil }
        return ClipboardActionsMenu.content(
            item: item, core: core, store: store, target: vm.pasteTarget)
    }

    func activate(at selection: Int) {
        guard let item = item(at: selection) else { return }
        core.clipboardCoordinator.paste(item)
    }

    /// ⌘↵ — copy without pasting, leaving the frontmost app's own clipboard use alone.
    func secondary(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        core.clipboardCoordinator.copyToClipboard(item)
        return true
    }

    /// ⌘P — mirrors the Actions menu row; pinning lifts the row into the Pinned section.
    func pin(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        core.clipboardCoordinator.togglePinnedClip(item)
        return true
    }

    /// ⌘⌫ — the screen owns the chord whether or not a row sits under the selection.
    func delete(at selection: Int) {
        guard let item = item(at: selection) else { return }
        store.remove(item)
    }

    /// Follow a row the store moved; with a query typed the highlight stays put.
    private func follow(from old: ClipFollowKey, to new: ClipFollowKey) {
        // A nil `old.id` is the first load landing, not a row that moved.
        guard old.id != nil else { return }
        let rows = rows
        if vm.query.trimmingCharacters(in: .whitespaces).isEmpty, old.id != new.id, let id = new.id,
            let index = rows.firstIndex(where: { $0.id == id })
        {
            vm.selection = index
        }
        scrollToFollow()
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            content(selection: selection, scroll: scroll)
                .onChange(of: ClipFollowKey(id: store.items.first?.id, token: vm.followToken)) {
                    old, new in
                    follow(from: old, to: new)
                }
        )
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        // Empty history: centre one message across the panel, not in the list column.
        if rows.isEmpty {
            EmptyResults(text: "Clipboard history is empty")
        } else {
            let selected = item(at: selection)
            HStack(spacing: 0) {
                ClipboardList(
                    results: rows,
                    selectedID: selected?.id,
                    scroll: scroll,
                    onSelect: { item in vm.selection = rows.firstIndex(of: item) ?? 0 },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { item in
                        if let index = rows.firstIndex(of: item) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: Theme.Size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: 1)
                ClipboardPreview(item: selected)
            }
        }
    }
}

/// Change key for the follow-the-moved-row handler, read from the store, not the results.
private struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

/// Actions menu for an entry, shown bottom-right on right-click like `AppActionsMenu`.
@MainActor
enum ClipboardActionsMenu {
    static func content(
        item: ClipboardItem, core: AppCore, store: ClipboardStore, target: PasteTarget?
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: target?.pasteTitle ?? "Paste",
                icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "↵"
            ) {
                core.clipboardCoordinator.paste(item)
            },
            PopoverMenuItem(title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                core.clipboardCoordinator.copyToClipboard(item)
            },
            PopoverMenuItem(
                title: "Paste & Keep Window Open", icon: .paste(target, fallback: "macwindow")
            ) {
                core.clipboardCoordinator.pasteKeepingWindowOpen(item)
            }
        ]
        if item.isPinned {
            items.append(
                PopoverMenuItem(title: "Unpin Entry", systemImage: "pin.slash", shortcut: "⌘P") {
                    core.clipboardCoordinator.togglePinnedClip(item)
                })
        } else {
            items.append(
                PopoverMenuItem(title: "Pin Entry", systemImage: "pin", shortcut: "⌘P") {
                    core.clipboardCoordinator.togglePinnedClip(item)
                })
        }
        if item.kind == .image {
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder") {
                    core.clipboardCoordinator.revealClipboardImage(item)
                })
        }
        items.append(
            PopoverMenuItem(title: "Delete Entry", systemImage: "trash", isDestructive: true) {
                store.remove(item)
            })
        items.append(
            PopoverMenuItem(
                title: "Delete All Entries", systemImage: "trash.fill", isDestructive: true
            ) {
                store.clearAll()
            })
        return PopoverMenuContent(header: headerText(item), items: items)
    }

    private static func headerText(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            // Collapse whitespace so a multi-line copy stays a clean one-line title.
            let oneLine = (item.text ?? "").split(whereSeparator: \.isWhitespace).joined(
                separator: " ")
            return String(oneLine.prefix(40))
        case .image: return "Image"
        }
    }
}
