import SwiftUI

extension DialogTone {
    /// Tints the subject glyph only; buttons take their color from `DialogAction.Role`.
    var tint: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return Theme.Colors.success
        case .danger: return Theme.Colors.destructive
        }
    }

    var tileFill: Color {
        switch self {
        case .neutral: return tint.opacity(0.12)
        case .success, .danger: return tint.opacity(0.18)
        }
    }
}

/// Tinycast's Liquid Glass dialog, compact unless a native control needs more room.
struct DialogView: View {
    @Environment(\.metrics) private var metrics
    let request: DialogRequest
    let width: CGFloat
    let onChoose: (Int) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
            VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
                if let symbol = request.symbol {
                    DialogSymbol(name: symbol, tone: request.tone)
                }

                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    Text(request.title)
                        .font(metrics.typography.panelTitle)
                    if let message = request.message {
                        Text(message)
                            .font(metrics.typography.rowTitle)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                switch request.accessory {
                case .volume(let volume): VolumeSlider(state: volume)
                case .eventDraft(let draft): EventDraftFields(state: draft)
                case .snippetArguments(let arguments): SnippetArgumentFields(state: arguments)
                case nil: EmptyView()
                }
            }
            .padding(.horizontal, metrics.spacing.xs)
            .padding(.top, metrics.spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(metrics.spacing.dialogInset)
        .frame(width: width, alignment: .leading)
        .background(Theme.Colors.panelScrim, in: shape)
        .glassEffect(.regular, in: shape)
    }

    @ViewBuilder private var actions: some View {
        if request.actions.count == 2 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: metrics.spacing.md) { actionButtons(singleLine: true) }
                VStack(spacing: metrics.spacing.md) { actionButtons(singleLine: false) }
            }
        } else if request.actions.count > 2 {
            VStack(spacing: metrics.spacing.md) { actionButtons }
        } else {
            HStack(spacing: metrics.spacing.md) { actionButtons }
        }
    }

    private var actionButtons: some View {
        actionButtons(singleLine: false)
    }

    private func actionButtons(singleLine: Bool) -> some View {
        ForEach(visualOrder, id: \.self) { index in
            DialogButton(
                action: request.actions[index],
                isDefault: index == request.defaultIndex,
                keyCap: keyCap(for: index),
                singleLine: singleLine,
                onActivate: { onChoose(index) }
            )
        }
    }

    /// Cancel leads a horizontal pair; a vertical choice keeps the caller's semantic order.
    private var visualOrder: [Int] {
        guard request.actions.count < 3 else { return Array(request.actions.indices) }
        return request.actions.indices.sorted { rank(of: $0) < rank(of: $1) }
    }

    private func rank(of index: Int) -> Int {
        request.actions[index].role == .cancel ? 0 : 1
    }

    /// Only the two keys the panel handles are advertised, so a tooltip can't drift.
    private func keyCap(for index: Int) -> String? {
        if index == request.defaultIndex { return "↵" }
        if index == request.cancelIndex { return "⎋" }
        return nil
    }
}

private struct DialogSymbol: View {
    @Environment(\.metrics) private var metrics
    let name: String
    let tone: DialogTone

    var body: some View {
        SymbolImage(name: name, size: metrics.size.dialogSymbol, monochrome: true)
            .foregroundStyle(symbolTint)
            .frame(
                width: metrics.size.dialogSymbolContainer,
                height: metrics.size.dialogSymbolContainer
            )
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.dialogSymbol, style: .continuous)
                    .fill(tone.tileFill))
    }

    /// Neutral glyphs need the same legibility as a key-cap symbol; semantic colours stay intact.
    private var symbolTint: Color {
        tone == .neutral ? Theme.Colors.textSecondary : tone.tint
    }
}

private struct DialogButton: View {
    let action: DialogAction
    let isDefault: Bool
    let keyCap: String?
    var singleLine = false
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            Text(action.title)
                .fixedSize(horizontal: singleLine, vertical: false)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.modalAction(role))
        .tooltip(keyCap: keyCap)
    }

    private var role: ModalActionButtonStyle.Role {
        if isDefault, action.role == .standard { return .primary }
        return switch action.role {
        case .standard: .standard
        case .destructive: .destructive
        case .cancel: .cancel
        }
    }
}
