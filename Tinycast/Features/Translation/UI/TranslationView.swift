import SwiftUI

/// The translator's two columns: the draft on the left, its translation or status on the right.
struct TranslationView: View {
    let toggleActions: () -> Void
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var vm
    @Environment(\.metrics) private var metrics
    @State private var sourceFocused = false
    @State private var resultFocused = false

    var body: some View {
        HStack(spacing: 0) {
            sourceColumn
            resultColumn
        }
        .overlay { SwapButton() }
        .background { ColumnBackdrop() }
        .onAppear(perform: appeared)
        // Ordering out never unmounts the tree, so visibility is the lifecycle, not appearance.
        .onChange(of: vm.isVisible) { _, visible in
            if visible {
                coordinator.activate()
            } else {
                coordinator.suspend()
            }
        }
        .onChange(of: vm.focusToken) { focusSource() }
        .onChange(of: sourceFocused || resultFocused) { _, editing in vm.noteEditingField(editing) }
        .onDisappear { vm.noteEditingField(false) }
    }

    private var sourceColumn: some View {
        TranslationTextView(
            role: .source, text: coordinator.text,
            onEdit: { coordinator.setText($0, isComposing: $1) },
            onFocusChange: { sourceFocused = $0 },
            onCopy: { coordinator.copyTranslation() }, onMenu: toggleActions
        )
        .modifier(ColumnFade())
        .overlay(alignment: .topLeading) {
            // Marked text leaves the committed draft empty, and composing it is still typing.
            if coordinator.text.isEmpty, !coordinator.isComposing {
                Placeholder(text: "Enter text…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultColumn: some View {
        TranslationTextView(
            role: .result, text: coordinator.session.result?.text ?? "",
            onFocusChange: { resultFocused = $0 },
            onCopy: { coordinator.copyTranslation() }, onMenu: toggleActions
        )
        .modifier(ColumnFade())
        .overlay(alignment: .topLeading) {
            if coordinator.session.result == nil { Status() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appeared() {
        if vm.isVisible { coordinator.activate() }
        focusSource()
    }

    /// Next turn: on first mount the text view has no window to become first responder of yet.
    private func focusSource() {
        Task { @MainActor in TranslationTextView.focusSource(in: nil) }
    }
}

/// The empty column's prompt, in the search field's own larger face.
private struct Placeholder: View {
    let text: String
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text(text)
            .font(metrics.typography.searchField)
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(metrics.spacing.xxl)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The right column before a translation exists: setup, progress, or the failure and its way out.
private struct Status: View {
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        if let issue = coordinator.configurationIssue {
            block {
                message(issue)
                actions(canRetry: false)
            }
        } else if let error = coordinator.languageError {
            block {
                failure(error)
                actions(canRetry: coordinator.canRetry)
            }
        } else if coordinator.isLoadingLanguages {
            block { progress("Loading languages…") }
        } else {
            switch coordinator.session.state {
            case .idle, .completed:
                Placeholder(text: "Translation")
            case .waiting:
                block { message("Waiting…") }
            case .translating:
                block { progress("Translating…") }
            case .failed(let error):
                block {
                    failure(error)
                    actions(canRetry: coordinator.canRetry)
                }
            }
        }
    }

    /// Sits where the translation's first line would, and wraps at the column like one.
    private func block(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) { content() }
            .padding(metrics.spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(metrics.typography.rowTitle)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
    }

    /// The tone tints the glyph alone, as a dialog's does.
    private func failure(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.destructive)
            message(text)
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: metrics.spacing.md) {
            // A `ProgressView` spinner is drawn by AppKit and ignores every tint it is given.
            Image(systemName: "progress.indicator")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.progress)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
            message(text)
        }
    }

    private func actions(canRetry: Bool) -> some View {
        HStack(spacing: metrics.spacing.md) {
            if canRetry {
                Button("Retry") { coordinator.retry() }
                    .buttonStyle(.modalAction(.primary, fillsWidth: false))
                    .accessibilityLabel("Retry Translation")
            }
            Button("Open Translation Settings") { coordinator.openSettings() }
                .buttonStyle(.modalAction(canRetry ? .standard : .primary, fillsWidth: false))
        }
    }
}

/// The glass circle on the seam; hover lives here, so a sweep never re-renders the columns.
private struct SwapButton: View {
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @State private var hovered = false

    var body: some View {
        let enabled = coordinator.canSwap
        Button(action: { coordinator.swap() }) {
            Image(systemName: "arrow.left.arrow.right")
                .font(
                    .system(
                        size: metrics.scaled(Theme.Typography.menuSymbolSize),
                        weight: Theme.Typography.menuSymbolWeight))
                .foregroundStyle(enabled ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                .frame(width: metrics.size.menuButton, height: metrics.size.menuButton)
                .background(Circle().fill(hovered && enabled ? Theme.Colors.rowHover : Color.clear))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
        .tooltip(enabled ? "Swap Languages" : "Choose a source language to swap.")
        .accessibilityLabel("Swap Languages")
    }
}

/// The columns' surfaces: the draft's faint fill, the seam's hairline, dissolving into the bars.
private struct ColumnBackdrop: View {
    @Environment(\.metrics) private var metrics

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Theme.Colors.cardFill
                Color.clear
            }
            .overlay {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: Theme.Size.hairline)
            }
            .mask {
                LinearGradient(
                    stops: stops(height: geometry.size.height), startPoint: .top, endPoint: .bottom)
            }
        }
        // The bars are safe-area insets; the surface runs under them and fades out, never clips.
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard height > 0 else { return [.init(color: .black, location: 0)] }
        let header = (metrics.size.headerPadding + metrics.size.headerHeight) / height
        let footer = metrics.size.bottomBarHeight / height
        return [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black, location: header),
            .init(color: .black, location: 1 - footer),
            .init(color: .black.opacity(0), location: 1)
        ]
    }
}

/// Text scrolling through a column's own inset softens over it instead of cutting at the edge.
private struct ColumnFade: ViewModifier {
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { geometry in
                LinearGradient(
                    stops: stops(height: geometry.size.height), startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard height > 0 else { return [.init(color: .black, location: 0)] }
        let band = metrics.spacing.xxl / height
        return [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black, location: band),
            .init(color: .black, location: 1 - band),
            .init(color: .black.opacity(0), location: 1)
        ]
    }
}
