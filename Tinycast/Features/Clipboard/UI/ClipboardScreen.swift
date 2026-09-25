import SwiftUI

/// The clipboard browser: a filtered list beside a preview of whichever entry is selected.
struct ClipboardScreen: PaletteScreen {
    let store: ClipboardStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void
    let scrollToFollow: () -> Void

    var rows: [ClipboardItem] { store.search(vm.query, filter: vm.clipboardFilter) }

    var landingSelection: Int { store.landingIndex(in: vm.query, filter: vm.clipboardFilter) }

    var primaryActionTitle: String {
        let defaultAction = core.settings.clipboardDefaultAction
        let action = item(at: vm.selection).flatMap { defaultAction.action(for: .return, on: $0) }
        return (action ?? defaultAction).title(pastingInto: vm.pasteTarget)
    }

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
        core.clipboardCoordinator.activate(item)
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            delete(at: selection)
            return true
        case .deleteAll:
            deleteAll()
            return true
        case .pin: return pin(at: selection)
        case .favoriteSlot(let index): return activatePinned(at: index)
        case .copyText:
            guard let item = item(at: selection), item.offersTextExtraction else { return false }
            core.clipboardCoordinator.copyImageText(item)
            return true
        default: return false
        }
    }

    /// ⌘1…⌘0 — the Nth visible pinned entry (Pinned section order), like ↵.
    private func activatePinned(at index: Int) -> Bool {
        guard let item = store.pinnedItem(at: index, in: vm.query, filter: vm.clipboardFilter) else {
            return false
        }
        core.clipboardCoordinator.activate(item)
        return true
    }

    /// ⌘↵ — the action ↵ is not set to.
    func secondary(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        return core.clipboardCoordinator.activate(item, chord: .command)
    }

    /// ⌃⌘↵ — Paste as Plain Text, or Paste while that is the default.
    func tertiary(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        return core.clipboardCoordinator.activate(item, chord: .controlCommand)
    }

    /// ⌥↵ — the palette stays up, so a run of entries goes over without re-summoning it.
    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        core.clipboardCoordinator.pasteKeepingWindowOpen(item)
        return true
    }

    /// ⌘. — mirrors the Actions menu row; pinning lifts the row into the Pinned section.
    private func pin(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        core.clipboardCoordinator.togglePinnedClip(item)
        return true
    }

    /// ⌘⌫ / ⌃X — the screen owns the chord whether or not a row sits under the selection.
    private func delete(at selection: Int) {
        guard let item = item(at: selection) else { return }
        store.remove(item)
    }

    /// ⌃⇧X — mirrors the Actions row, confirmation included; pinned entries go with the rest.
    private func deleteAll() {
        Task { await core.clipboardCoordinator.deleteAllClips() }
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
            // Names the filter, so one hiding every entry doesn't read as an empty history.
            EmptyResults(text: vm.clipboardFilter.emptyMessage)
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
                    },
                    onDragPayload: { core.clipboardCoordinator.dragPayload(for: $0) },
                    onDropped: { core.paletteCoordinator.dragLanded() }
                )
                .frame(width: metrics.size.clipboardListWidth)
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
        let defaultAction = core.settings.clipboardDefaultAction
        // Chord order puts the default first, beside the ↵ it answers.
        var items: [PopoverMenuItem] = ClipboardChord.allCases.compactMap { chord in
            defaultAction.action(for: chord, on: item).map { action in
                PopoverMenuItem(
                    title: action.title(pastingInto: target), icon: icon(for: action, target: target),
                    shortcut: chord.label
                ) {
                    core.clipboardCoordinator.perform(action, on: item)
                }
            }
        }
        items.append(
            PopoverMenuItem(
                title: "Paste and Keep Window Open", icon: .paste(target, fallback: "macwindow"),
                shortcut: "⌥↵"
            ) {
                core.clipboardCoordinator.pasteKeepingWindowOpen(item)
            })
        if item.isPinned {
            items.append(
                PopoverMenuItem(
                    title: "Unpin Entry", systemImage: "pin.slash", startsSection: true, shortcut: "⌘."
                ) {
                    core.clipboardCoordinator.togglePinnedClip(item)
                })
        } else {
            items.append(
                PopoverMenuItem(
                    title: "Pin Entry", systemImage: "pin", startsSection: true, shortcut: "⌘."
                ) {
                    core.clipboardCoordinator.togglePinnedClip(item)
                })
        }
        if item.offersTextExtraction {
            items.append(
                PopoverMenuItem(
                    title: "Copy Text", systemImage: "doc.text.viewfinder",
                    startsSection: true, shortcut: "⇧⌘T"
                ) {
                    core.clipboardCoordinator.copyImageText(item)
                })
        }
        if item.kind == .image || item.kind == .file {
            items.append(
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder",
                    startsSection: !item.offersTextExtraction
                ) {
                    core.clipboardCoordinator.revealClip(item)
                })
        }
        if item.kind == .file {
            items.append(
                PopoverMenuItem(title: "Open", systemImage: "arrow.up.forward.app") {
                    core.clipboardCoordinator.openClip(item)
                })
            items.append(
                PopoverMenuItem(title: "Copy Path", systemImage: "doc.on.clipboard") {
                    core.clipboardCoordinator.copyClipPath(item)
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Delete Entry", systemImage: "trash", startsSection: true, shortcut: "⌃X",
                isDestructive: true
            ) {
                store.remove(item)
            })
        items.append(
            PopoverMenuItem(
                title: "Delete All Entries", systemImage: "trash", shortcut: "⌃⇧X",
                isDestructive: true
            ) {
                Task { await core.clipboardCoordinator.deleteAllClips() }
            })
        return PopoverMenuContent(header: headerText(item), items: items)
    }

    private static func icon(
        for action: ClipboardDefaultAction, target: PasteTarget?
    ) -> PopoverMenuIcon {
        switch action {
        case .paste: .paste(target, fallback: "doc.on.clipboard")
        case .copy: .symbol("doc.on.doc")
        case .pastePlainText: .paste(target, fallback: "doc.plaintext")
        }
    }

    private static func headerText(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            // Collapse whitespace so a multi-line copy stays a clean one-line title.
            let oneLine = (item.text ?? "").split(whereSeparator: \.isWhitespace).joined(
                separator: " ")
            return String(oneLine.prefix(40))
        case .image: return "Image"
        case .file: return (item.filePath as NSString?)?.lastPathComponent ?? "File"
        }
    }
}

extension ClipboardDefaultAction {
    /// A paste names the app it lands in, in the footer pill and the ⌘K menu alike.
    func title(pastingInto target: PasteTarget?) -> String {
        guard let target, self != .copy else { return title }
        return "\(title) to \(target.name)"
    }
}
