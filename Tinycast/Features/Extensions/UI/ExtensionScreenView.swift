import SwiftUI

/// What the running command shows, and the search and selection it is told about.
struct ExtensionScreenView: View {
    /// Which session answers searches; a change hands it text typed before it could.
    private struct SearchTarget: Equatable {
        let session: ObjectIdentifier?
        let handlesSearch: Bool
    }

    let coordinator: ExtensionCoordinator
    let session: ExtensionSession?
    let query: String
    let selectedRow: String?

    private var searchTarget: SearchTarget {
        SearchTarget(
            session: session.map(ObjectIdentifier.init), handlesSearch: session?.ui?.handlesSearch == true)
    }

    var body: some View {
        content
            .onChange(of: query) { coordinator.search(query) }
            .onChange(of: searchTarget) { _, target in
                guard target.handlesSearch, !query.isEmpty else { return }
                coordinator.search(query)
            }
            .onChange(of: selectedRow) { coordinator.select(selectedRow) }
    }

    @ViewBuilder
    private var content: some View {
        if let session, session.state != .gone {
            if let ui = session.ui {
                // One line until the trees are drawn: the type and the revision it came from.
                EmptyResults(text: "\(ui.typeName) · revision \(session.revision)", systemImage: Self.symbol)
            } else {
                EmptyResults(text: String(localized: "Loading…"), systemImage: Self.symbol)
            }
        } else {
            EmptyResults(text: String(localized: "This command stopped."), systemImage: Self.symbol)
        }
    }

    private static let symbol = "puzzlepiece.extension"
}
