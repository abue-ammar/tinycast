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
    @Environment(\.metrics) private var metrics
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
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                HStack(spacing: metrics.spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(headline)
                        .font(metrics.typography.rowTitle)
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
            .padding(metrics.spacing.lg)
            .hideNativeScrollers()
        }
        .thinScrollbar()
    }
}

struct ExtensionToastPill: View {
    private static let glowOpacity = 0.14
    private static let glowRadius: CGFloat = 150
    private static let rimOpacity = 0.25

    @Environment(\.metrics) private var metrics
    let toast: ExtensionToast
    let onAction: (String) -> Void
    let onDismiss: () -> Void
    @State private var hovered = false
    /// A fresh stamp re-arms the reset, so a second copy holds "Copied".
    @State private var copiedAt: Date?

    private var tint: Color {
        switch toast.style {
        case .success: Theme.Colors.success
        case .failure: Theme.Colors.destructive
        case .animated: Theme.Colors.progress
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            mark.frame(width: metrics.size.menuButton, height: metrics.size.menuButton)
            HStack(spacing: metrics.spacing.md) {
                Text(toast.title).foregroundStyle(Theme.Colors.textPrimary)
                if let message = toast.message, !message.isEmpty {
                    Text(message).foregroundStyle(Theme.Colors.textSecondary)
                }
                if toast.style == .failure {
                    divider
                    button {
                        Paster.copyPlainText(
                            [toast.title, toast.message].compactMap(\.self).joined(separator: "\n"))
                        copiedAt = Date()
                    } label: {
                        // The wider word holds the width, so the pill never twitches on copy.
                        ZStack {
                            Text("Copied").hidden()
                            Text(copiedAt == nil ? "Copy" : "Copied")
                        }
                    }
                } else if let action = toast.primaryAction {
                    divider
                    button {
                        onAction(action.token)
                    } label: {
                        Text(action.title)
                    }
                }
            }
            .font(metrics.typography.bar)
            .lineLimit(1)
            .padding(.trailing, metrics.spacing.xl)
        }
        .frame(height: metrics.size.menuButton)
        .fixedSize()
        .background { glow }
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [tint.opacity(Self.rimOpacity), tint.opacity(0.06), .clear],
                    startPoint: .leading, endPoint: .trailing),
                lineWidth: Theme.Size.hairline)
        }
        .frosted(in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: onDismiss)
        .onHover { isHovered in
            withAnimation(.easeOut(duration: Theme.Duration.hover)) { hovered = isHovered }
        }
        .accessibilityAction(named: "Dismiss", onDismiss)
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            copiedAt = nil
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.border)
            .frame(width: Theme.Size.hairline, height: metrics.size.menuIcon * 0.7)
    }

    private func button(
        action: @escaping () -> Void, @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action, label: label)
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    private var glow: some View {
        GeometryReader { proxy in
            Capsule().fill(
                RadialGradient(
                    colors: [tint.opacity(Self.glowOpacity), tint.opacity(0.03), .clear],
                    center: UnitPoint(x: metrics.size.menuButton / 2 / proxy.size.width, y: 0.5),
                    startRadius: 0, endRadius: Self.glowRadius))
        }
    }

    private var mark: some View {
        Group {
            if hovered {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                symbol.foregroundStyle(tint)
            }
        }
        .font(metrics.typography.menuIcon)
        .transition(.opacity)
    }

    @ViewBuilder
    private var symbol: some View {
        switch toast.style {
        case .success: Image(systemName: "checkmark")
        case .failure: Image(systemName: "exclamationmark")
        case .animated:
            Image(systemName: "progress.indicator")
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
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
                isDestructive: action.isDestructive,
                startsSection: action.startsSection)
        }
    }
}
