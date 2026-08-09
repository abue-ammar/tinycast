import SwiftUI

/// Past calculations, led by the live answer for whatever is typed into the search field.
struct CalculatorHistoryScreen: PaletteScreen {
    let history: CalculatorHistoryStore
    let currencyRates: CurrencyRateStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// The card is a row like any other, so the flat selection indexes `rows` with no offset.
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case entry(CalcHistoryEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .entry(let entry): return entry.id.uuidString
            }
        }
    }

    private var calc: CalcResult? { CalcMemo.evaluate(vm.query, currency: currencyRates.source) }
    private var entries: [CalcHistoryEntry] { history.search(vm.query) }

    var rows: [Row] {
        let entries = entries.map(Row.entry)
        guard let calc else { return entries }
        return [.calc(calc)] + entries
    }

    var primaryActionTitle: String { "Copy Answer" }

    private func row(at selection: Int) -> Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func entry(at selection: Int) -> CalcHistoryEntry? {
        guard case .entry(let entry) = row(at: selection) else { return nil }
        return entry
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        if case .calc = row(at: selection) { return true }
        return false
    }

    /// An error card is selectable but can't be copied, so it drives neither the pill nor ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .entry(let entry):
            return CalcHistoryActionsMenu.content(entry: entry, core: core, calcHistory: history)
        case nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        // A fresh calculation: copy + record like the launcher card; error cards no-op.
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .entry(let entry): core.calculatorCoordinator.copyHistoryEntry(entry)
        case nil: break
        }
    }

    /// ⌘↵: the inline card has no expression to copy, so only stored entries respond.
    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        core.calculatorCoordinator.copyHistoryExpression(entry)
        return true
    }

    /// ⌘⌫ — the screen owns the chord, but the inline card can't be deleted.
    func delete(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        history.remove(entry)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: vm.query.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "No calculations yet" : "No matching calculations")
        } else {
            CalculatorHistoryList(
                results: entries,
                selectedID: entry(at: selection)?.id,
                scroll: scroll,
                calc: calc,
                calcSelected: isCardSelected(selection),
                onActivateCalc: {
                    vm.selection = 0
                    activate(at: 0)
                },
                onCalcActions: {
                    guard let calc, case .value = calc.payload else { return }
                    vm.selection = 0
                    openActions()
                },
                onSelect: { entry in
                    if let index = rows.firstIndex(of: .entry(entry)) { vm.selection = index }
                },
                onActivate: { activate(at: vm.selection) },
                onActions: { entry in
                    if let index = rows.firstIndex(of: .entry(entry)) { vm.selection = index }
                    openActions()
                }
            )
        }
    }
}

/// Actions menu content for a calculator-history entry, shown bottom-right like the other modes.
@MainActor
enum CalcHistoryActionsMenu {
    static func content(
        entry: CalcHistoryEntry, core: AppCore, calcHistory: CalculatorHistoryStore
    )
        -> PopoverMenuContent
    {
        PopoverMenuContent(
            header: entry.expression,
            items: [
                PopoverMenuItem(title: "Copy Answer", systemImage: "doc.on.doc", shortcut: "↵") {
                    core.calculatorCoordinator.copyHistoryEntry(entry)
                },
                PopoverMenuItem(
                    title: "Copy Expression", systemImage: "doc.on.doc.fill", shortcut: "⌘↵"
                ) {
                    core.calculatorCoordinator.copyHistoryExpression(entry)
                },
                PopoverMenuItem(title: "Delete Entry", systemImage: "trash", isDestructive: true) {
                    calcHistory.remove(entry)
                },
                PopoverMenuItem(
                    title: "Delete All Entries", systemImage: "trash.fill", isDestructive: true
                ) {
                    calcHistory.clearAll()
                }
            ]
        )
    }
}
