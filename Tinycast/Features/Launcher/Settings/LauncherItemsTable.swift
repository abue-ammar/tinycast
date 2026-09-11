import AppKit
import SwiftUI

/// Launcher items as a table in one `Form` row, reusing a screenful of hosted rows as it scrolls.
struct LauncherItemsTable: NSViewRepresentable {
    let entries: [AppEntry]
    let isEnabled: Bool
    let visibility: VisibilityStore
    let aliases: AliasStore
    let hotKeys: HotKeyManager
    /// The open recorder's bounds in this view's space; nil while nothing is recording.
    @Binding var recorderFrame: CGRect?

    /// A grouped `Form` row's own vertical padding, which the first and last rows already carry.
    static let rowPadding: CGFloat = 15
    /// A trailing control's 24 pt plus that padding above and below it.
    static let rowHeight: CGFloat = 24 + 2 * rowPadding

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let table = HostedRowsTableView()
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.refusesFirstResponder = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        context.coordinator.table = table
        let container = OverhangingTableView(table: table, overhang: Self.rowPadding)
        context.coordinator.container = container
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.show(self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        let rows = CGFloat(entries.count) * Self.rowHeight
        return CGSize(width: proposal.width ?? nsView.frame.width, height: rows - 2 * Self.rowPadding)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        fileprivate weak var table: NSTableView?
        fileprivate weak var container: NSView?
        private var list: LauncherItemsTable?
        private var shownIDs: [AppEntry.ID] = []
        private weak var recorderOwner: LauncherItemCellView?

        fileprivate func show(_ list: LauncherItemsTable) {
            self.list = list
            guard let table else { return }
            let ids = list.entries.map(\.id)
            guard ids == shownIDs else {
                shownIDs = ids
                table.reloadData()
                return
            }
            // Same rows: refresh the visible cells in place, so a focused alias keeps its editor.
            let visible = table.rows(in: table.visibleRect)
            for row in visible.location..<visible.location + visible.length {
                let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false)
                (cell as? LauncherItemCellView)?.show(content(for: row, of: list))
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            list?.entries.count ?? 0
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let list else { return nil }
            let content = content(for: row, of: list)
            let reused = tableView.makeView(withIdentifier: LauncherItemCellView.reuseID, owner: nil)
            let cell = reused as? LauncherItemCellView ?? LauncherItemCellView(content)
            cell.coordinator = self
            cell.show(content)
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        fileprivate func focusAlias(below cell: LauncherItemCellView) -> Bool {
            guard let table else { return false }
            let row = table.row(for: cell) + 1
            guard row > 0, row < table.numberOfRows else { return false }
            table.scrollRowToVisible(row)
            let next = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? LauncherItemCellView
            return next?.focusAlias() ?? false
        }

        fileprivate func recorderMoved(to frame: CGRect?, in cell: LauncherItemCellView) {
            if let frame {
                recorderOwner = cell
                publish(frame)
            } else if recorderOwner === cell {
                recorderOwner = nil
                publish(nil)
            }
        }

        private func publish(_ frame: CGRect?) {
            guard let list, list.recorderFrame != frame else { return }
            list.recorderFrame = frame
        }

        private func content(for row: Int, of list: LauncherItemsTable) -> LauncherItemCell {
            LauncherItemCell(
                entry: list.entries[row], showsDivider: row > 0, isEnabled: list.isEnabled,
                visibility: list.visibility, aliases: list.aliases, hotKeys: list.hotKeys)
        }
    }
}

/// Hangs the table into the `Form` row's padding: negative padding doesn't move an AppKit view.
private final class OverhangingTableView: NSView {
    private let table: NSTableView
    private let overhang: CGFloat

    init(table: NSTableView, overhang: CGFloat) {
        self.table = table
        self.overhang = overhang
        super.init(frame: .zero)
        addSubview(table)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        table.frame = bounds.insetBy(dx: 0, dy: -overhang)
    }
}

/// Hands every click to the hosted row; a table otherwise claims clicks that miss an `NSControl`.
private final class HostedRowsTableView: NSTableView {
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        true
    }
}

/// A reused row: its hosted text field and checkbox survive, and only the entry changes hands.
private final class LauncherItemCellView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("launcherItem")
    weak var coordinator: LauncherItemsTable.Coordinator?
    private let host: NSHostingView<LauncherItemCell>

    init(_ content: LauncherItemCell) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        identifier = Self.reuseID
        // The table fixes the row height; a hosting view left to size itself would fight it.
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ content: LauncherItemCell) {
        var content = content
        content.onRecorderFrame = { [weak self] frame in self?.recorderMoved(to: frame) }
        content.onTab = { [weak self] in self?.tabbed() ?? false }
        host.rootView = content
    }

    fileprivate func focusAlias() -> Bool {
        guard let field = aliasField else { return false }
        return window?.makeFirstResponder(field) ?? false
    }

    /// Only while the alias is being edited, so Tab off a focused checkbox keeps its default.
    private func tabbed() -> Bool {
        guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor,
            let field = editor.delegate as? NSView, field.isDescendant(of: host), let coordinator
        else { return false }
        return coordinator.focusAlias(below: self)
    }

    /// The row's one editable text field is its alias; the name and the recorder are drawn text.
    private var aliasField: NSTextField? {
        var pending: [NSView] = [host]
        while let view = pending.popLast() {
            if let field = view as? NSTextField, field.isEditable { return field }
            pending.append(contentsOf: view.subviews)
        }
        return nil
    }

    private func recorderMoved(to frame: CGRect?) {
        guard let coordinator, let container = coordinator.container else { return }
        coordinator.recorderMoved(to: frame.map { host.convert($0, to: container) }, in: self)
    }
}

/// What a cell hosts: the row, plus the hairline and environment a `Form` row would hand it.
private struct LauncherItemCell: View {
    let entry: AppEntry
    let showsDivider: Bool
    let isEnabled: Bool
    let visibility: VisibilityStore
    let aliases: AliasStore
    let hotKeys: HotKeyManager
    var onRecorderFrame: @MainActor (CGRect?) -> Void = { _ in }
    var onTab: @MainActor () -> Bool = { false }

    var body: some View {
        LauncherItemRow(entry: entry)
            // Rows are separate hosting views; the key view loop doesn't run from one to the next.
            .onKeyPress(.tab, phases: .down) { press in
                !press.modifiers.contains(.shift) && onTab() ? .handled : .ignored
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if showsDivider { Divider() }
            }
            .disabled(!isEnabled)
            // The recorder's anchor can't leave this hosting view; its bounds go out by hand.
            .overlayPreferenceValue(ShortcutRecorderAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    Color.clear.onChange(of: anchor.map { proxy[$0] }, initial: true) { _, frame in
                        onRecorderFrame(frame)
                    }
                }
            }
            .environment(visibility)
            .environment(aliases)
            .environment(hotKeys)
    }
}
