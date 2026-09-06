import Foundation

/// One screen's restorable state, snapshotted when another screen is pushed over it.
struct PaletteFrame: Equatable {
    var mode: PaletteMode
    var query: String
    var selection: Int
    var clipboardFilter: ClipboardFilter
}

/// The screens under the current one, bottom first. Empty means the current screen is the root.
struct PaletteNavigationStack: Equatable {
    private(set) var parents: [PaletteFrame] = []

    var canGoBack: Bool { !parents.isEmpty }

    mutating func push(_ current: PaletteFrame) {
        parents.append(current)
    }

    mutating func pop() -> PaletteFrame? {
        parents.popLast()
    }

    mutating func reset() {
        parents.removeAll()
    }
}
