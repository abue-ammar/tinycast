import SwiftUI

struct FileSearchScreen: PaletteScreen {
    let session: FileSearchSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [FileSearchResult] { session.results }

    /// True on the blank screen, where the rows are what was opened lately rather than matches.
    private var isShowingRecents: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var primaryActionTitle: String {
        guard let result = result(at: vm.selection) else { return "Open File" }
        return result.isDirectory ? "Open Folder" : "Open File"
    }

    private func result(at selection: Int) -> FileSearchResult? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let result = result(at: selection) else { return nil }
        return FileSearchActionsMenu.content(
            result: result, core: core, vm: vm, target: vm.pasteTarget)
    }

    func activate(at selection: Int) {
        guard let result = result(at: selection) else { return }
        core.fileSearchCoordinator.open(result)
    }

    func secondary(at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        core.fileSearchCoordinator.showInFinder(result)
        return true
    }

    /// ⌘⌫ — mirrors the Actions row; trashing is undoable, so it asks nothing first.
    func trash(at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        core.fileSearchCoordinator.trash(result)
        return true
    }

    /// ⌘Y — the overlay follows the selection, so toggling is all the state it needs.
    func toggleQuickLook(at selection: Int) -> Bool {
        guard result(at: selection) != nil else { return false }
        vm.fileSearchQuickLook.toggle()
        return true
    }

    /// ⇧⌘C / ⌥⌘C / ⌃⌘C / ⇧⌘V — the pasteboard rows, each on the selection the menu would act on.
    func run(_ action: FileSearchPasteboardAction, at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        let coordinator = core.fileSearchCoordinator
        switch action {
        case .copyFile: coordinator.copyFile(result)
        case .copyName: coordinator.copyName(result)
        case .copyPath: coordinator.copyPath(result)
        case .pasteFile: coordinator.pasteFile(result)
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if session.state == .failed {
            EmptyResults(text: "File search is unavailable")
        } else if rows.isEmpty {
            emptyState
        } else {
            let selected = result(at: selection)
            HStack(spacing: 0) {
                FileSearchList(
                    title: isShowingRecents ? "Recently Used" : "Results",
                    results: rows,
                    selectedID: selected?.id,
                    scroll: scroll,
                    onSelect: { result in vm.selection = rows.firstIndex(of: result) ?? 0 },
                    onActivate: { core.fileSearchCoordinator.open($0) },
                    onActions: { result in
                        if let index = rows.firstIndex(of: result) { vm.selection = index }
                        openActions()
                    })
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: Theme.Size.hairline)
                FileSearchPreview(result: selected)
            }
            .overlay {
                if vm.fileSearchQuickLook, let selected {
                    FileSearchQuickLook(result: selected) { vm.fileSearchQuickLook = false }
                }
            }
        }
    }

    /// Nothing is said while a query runs: the rows it replaces would only flash a message.
    @ViewBuilder
    private var emptyState: some View {
        if session.state != .ready {
            Color.clear
        } else if isShowingRecents {
            EmptyResults(text: "Type to search files and folders")
        } else {
            EmptyResults(text: vm.fileSearchFilter.emptyMessage)
        }
    }
}

/// The pasteboard rows a chord can reach, so the key handler names one instead of four selectors.
enum FileSearchPasteboardAction {
    case copyFile
    case copyName
    case copyPath
    case pasteFile
}

@MainActor
enum FileSearchActionsMenu {
    static func content(
        result: FileSearchResult, core: AppCore, vm: PaletteState, target: PasteTarget?
    ) -> PopoverMenuContent {
        let coordinator = core.fileSearchCoordinator
        return PopoverMenuContent(
            header: result.name,
            items: [
                PopoverMenuItem(
                    title: result.isDirectory ? "Open Folder" : "Open File",
                    systemImage: result.isDirectory ? "folder" : "doc", shortcut: "↵"
                ) { coordinator.open(result) },
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵"
                ) { coordinator.showInFinder(result) },
                PopoverMenuItem(title: "Quick Look", systemImage: "eye", shortcut: "⌘Y") {
                    vm.fileSearchQuickLook = true
                },
                PopoverMenuItem(
                    title: "Copy File", systemImage: "doc.on.doc", startsSection: true,
                    shortcut: "⇧⌘C"
                ) { coordinator.copyFile(result) },
                PopoverMenuItem(
                    title: "Copy Name", systemImage: "textformat", shortcut: "⌥⌘C"
                ) { coordinator.copyName(result) },
                PopoverMenuItem(
                    title: "Copy Path", systemImage: "doc.on.clipboard", shortcut: "⌃⌘C"
                ) { coordinator.copyPath(result) },
                PopoverMenuItem(
                    title: target.map { "Paste File to \($0.name)" } ?? "Paste File",
                    icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "⇧⌘V"
                ) { coordinator.pasteFile(result) },
                PopoverMenuItem(
                    title: "Move to Trash", systemImage: "trash", startsSection: true,
                    shortcut: "⌘⌫", isDestructive: true
                ) { coordinator.trash(result) }
            ])
    }
}
