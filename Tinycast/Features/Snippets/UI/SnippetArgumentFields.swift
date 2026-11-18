import SwiftUI

struct SnippetArgumentFields: View {
    @Environment(\.metrics) private var metrics
    @Bindable var state: SnippetArgumentsState
    let onSubmit: () -> Void
    @FocusState private var focus: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) {
            ForEach(state.arguments.indices, id: \.self) { index in
                field(at: index)
            }
        }
        .onChange(of: state.focusedIndex) { _, index in focus = index }
        .onChange(of: focus) { _, index in
            if let index { state.focusedIndex = index }
        }
    }

    private func field(at index: Int) -> some View {
        let argument = state.arguments[index]
        return VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            if state.showsNames {
                Text(argument.name)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if argument.options.isEmpty {
                TextField("", text: $state.texts[index], prompt: Text(argument.name))
                    .dialogTextField()
                    .focused($focus, equals: index)
            } else {
                SnippetOptionList(
                    state: state, index: index, isFocused: focus == index,
                    onFocus: { focus = index }, onSubmit: onSubmit
                )
                .focused($focus, equals: index)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Snippet argument \(argument.name)")
    }
}

private struct SnippetOptionList: View {
    @Environment(\.metrics) private var metrics
    let state: SnippetArgumentsState
    let index: Int
    let isFocused: Bool
    let onFocus: () -> Void
    let onSubmit: () -> Void

    private var options: [String] { state.arguments[index].options }
    private var choice: Int { state.choices[index] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: metrics.spacing.xxs) {
                    ForEach(options.indices, id: \.self) { option in
                        SnippetOptionRow(
                            title: options[option], isChosen: option == choice,
                            isFocused: isFocused,
                            onPick: {
                                state.choices[index] = option
                                onFocus()
                            },
                            onSubmit: onSubmit
                        )
                        .id(option)
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: height)
            .onChange(of: choice) { proxy.scrollTo(choice) }
        }
        .focusable()
        // The chosen row's fill marks focus, so AppKit's blue ring would be a second one.
        .focusEffectDisabled()
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
            state.moveChoice(at: index, by: -1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
            state.moveChoice(at: index, by: 1)
            return .handled
        }
    }

    private var height: CGFloat {
        let rows = min(CGFloat(options.count), Theme.Size.menuVisibleRows)
        let pitch = metrics.size.dialogButtonHeight + metrics.spacing.xxs
        return (rows * pitch - metrics.spacing.xxs).rounded()
    }
}

private struct SnippetOptionRow: View {
    @Environment(\.metrics) private var metrics
    let title: String
    let isChosen: Bool
    let isFocused: Bool
    let onPick: () -> Void
    let onSubmit: () -> Void
    @State private var hovered = false

    private var fill: Color {
        if isChosen, isFocused { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: metrics.spacing.md) {
                Text(title)
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(metrics.typography.rowTrailing.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, metrics.spacing.lg)
            .frame(height: metrics.size.dialogButtonHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        // Alongside the button, so the first click still picks without waiting out a double.
        .simultaneousGesture(TapGesture(count: 2).onEnded(onSubmit))
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}
