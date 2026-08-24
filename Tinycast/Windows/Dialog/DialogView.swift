import SwiftUI

extension DialogTone {
    /// Tints the leading glyph only; buttons take their color from `DialogAction.Role`.
    var tint: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return Theme.Colors.success
        case .danger: return Theme.Colors.destructive
        }
    }
}

/// A dialog: the palette's surface recipe at dialog size, glass only on the buttons.
struct DialogView: View {
    let request: DialogRequest
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                if let symbol = request.symbol {
                    SymbolImage(name: symbol, size: Theme.Size.dialogIcon)
                        .foregroundStyle(request.tone.tint)
                        .frame(width: Theme.Size.dialogIcon)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(request.title)
                        .font(.headline)
                    if let message = request.message {
                        Text(message)
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            switch request.accessory {
            case .volume(let volume): VolumeSlider(state: volume)
            case .eventDraft(let draft): EventDraftFields(state: draft)
            case nil: EmptyView()
            }

            HStack(spacing: Theme.Spacing.md) {
                Spacer(minLength: 0)
                ForEach(visualOrder, id: \.self) { index in
                    DialogButton(
                        action: request.actions[index],
                        keyCap: keyCap(for: index),
                        onActivate: { onChoose(index) }
                    )
                }
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.dialogWidth, alignment: .leading)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
    }

    /// Cancel renders leading; `onChoose` still dispatches against the original order.
    private var visualOrder: [Int] {
        request.actions.indices.sorted { rank(of: $0) < rank(of: $1) }
    }

    private func rank(of index: Int) -> Int {
        request.actions[index].role == .cancel ? 0 : 1
    }

    /// Only the two keys the panel handles are advertised, so a tooltip can't drift.
    private func keyCap(for index: Int) -> String? {
        if index == request.defaultIndex { return "↵" }
        if index == request.cancelIndex { return "esc" }
        return nil
    }
}

private struct DialogButton: View {
    let action: DialogAction
    let keyCap: String?
    let onActivate: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onActivate) {
            Text(action.title)
                .font(Theme.Typography.bar)
                .foregroundStyle(labelColor)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.menuButton)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Capsule())
        .tooltip(keyCap)
    }

    private var labelColor: Color {
        switch action.role {
        case .standard: return .primary
        case .destructive: return Theme.Colors.destructive
        case .cancel: return Theme.Colors.textSecondary
        }
    }
}
