import SwiftUI
@preconcurrency import Translation

struct QuickActionResultView: View {
    let state: QuickActionPanelState
    let languages: [Locale.Language]
    let onReplace: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    let onRetranslate: (Locale.Language) -> Void
    let onDownloaded: () -> Void
    let onHeight: (CGFloat) -> Void

    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var download: TranslationSession.Configuration?

    /// Explicit overlays, not `safeAreaBar`: that lays its bars over the content instead of inset.
    var body: some View {
        ScrollView {
            body(for: state.phase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.xxl)
                // A `ScrollView` has no ideal height, so the frame below is set, not merely capped.
                .fixedSize(horizontal: false, vertical: true)
                // Measured before the insets, so `isScrollable` cannot depend on its own answer.
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
                .padding(.top, inset(headerHeight))
                .padding(.bottom, inset(footerHeight))
        }
        .scrollBounceBehavior(.basedOnSize)
        .mask(scrollFade)
        .overlay(alignment: .top) { measured(header) { headerHeight = $0 } }
        .overlay(alignment: .bottom) { measured(footer) { footerHeight = $0 } }
        .frame(width: Theme.Size.quickActionPanel, height: panelHeight)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
        // Reported, not measured: the frame above is ours, so reading it back would feed itself.
        .onChange(of: panelHeight, initial: true) { onHeight(panelHeight) }
        .translationTask(download) { session in
            try? await session.prepareTranslation()
            await MainActor.run {
                download = nil
                onDownloaded()
            }
        }
    }

    private func measured(_ bar: some View, action: @escaping (CGFloat) -> Void) -> some View {
        bar.onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: action)
    }

    /// Clears the bar and its ramp, so the first line is opaque until it scrolls into the gradient.
    private func inset(_ bar: CGFloat) -> CGFloat {
        bar + (isScrollable ? Theme.Size.quickActionScrollFade : 0)
    }

    /// A mask, not `scrollEdgeEffectStyle`: its material composited to nothing over this vibrancy.
    @ViewBuilder
    private var scrollFade: some View {
        if isScrollable {
            VStack(spacing: 0) {
                // Fully clear behind each bar, or text bleeds around the title and the buttons.
                Color.clear.frame(height: headerHeight)
                ramp(from: .clear, to: .black)
                Color.black
                ramp(from: .black, to: .clear)
                Color.clear.frame(height: footerHeight)
            }
        } else {
            // Dissolving a result that already fits would dim it for nothing.
            Color.black
        }
    }

    private func ramp(from start: Color, to end: Color) -> some View {
        LinearGradient(colors: [start, end], startPoint: .top, endPoint: .bottom)
            .frame(height: Theme.Size.quickActionScrollFade)
    }

    private var isScrollable: Bool { contentHeight > Theme.Size.quickActionPanelBody }

    private var panelHeight: CGFloat {
        let chrome = headerHeight + footerHeight
        return min(
            max(contentHeight + chrome, chrome + Theme.Size.quickActionPanelMinBody),
            chrome + Theme.Size.quickActionPanelBody)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Only the title run drags: the handle is an overlay, and would eat the menu's clicks.
            HStack(spacing: Theme.Spacing.sm) {
                SymbolImage(name: state.action.symbol, size: Theme.Size.quickActionHeaderIcon)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(state.action.title)
                    .font(Theme.Typography.panelTitle)
                Spacer(minLength: Theme.Spacing.md)
            }
            .windowDraggable(true)
            if state.action == .translate, !languages.isEmpty { languageMenu }
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
    }

    @ViewBuilder
    private func body(for phase: QuickActionPanelState.Phase) -> some View {
        switch phase {
        case .running where state.output.isEmpty:
            HStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.small)
                Text("Working…").foregroundStyle(Theme.Colors.textSecondary)
            }
            .font(Theme.Typography.rowTitle)
        case .running, .finished:
            output
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .needsLanguageDownload:
            downloadPrompt
        }
    }

    @ViewBuilder
    private var output: some View {
        let chunks = state.diff
        if !chunks.isEmpty {
            // One `Text` per chunk would break the wrap, so the runs are styled inside one string.
            prose(Text(attributed(chunks)))
        } else if state.action == .summarize {
            MarkdownView(blocks: MarkdownBlock.parse(state.output))
        } else {
            prose(Text(state.output))
        }
    }

    /// A result is a paragraph to read rather than a row label, so it is led like one.
    private func prose(_ text: Text) -> some View {
        text
            .font(Theme.Typography.rowTitle)
            .lineSpacing(Theme.Spacing.xs)
            .textSelection(.enabled)
    }

    private func attributed(_ chunks: [TextDiffEngine.Chunk]) -> AttributedString {
        chunks.reduce(into: AttributedString()) { result, chunk in
            switch chunk {
            case .equal(let text):
                result.append(AttributedString(text))
            case .inserted(let text):
                var run = AttributedString(text)
                run.foregroundColor = Theme.Colors.success
                result.append(run)
            case .deleted(let text):
                var run = AttributedString(text)
                run.foregroundColor = Theme.Colors.destructive
                run.strikethroughStyle = .single
                result.append(run)
            }
        }
    }

    private var downloadPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("\(TextTranslator.displayName(of: state.targetLanguage)) hasn't been downloaded yet.")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Download") {
                download = TranslationSession.Configuration(
                    source: nil, target: state.targetLanguage)
            }
        }
    }

    private var languageMenu: some View {
        Menu(TextTranslator.displayName(of: state.targetLanguage)) {
            ForEach(languages, id: \.minimalIdentifier) { language in
                Button(TextTranslator.displayName(of: language)) { onRetranslate(language) }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.accessoryBar)
        .fixedSize()
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: Theme.Spacing.md)
            Button("Dismiss", action: onCancel)
            Button("Copy", action: onCopy).disabled(!state.canReplace)
            Button("Replace", action: onReplace)
                .buttonStyle(.borderedProminent)
                .disabled(!state.canReplace)
        }
        .controlSize(.large)
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
    }
}
