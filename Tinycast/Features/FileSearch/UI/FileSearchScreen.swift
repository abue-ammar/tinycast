import SwiftUI

struct FileSearchScreen: PaletteScreen {
    let session: FileSearchSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [FileSearchResult] { session.results }

    var primaryActionTitle: String {
        guard let result = result(at: vm.selection) else { return "Open File" }
        return result.isDirectory ? "Open Folder" : "Open File"
    }

    func result(at selection: Int) -> FileSearchResult? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let result = result(at: selection) else { return nil }
        return FileSearchActionsMenu.content(result: result, core: core, session: session)
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

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            EmptyResults(text: "Type to search files and folders")
        } else if session.state == .failed {
            EmptyResults(text: "File search is unavailable")
        } else if rows.isEmpty {
            EmptyResults(text: session.state == .ready ? "No files found" : "Searching files…")
        } else {
            let selected = result(at: selection)
            Group {
                if session.showsInfoPanel {
                    HStack(spacing: 0) {
                        FileSearchList(
                            results: rows,
                            selectedID: selected?.id,
                            showsInfoPanel: true,
                            scroll: scroll,
                            onSelect: { result in
                                if let index = rows.firstIndex(of: result) { vm.selection = index }
                            },
                            onActivate: { core.fileSearchCoordinator.open($0) },
                            onActions: { result in
                                if let index = rows.firstIndex(of: result) { vm.selection = index }
                                openActions()
                            }
                        )
                        .frame(width: metrics.size.clipboardListWidth)

                        Rectangle()
                            .fill(Theme.Colors.separator)
                            .frame(width: 1)

                        FileSearchPreview(result: selected)
                    }
                } else {
                    FileSearchList(
                        results: rows,
                        selectedID: selected?.id,
                        showsInfoPanel: false,
                        scroll: scroll,
                        onSelect: { result in
                            if let index = rows.firstIndex(of: result) { vm.selection = index }
                            session.showsInfoPanel = true
                        },
                        onActivate: { core.fileSearchCoordinator.open($0) },
                        onActions: { result in
                            if let index = rows.firstIndex(of: result) { vm.selection = index }
                            openActions()
                        }
                    )
                }
            }
            .onChange(of: selected?.id) { _, newID in
                if let newID {
                    session.lastSelectedID = newID
                }
                core.fileSearchCoordinator.updateQuickLookIfVisible(selected)
            }
            .onAppear {
                restoreSelectionIfNeeded()
            }
            .onChange(of: rows) { _, _ in
                restoreSelectionIfNeeded()
            }
        }
    }

    private func restoreSelectionIfNeeded() {
        guard let lastID = session.lastSelectedID,
            let targetIndex = rows.firstIndex(where: { $0.id == lastID }),
            vm.selection != targetIndex
        else { return }
        vm.selection = targetIndex
        vm.followToken = UUID()
    }
}

@MainActor
enum FileSearchActionsMenu {
    static func content(
        result: FileSearchResult, core: AppCore, session: FileSearchSession
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = []

        if core.settings.isFileSearchActionVisible(.open) {
            items.append(
                PopoverMenuItem(
                    title: result.isDirectory ? "Open Folder" : "Open File",
                    systemImage: result.isDirectory ? "folder" : "doc", shortcut: "↵"
                ) { core.fileSearchCoordinator.open(result) }
            )
        }
        if core.settings.isFileSearchActionVisible(.showInFinder) {
            items.append(
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵"
                ) { core.fileSearchCoordinator.showInFinder(result) }
            )
        }
        if core.settings.isFileSearchActionVisible(.quickLook) {
            items.append(
                PopoverMenuItem(
                    title: "Quick Look", systemImage: "eye", shortcut: "⌘Y"
                ) { core.fileSearchCoordinator.quickLook(result) }
            )
        }
        if core.settings.isFileSearchActionVisible(.showInfoInFinder) {
            items.append(
                PopoverMenuItem(
                    title: "Show Info in Finder", systemImage: "info.circle", shortcut: "⌥⌘I"
                ) { core.fileSearchCoordinator.showInfoInFinder(result) }
            )
        }
        if core.settings.isFileSearchActionVisible(.toggleInfoPanel) {
            items.append(
                PopoverMenuItem(
                    title: session.showsInfoPanel ? "Hide Info Panel" : "Show Info Panel",
                    systemImage: "sidebar.right", startsSection: !items.isEmpty, shortcut: "⌘I"
                ) { core.fileSearchCoordinator.toggleInfoPanel() }
            )
        }
        var startedCopySection = false
        if core.settings.isFileSearchActionVisible(.copyFile) {
            items.append(
                PopoverMenuItem(
                    title: "Copy File", systemImage: "doc.on.doc", startsSection: !items.isEmpty,
                    shortcut: "⇧⌘C"
                ) { core.fileSearchCoordinator.copyFile(result) }
            )
            startedCopySection = true
        }
        if core.settings.isFileSearchActionVisible(.copyName) {
            items.append(
                PopoverMenuItem(
                    title: "Copy Name", systemImage: "doc.text",
                    startsSection: !startedCopySection && !items.isEmpty, shortcut: "⌥⌘C"
                ) { core.fileSearchCoordinator.copyName(result) }
            )
            startedCopySection = true
        }
        if core.settings.isFileSearchActionVisible(.copyPath) {
            items.append(
                PopoverMenuItem(
                    title: "Copy Path", systemImage: "doc.on.clipboard",
                    startsSection: !startedCopySection && !items.isEmpty
                ) { core.fileSearchCoordinator.copyPath(result) }
            )
        }
        if core.settings.isFileSearchActionVisible(.saveAsQuicklink) {
            items.append(
                PopoverMenuItem(
                    title: "Save as Quicklink", systemImage: "link", startsSection: !items.isEmpty,
                    shortcut: "⌘S"
                ) { core.fileSearchCoordinator.saveAsQuicklink(result) }
            )
        }

        if items.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: result.isDirectory ? "Open Folder" : "Open File",
                    systemImage: result.isDirectory ? "folder" : "doc", shortcut: "↵"
                ) { core.fileSearchCoordinator.open(result) }
            )
        }

        return PopoverMenuContent(header: result.name, items: items)
    }
}
