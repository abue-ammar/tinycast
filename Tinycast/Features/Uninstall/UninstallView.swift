import SwiftUI

/// The uninstall screen's list: every path an uninstall would remove, each row a checkbox. Flat and
/// unsectioned (the header's sort control owns the order), so row order is exactly `items` and the
/// palette's flat selection index maps 1:1 onto it.
struct UninstallList: View {
    let items: [LeftoverItem]
    let selection: Int
    let isChecked: (LeftoverItem) -> Bool
    let appIcon: NSImage?
    /// Count line rendered as this list's section header, so it sits exactly where every other palette
    /// list's first header sits — same component, same rhythm, no per-screen layout shift.
    let header: String
    /// Changes only when the list should scroll (keyboard nav / reset), so mouse selection never yanks
    /// the scroll position.
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onToggle: (Int) -> Void
    let onActions: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: header, isFirst: true)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        UninstallRow(
                            item: item,
                            checked: isChecked(item),
                            selected: index == selection,
                            icon: item.kind == .bundle ? appIcon : nil
                        )
                        .contentShape(Rectangle())
                        // A click checks or unchecks, like any checkbox list — the destructive action
                        // stays with ↵ and the footer button.
                        .onTapGesture {
                            onSelect(index)
                            onToggle(index)
                        }
                        .onRightClick { onActions(index) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top:
                    proxy.scrollToOrigin()
                case .follow:
                    // The first row snaps to the origin so the count header comes back into view; a nil
                    // anchor wouldn't move, the row being visible already.
                    if selection == 0 {
                        proxy.scrollToOrigin()
                    } else if items.indices.contains(selection) {
                        proxy.reveal(items[selection].id)
                    }
                }
            }
        }
    }
}

/// The uninstall list's header text: how many rows are checked out of the removable ones, and what
/// they add up to. Rendered through the shared `SectionHeader`, so it reads as a category label.
@MainActor
enum UninstallHeader {
    static func title(checked: Int, removable: Int, size: Int64) -> String {
        let files = removable == 1 ? "file" : "files"
        let count = "\(checked) of \(removable) \(files) selected"
        return size > 0 ? count + "  ·  " + UninstallFormat.size(size) : count
    }
}

/// The in-progress screen. Quitting the app and walking a multi-gigabyte bundle takes a moment, and
/// that moment is exactly when the palette used to disappear without a word.
struct UninstallProgressView: View {
    let name: String
    let permanently: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ProgressView()
                .controlSize(.large)
            Text(permanently ? "Deleting \(name)…" : "Moving \(name) to the Trash…")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The result screen: what went, how much came back, and anything that didn't go.
struct UninstallSummaryView: View {
    let name: String
    let outcome: UninstallOutcome

    private var title: String {
        guard outcome.removedCount > 0 else { return "Nothing was removed" }
        let items = "\(outcome.removedCount) \(outcome.removedCount == 1 ? "item" : "items")"
        return outcome.permanently
            ? "Deleted \(items)" : "Moved \(items) to the Trash"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(
                systemName: outcome.failures.isEmpty
                    ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.largeTitle)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(outcome.failures.isEmpty ? Color.primary : Color.red)
            VStack(spacing: Theme.Spacing.xs) {
                Text("\(name) — \(title)")
                    .font(Theme.Typography.rowTitle)
                if outcome.reclaimed > 0 {
                    Text("\(UninstallFormat.size(outcome.reclaimed)) reclaimed")
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
                // Trashing is reversible and worth saying so; unlinking isn't, and pretending otherwise
                // would be the one misleading line on this screen.
                if outcome.removedCount > 0, !outcome.permanently {
                    Text("Recoverable from the Trash")
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            if !outcome.failures.isEmpty { failureList }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What stayed behind, and the two reasons it does: no permission, or the file is still in use.
    private var failureList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(
                outcome.failures.count == 1
                    ? "1 item couldn’t be removed — it may need an administrator, or still be in use."
                    : "\(outcome.failures.count) items couldn’t be removed — they may need an administrator, or still be in use."
            )
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(outcome.failures) { failure in
                Text(failure.displayPath)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

/// The header's sort control: current order plus a disclosure chevron, opening the sort menu.
struct UninstallSortButton: View {
    let sort: UninstallSort
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: sort.systemImage)
                    .symbolRenderingMode(.hierarchical)
                Text(sort.title)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.keyCap)
            }
            .font(Theme.Typography.bar)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Size.headerControl)
            .contentShape(Capsule())
            .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .fixedSize()
    }
}

/// One uninstall row: checkbox, file name, its directory, size, then the file's own icon — or a padlock
/// when the path is locked.
private struct UninstallRow: View {
    let item: LeftoverItem
    let checked: Bool
    let selected: Bool
    /// The app's own icon for the bundle row; every other row draws a symbol for its kind.
    let icon: NSImage?
    @State private var hovered = false

    /// Copy-identical to every other palette row (see docs/ui.md): selection beats hover.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// Directory the item sits in, tilde-abbreviated — the row's name column already carries the leaf.
    private var directory: String {
        (item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    /// The trailing glyph. A locked row says so with a padlock; otherwise it's what the path *is*, read
    /// from the row rather than the filesystem — this is evaluated on every re-render.
    private var trailingSymbol: String {
        if !item.isRemovable { return "lock" }
        if item.kind == .bundle { return "app.badge" }
        return item.isDirectory ? "folder" : "doc"
    }

    private var titleColor: Color {
        guard item.isRemovable else { return Theme.Colors.textTertiary }
        return checked ? Color.primary : Theme.Colors.textSecondary
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            UninstallCheckbox(checked: checked, locked: !item.isRemovable)
            Text(item.url.lastPathComponent)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
                .foregroundStyle(titleColor)
            Text(directory)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                // The distinguishing part of a long support path is its tail.
                .truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.md)
            // "-" while a size is still being measured or can't be, so the column never blinks in and
            // out of existence as the walks land.
            Text(item.size.map(UninstallFormat.size) ?? "-")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Group {
                if let icon, item.isRemovable {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: trailingSymbol)
                        .font(Theme.Typography.menuIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .help(item.isRemovable ? "" : "Locked — Tinycast can’t remove this")
    }
}

/// A checkbox drawn from `Theme` tokens rather than `checkmark.square`, so the box matches the panel's
/// white-alpha ramp (an SF checkbox glyph reads as a hairline outline on this surface).
private struct UninstallCheckbox: View {
    let checked: Bool
    /// A locked row's box is drawn fainter still, so it reads as unavailable rather than merely unchecked.
    var locked = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.checkbox, style: .continuous)
        return ZStack {
            if locked {
                shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            } else if checked {
                shape.fill(Color.primary.opacity(0.85))
                Image(systemName: "checkmark")
                    .font(Theme.Typography.keyCap.weight(.bold))
                    // Punched out of the filled box: the one place a near-black foreground is correct.
                    .foregroundStyle(Color.black.opacity(0.8))
            } else {
                shape.strokeBorder(Theme.Colors.border, lineWidth: 1)
            }
        }
        .frame(width: Theme.Size.checkbox, height: Theme.Size.checkbox)
    }
}

/// Byte formatting for the uninstall screen — one formatter, so row sizes and the status line can
/// never render the same number two ways.
@MainActor
enum UninstallFormat {
    /// `ByteCountFormatter` isn't `Sendable`; the one instance stays pinned to the main actor, which is
    /// where every row and the status line render anyway.
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func size(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}

/// Actions menu content for the uninstall screen, shown bottom-right on right-click or from the pill.
@MainActor
enum UninstallActionsMenu {
    /// `visible` is the filtered list the palette's selection indexes — never `session.items`, which is
    /// the unfiltered one and would point at a different row the moment a filter is typed.
    static func content(
        session: UninstallSession, visible: [LeftoverItem], selection: Int, core: AppCore
    ) -> PopoverMenuContent {
        let name = session.target?.name ?? "Application"
        var items: [PopoverMenuItem] = []
        // Both removal rows appear only with something checked, so neither can fire on an empty list.
        if !session.checkedItems.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", shortcut: "↵",
                    isDestructive: true
                ) { core.confirmUninstall() })
            // Finder's own pairing and Finder's own chord: the Trash is the default, permanent deletion
            // is a separate row on ⇧⌘⌫ — and unlike the Trash path it confirms first.
            items.append(
                PopoverMenuItem(
                    title: "Permanently Delete…", systemImage: "trash.slash", shortcut: "⇧⌘⌫",
                    isDestructive: true
                ) { core.confirmUninstall(permanently: true) })
        }
        if visible.indices.contains(selection) {
            let item = visible[selection]
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {
                    core.showLeftoverInFinder(item)
                })
        }
        items.append(
            PopoverMenuItem(title: "Cancel", systemImage: "xmark", shortcut: "⎋") {
                core.cancelUninstall()
            })
        return PopoverMenuContent(header: "Uninstall \(name)", items: items)
    }

    /// The header sort control's menu: one row per order, the active one marked with a checkmark.
    /// `onSelect` carries the scroll reset the re-order needs, which only the view owns.
    static func sortContent(
        session: UninstallSession, onSelect: @escaping (UninstallSort) -> Void
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: "Sort",
            items: UninstallSort.allCases.map { sort in
                PopoverMenuItem(
                    title: sort.title,
                    systemImage: sort == session.sort ? "checkmark" : sort.systemImage
                ) { onSelect(sort) }
            })
    }
}
