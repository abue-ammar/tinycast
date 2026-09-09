import SwiftUI

/// The leftover files found for one app, each selectable for the Trash.
struct UninstallScreen: PaletteScreen {
    let session: UninstallSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// The search field filters files by name or location on this screen.
    var rows: [UninstallCandidate] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return session.candidates }
        return session.candidates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.locationLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var primaryActionTitle: String { String(localized: "Uninstall Application", bundle: .appLanguage) }

    /// Stands in for the section headers the other lists use.
    private var summary: String {
        let total = session.plan?.removableIDs.count ?? 0
        let size = MeasuredSize(bytes: session.selectedBytes).formatted
        return String(localized: "\(session.selectedCount) of \(total) files selected · \(size)", bundle: .appLanguage)
    }

    private func candidate(at selection: Int) -> UninstallCandidate? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let candidate = candidate(at: selection) else { return nil }
        return UninstallActionsMenu.content(candidate: candidate, session: session, core: core)
    }

    /// The primary action trashes the session's checked set, not the highlighted row.
    func activate(at selection: Int) {
        core.uninstallCoordinator.performUninstall()
    }

    func secondary(at selection: Int) -> Bool {
        guard let candidate = candidate(at: selection), !candidate.isLocked else { return false }
        session.toggle(candidate.id)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        switch session.state {
        case .idle, .scanning:
            // Blank, not copy: discovery is milliseconds, so anything here would only flash.
            Color.clear
        case .failed(let message):
            EmptyResults(text: message)
        case .ready:
            let rows = rows
            if rows.isEmpty {
                EmptyResults(
                    text: vm.query.trimmingCharacters(in: .whitespaces).isEmpty
                        ? String(
                            localized: "Nothing left to remove",
                            bundle: .appLanguage) : String(
                            localized: "No matching files",
                            bundle: .appLanguage))
            } else {
                UninstallList(
                    results: rows,
                    selectedID: rows.indices.contains(selection) ? rows[selection].id : nil,
                    summary: summary,
                    scroll: scroll,
                    onSelect: { candidate in
                        if let index = rows.firstIndex(of: candidate) { vm.selection = index }
                    },
                    onToggle: { session.toggle($0.id) },
                    onActions: { candidate in
                        if let index = rows.firstIndex(of: candidate) { vm.selection = index }
                        openActions()
                    }
                )
            }
        }
    }
}

/// Actions menu for a row on the Uninstall screen.
@MainActor
enum UninstallActionsMenu {
    static func content(
        candidate: UninstallCandidate, session: UninstallSession, core: AppCore
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = []
        if session.canConfirm {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Uninstall Application", bundle: .appLanguage), systemImage: "trash", shortcut: "↵",
                    isDestructive: true
                ) { core.uninstallCoordinator.performUninstall() })
        }
        if !candidate.isLocked {
            let checked = session.selection?.isChecked(candidate.id) ?? false
            items.append(
                PopoverMenuItem(
                    title: checked ? String(
                        localized: "Unselect File",
                        bundle: .appLanguage) : String(
                        localized: "Select File",
                        bundle: .appLanguage),
                    systemImage: checked ? "circle" : "checkmark.circle", shortcut: "⌘↵"
                ) { session.toggle(candidate.id) })
        }
        items.append(
            PopoverMenuItem(title: String(
                localized: "Copy Path",
                bundle: .appLanguage), systemImage: "doc.on.clipboard", shortcut: "⌥⌘C") {
                core.uninstallCoordinator.copyUninstallPath(candidate)
            })
        items.append(
            PopoverMenuItem(title: String(
                localized: "Show in Finder",
                bundle: .appLanguage), systemImage: "folder", shortcut: "⇧⌘O") {
                core.uninstallCoordinator.showUninstallItemInFinder(candidate)
            })
        items.append(
            PopoverMenuItem(title: String(
                localized: "Show Info in Finder",
                bundle: .appLanguage), systemImage: "info.circle", shortcut: "⇧⌘I") {
                core.uninstallCoordinator.showUninstallItemInfo(candidate)
            })
        return PopoverMenuContent(header: session.app?.name ?? candidate.name, items: items)
    }
}
