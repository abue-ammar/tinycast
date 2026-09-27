import AppKit
import SwiftUI

/// Models as checkboxes in one `Form` row, since a `Form` realizes every row and OpenCode has 400.
struct AIModelChecklist: NSViewRepresentable {
    struct Item: Equatable {
        let id: String
        let title: String
        let isOn: Bool
        /// The default model: always listed, so its box cannot be cleared.
        let isLocked: Bool
    }

    let items: [Item]
    let onToggle: (String, Bool) -> Void

    /// A grouped `Form` row's own vertical padding, which the first and last rows already carry.
    static let rowPadding: CGFloat = 9
    static let rowHeight: CGFloat = 18 + 2 * rowPadding

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let table = NSTableView()
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.refusesFirstResponder = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("model"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        context.coordinator.table = table
        return ChecklistContainer(table: table, overhang: Self.rowPadding)
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.show(self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        let rows = CGFloat(items.count) * Self.rowHeight
        return CGSize(width: proposal.width ?? nsView.frame.width, height: rows - 2 * Self.rowPadding)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        fileprivate weak var table: NSTableView?
        private var list: AIModelChecklist?
        private var shownIDs: [String] = []

        fileprivate func show(_ list: AIModelChecklist) {
            self.list = list
            guard let table else { return }
            let ids = list.items.map(\.id)
            guard ids == shownIDs else {
                shownIDs = ids
                table.reloadData()
                return
            }
            let visible = table.rows(in: table.visibleRect)
            for row in visible.location..<visible.location + visible.length {
                let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false)
                (cell as? ChecklistCellView)?.show(list.items[row], showsDivider: row > 0)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            list?.items.count ?? 0
        }

        func tableView(
            _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
        ) -> NSView? {
            guard let list else { return nil }
            let reused = tableView.makeView(withIdentifier: ChecklistCellView.reuseID, owner: nil)
            let cell = reused as? ChecklistCellView ?? ChecklistCellView()
            cell.onToggle = { [weak self] id, isOn in self?.list?.onToggle(id, isOn) }
            cell.show(list.items[row], showsDivider: row > 0)
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    }
}

/// Hangs the table into the `Form` row's padding: negative padding doesn't move an AppKit view.
private final class ChecklistContainer: NSView {
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

/// A reused row: a stock checkbox, the default's tag, and the hairline a `Form` row would draw.
private final class ChecklistCellView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("modelChecklistRow")
    var onToggle: (String, Bool) -> Void = { _, _ in }
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let defaultTag = NSTextField(labelWithString: "Default")
    private let divider = NSBox()
    private var itemID = ""

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseID
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.lineBreakMode = .byTruncatingMiddle
        defaultTag.textColor = .secondaryLabelColor
        divider.boxType = .separator
        for view in [checkbox, defaultTag, divider] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.trailingAnchor.constraint(
                lessThanOrEqualTo: defaultTag.leadingAnchor, constant: -Theme.Spacing.lg),
            defaultTag.trailingAnchor.constraint(equalTo: trailingAnchor),
            defaultTag.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor)
        ])
        defaultTag.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ item: AIModelChecklist.Item, showsDivider: Bool) {
        itemID = item.id
        checkbox.title = item.title
        checkbox.state = item.isOn || item.isLocked ? .on : .off
        checkbox.isEnabled = !item.isLocked
        defaultTag.isHidden = !item.isLocked
        divider.isHidden = !showsDivider
    }

    @objc private func toggled() {
        onToggle(itemID, checkbox.state == .on)
    }
}
