import SwiftUI

/// The camera inside the palette. ↵ takes the photo; ⌘K holds Mirror and Switch Camera.
struct CameraScreen: PaletteScreen {
    struct Row: Identifiable {
        let id: String
    }

    let coordinator: CameraCoordinator

    private var isLive: Bool {
        if case .live = coordinator.feed { return true }
        return false
    }

    /// No rows and no visible field: the stage is the whole screen, and ↵ and ⌘K act on it.
    var rows: [Row] { [] }
    var drawsSearchField: Bool { false }
    var actsWithoutRows: Bool { true }

    var primaryActionTitle: String { "Take Photo" }

    func hasPrimaryAction(at selection: Int) -> Bool { isLive }

    func hasActions(at selection: Int) -> Bool { isLive }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard isLive else { return nil }
        var items = [
            PopoverMenuItem(
                title: coordinator.mirrored ? "Turn Mirroring Off" : "Turn Mirroring On",
                systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right"
            ) { [coordinator] in
                coordinator.mirrored.toggle()
            }
        ]
        if coordinator.canSwitchCamera {
            items.append(
                PopoverMenuItem(
                    title: "Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera"
                ) { [coordinator] in
                    coordinator.switchCamera()
                })
        }
        return PopoverMenuContent(items: items)
    }

    func activate(at selection: Int) {
        coordinator.takePhoto()
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(CameraView(coordinator: coordinator))
    }
}
