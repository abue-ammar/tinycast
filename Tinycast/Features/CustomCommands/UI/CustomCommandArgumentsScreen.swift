import SwiftUI

struct CustomCommandArgumentsScreen: PaletteScreen {
    /// The form has no list of its own: every value is typed into the palette's search field.
    struct Row: Identifiable { let id: Int }

    let session: CustomCommandArgumentSession
    let core: AppCore
    let vm: PaletteState

    var rows: [Row] { [] }

    var primaryActionTitle: String { session.isLastArgument ? "Run Command" : "Next" }

    /// A required argument holds ↵ until it has a value, which also hides the footer pill.
    func hasPrimaryAction(at selection: Int) -> Bool {
        guard let current = session.current else { return false }
        return current.isOptional || !vm.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func secondary(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard hasPrimaryAction(at: selection) else { return }
        core.customCommandCoordinator.submitCustomCommandArgument(vm.query)
        // More to answer: clear the field so the next argument starts on an empty one.
        if session.isActive { vm.query = "" }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(CustomCommandArgumentsView(session: session))
    }
}
