import SwiftUI

/// The palette's extension screen: whichever root component the running command rendered.
struct ExtensionCommandView: View {
    let screen: ExtensionScreen
    let state: ExtensionSessionState
    let selection: Int
    let assetsPath: String?
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
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
                    screen: screen, assetsPath: assetsPath, onChange: onFieldChange,
                    onSubmit: onActivate)
            case .unsupported(let type):
                if type.isEmpty {
                    // A commit arrived but the command rendered nothing — it returned null, usually
                    // because it has no data to show. Saying "Starting…" here would claim it is still
                    // launching, which is how a permanently-null command looked like a hang.
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

/// A command that threw, or one Tinycast can't render. The stack trace is kept — it's the only debugging
/// signal an extension author gets.
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

/// Toasts a running view command raised, stacked above the footer. `showHUD` is a separate floating
/// window (`HUDWindowController`) because a no-view command closes the palette before it finishes.
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

/// Actions menu content for the running command's current selection.
@MainActor
enum ExtensionActionsMenu {
    static func content(
        screen: ExtensionScreen, selection: Int, assetsPath: String?, core: AppCore
    ) -> PopoverMenuContent? {
        let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection))
        guard !actions.isEmpty else { return nil }
        let header =
            screen.items.indices.contains(selection)
            ? screen.items[selection].string("title") : screen.navigationTitle
        return PopoverMenuContent(
            header: header,
            items: actions.map { action in
                PopoverMenuItem(
                    title: action.title,
                    systemImage: symbolName(for: action),
                    shortcut: action.shortcutCaps?.joined()
                ) {
                    guard let handler = action.handler else { return }
                    core.extensions.dispatch(handler: handler)
                }
            })
    }

    /// The popover menu draws SF Symbols, so an extension icon resolves to one; a file-based icon falls
    /// back to a neutral glyph rather than an empty slot.
    private static func symbolName(for action: ExtensionAction) -> String {
        guard let resolved = ExtensionImage.resolve(action.iconValue, assetsPath: nil),
            case .symbol(let name) = resolved.source
        else { return action.isDestructive ? "trash" : "bolt" }
        return name
    }
}
