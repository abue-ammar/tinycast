import AppKit

/// Owns copying a calculation out: the inline card records history, a history row never re-records.
@MainActor
final class CalculatorCoordinator {
    private let calcHistory: CalculatorHistoryStore
    private let paletteCoordinator: PaletteCoordinator
    /// Dialogs, for the one action here that can't be undone.
    private unowned let core: AppCore

    init(
        calcHistory: CalculatorHistoryStore, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.calcHistory = calcHistory
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// Both the ⌃⇧X chord and the menu row land here, so neither can skip the confirmation.
    func deleteAllHistory() async {
        guard
            await core.confirm(
                title: "Clear calculation history?",
                message: "Every past calculation goes. This can't be undone.",
                symbol: PaletteMode.calculatorHistory.systemImage, confirmTitle: "Clear History")
        else { return }
        calcHistory.clearAll()
    }

    /// Enter on the inline calculator card: copy the answer, remember the calculation, dismiss.
    func copyCalculatorResult(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(copyText)
    }

    /// `⇧⌘↵` on the card: the whole calculation, for pasting into a note or a message.
    func copyCalculationWithExpression(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText("\(result.expression) = \(copyText)")
    }

    /// Enter on a Calculator History row: re-copy the stored answer (no re-record).
    func copyHistoryEntry(_ entry: CalcHistoryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.result.replacingOccurrences(of: ",", with: ""))
    }

    func copyHistoryExpression(_ entry: CalcHistoryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.expression)
    }
}
