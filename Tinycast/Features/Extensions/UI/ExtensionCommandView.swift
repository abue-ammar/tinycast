import SwiftUI

/// The palette's extension screen: whichever root component the running command rendered.
struct ExtensionCommandView: View {
    let screen: ExtensionScreen
    let state: ExtensionSessionState
    let selection: Int
    let assetsPath: String?
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    let onFieldChange: (RenderNode, Any) -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .launching where screen.root == nil:
            EmptyResults(text: "Starting…")
        case .failed(let message):
            ExtensionFailureView(message: message)
        case .finished:
            EmptyResults(text: "Done")
        default:
            switch screen.kind {
            case .list, .grid:
                ExtensionListView(
                    screen: screen, selection: selection, assetsPath: assetsPath,
                    scroll: scroll, onSelect: onSelect, onActivate: onActivate,
                    onActions: onActions)
            case .detail:
                ExtensionDetailBody(
                    markdown: screen.root?.string("markdown"),
                    metadata: screen.root?.node("metadata"),
                    isLoading: screen.isLoading, assetsPath: assetsPath)
            case .form:
                ExtensionFormView(
                    screen: screen, assetsPath: assetsPath, selection: selection, scroll: scroll,
                    onSelect: onSelect, onChange: onFieldChange,
                    onSubmit: { onActivate(selection) })
            case .unsupported(let type):
                if type.isEmpty {
                    // A commit rendered null; "Starting…" here would look like a hang.
                    EmptyResults(text: "Nothing to show")
                } else {
                    ExtensionFailureView(
                        message:
                            "This command renders \(type), which Tinycast doesn't support yet. See docs/extensions.md."
                    )
                }
            }
        }
    }
}

/// The stack trace is kept: it is the only debugging signal an author gets.
struct ExtensionFailureView: View {
    let message: String

    private var headline: String {
        message.split(separator: "\n").first.map(String.init) ?? message
    }
    private var detail: String? {
        let lines = message.split(separator: "\n").dropFirst()
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(headline)
                        .font(Theme.Typography.rowTitle)
                        .textSelection(.enabled)
                }
                if let detail {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
            .hideNativeScrollers()
        }
        .thinScrollbar()
    }
}

/// `showHUD` is a separate window: a no-view command closes the palette first.
struct ExtensionFeedbackOverlay: View {
    let toasts: [ExtensionToast]
    let onToastAction: (String) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(toasts) { toast in
                ToastRow(toast: toast, onAction: onToastAction)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, Theme.Size.bottomBarHeight)
        .padding(.horizontal, Theme.Spacing.md)
        .animation(.easeOut(duration: 0.16), value: toasts.map(\.id))
    }

    private struct ToastRow: View {
        let toast: ExtensionToast
        let onAction: (String) -> Void

        private var icon: (name: String, tint: Color) {
            switch toast.style {
            case .success: return ("checkmark.circle.fill", .green)
            case .failure: return ("xmark.circle.fill", .red)
            case .animated: return ("arrow.trianglehead.2.clockwise", Theme.Colors.textSecondary)
            }
        }

        var body: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon.name)
                    .foregroundStyle(icon.tint)
                    .symbolEffect(.rotate, isActive: toast.style == .animated)
                VStack(alignment: .leading, spacing: 0) {
                    Text(toast.title).font(Theme.Typography.bar).lineLimit(1)
                    if let message = toast.message, !message.isEmpty {
                        Text(message)
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                if let action = toast.primaryAction {
                    Button(action.title) { onAction(action.token) }
                        .buttonStyle(.plain)
                        .font(Theme.Typography.bar)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frosted(in: RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
        }
    }
}

/// The ⌘K panel's content for the running command's current selection.
@MainActor
enum ExtensionActionsMenu {
    /// What the panel belongs to: the selected row, or the screen when the selection has outrun it.
    static func header(screen: ExtensionScreen, selection: Int) -> String? {
        // A form's rows are its fields, and the panel acts on the form rather than on one field.
        guard screen.kind != .form, screen.items.indices.contains(selection) else {
            return screen.navigationTitle
        }
        return screen.items[selection].node.string("title")
    }

    /// Rows carry a resolved `ExtensionImage`; resolving per ↑/↓ would probe symbols on main.
    static func rows(_ actions: [ExtensionAction], assetsPath: String?) -> [ExtensionActionItem] {
        actions.map { action in
            ExtensionActionItem(
                title: action.title,
                icon: ExtensionImage.actionIcon(
                    action.iconValue, assetsPath: assetsPath,
                    // Read rather than injected: a panel is rebuilt each time it opens.
                    isDark: NSApp.effectiveAppearance.isDark,
                    isDestructive: action.isDestructive),
                shortcut: action.shortcutCaps?.joined(),
                isDestructive: action.isDestructive)
        }
    }
}
