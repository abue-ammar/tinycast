import Foundation

struct WindowCommand: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case leftHalf = "left-half"
        case rightHalf = "right-half"
        case topHalf = "top-half"
        case bottomHalf = "bottom-half"
        case topLeftQuarter = "top-left-quarter"
        case topRightQuarter = "top-right-quarter"
        case bottomLeftQuarter = "bottom-left-quarter"
        case bottomRightQuarter = "bottom-right-quarter"
        case firstThreeFourths = "first-three-fourths"
        case lastThreeFourths = "last-three-fourths"
        case firstThird = "first-third"
        case centerThird = "center-third"
        case lastThird = "last-third"
        case firstTwoThirds = "first-two-thirds"
        case lastTwoThirds = "last-two-thirds"
        case maximize
        case almostMaximize = "almost-maximize"
        case reasonableSize = "reasonable-size"
        case maximizeHeight = "maximize-height"
        case maximizeWidth = "maximize-width"
        case center
        case centerHalf = "center-half"
        case makeLarger = "make-larger"
        case makeSmaller = "make-smaller"
        case restore
        case moveLeft = "move-left"
        case moveRight = "move-right"
        case moveUp = "move-up"
        case moveDown = "move-down"
        case nextDisplay = "next-display"
        case previousDisplay = "previous-display"
        case toggleFullscreen = "toggle-fullscreen"
        case previousSpace = "previous-space"
        case nextSpace = "next-space"
        case restoreWorkspace = "restore-workspace"
    }

    /// What the mover has to do, so its dispatch stays exhaustive over the catalog.
    enum Kind: String, Sendable {
        /// Resolve a target frame from the screen and write it.
        case geometry
        /// Geometry too, but sourced from the recorded pre-action frame rather than computed.
        case restore
        /// No geometry at all — the native `AXFullScreen` toggle.
        case fullscreen
        /// No window at all — a synthetic Dock gesture that moves between Spaces.
        case space
        /// Restore the workspace selected in Settings.
        case workspace
    }

    /// The launcher section a command belongs to, and the order the Settings panel lists them in.
    enum Group: String, CaseIterable, Sendable {
        case halves
        case quarters
        case fourths
        case thirds
        case sizing
        case moving
        case fullscreen
        case spaces
        case workspaces

        var title: String {
            switch self {
            case .halves: return "Halves"
            case .quarters: return "Quarters"
            case .fourths: return "Fourths"
            case .thirds: return "Thirds"
            case .sizing: return "Sizing"
            case .moving: return "Moving"
            case .fullscreen: return "Fullscreen"
            case .spaces: return "Spaces"
            case .workspaces: return "Workspaces"
            }
        }
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let kind: Kind
    let group: Group
    /// Only the four halves cycle ½ → ⅓ → ⅔; the rest ignore the step they are handed.
    let cyclesOnRepeat: Bool
    /// False for the nudges, so the mover never writes `kAXSizeAttribute` for them.
    let resizes: Bool

    var entryID: String { "window-command:" + id.rawValue }
}

enum WindowCommandCatalog {
    static let all: [WindowCommand] = WindowCommand.ID.allCases.map { id in
        WindowCommand(
            id: id, name: name(for: id), sfSymbol: symbol(for: id), kind: kind(for: id),
            group: group(for: id), cyclesOnRepeat: cyclesOnRepeat.contains(id),
            resizes: !movesOnly.contains(id))
    }

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })

    static func command(id: WindowCommand.ID) -> WindowCommand? { byID[id] }

    static func command(forEntryID entryID: String) -> WindowCommand? { byEntryID[entryID] }

    /// Catalog order grouped for Settings; `ID.allCases` is in group order, so this partitions.
    static func grouped() -> [(group: WindowCommand.Group, commands: [WindowCommand])] {
        WindowCommand.Group.allCases.compactMap { group in
            let commands = all.filter { $0.group == group }
            return commands.isEmpty ? nil : (group, commands)
        }
    }

    static let cyclesOnRepeat: Set<WindowCommand.ID> = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf
    ]

    /// Nudges reposition without ever touching the size.
    static let movesOnly: Set<WindowCommand.ID> = [.moveLeft, .moveRight, .moveUp, .moveDown]

    private static func name(for id: WindowCommand.ID) -> String {
        switch id {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeftQuarter: return "Top Left Quarter"
        case .topRightQuarter: return "Top Right Quarter"
        case .bottomLeftQuarter: return "Bottom Left Quarter"
        case .bottomRightQuarter: return "Bottom Right Quarter"
        case .firstThreeFourths: return "First Three Fourths"
        case .lastThreeFourths: return "Last Three Fourths"
        case .firstThird: return "First Third"
        case .centerThird: return "Center Third"
        case .lastThird: return "Last Third"
        case .firstTwoThirds: return "First Two Thirds"
        case .lastTwoThirds: return "Last Two Thirds"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .reasonableSize: return "Reasonable Size"
        case .maximizeHeight: return "Maximize Height"
        case .maximizeWidth: return "Maximize Width"
        case .center: return "Center"
        case .centerHalf: return "Center Half"
        case .makeLarger: return "Make Larger"
        case .makeSmaller: return "Make Smaller"
        case .restore: return "Restore Window"
        case .moveLeft: return "Move Left"
        case .moveRight: return "Move Right"
        case .moveUp: return "Move Up"
        case .moveDown: return "Move Down"
        case .nextDisplay: return "Move to Next Display"
        case .previousDisplay: return "Move to Previous Display"
        case .toggleFullscreen: return "Toggle Fullscreen"
        case .previousSpace: return "Switch to Previous Space"
        case .nextSpace: return "Switch to Next Space"
        case .restoreWorkspace: return "Restore Workspace"
        }
    }

    private static func symbol(for id: WindowCommand.ID) -> String {
        switch id {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeftQuarter: return "rectangle.inset.topleading.filled"
        case .topRightQuarter: return "rectangle.inset.toptrailing.filled"
        case .bottomLeftQuarter: return "rectangle.inset.bottomleading.filled"
        case .bottomRightQuarter: return "rectangle.inset.bottomtrailing.filled"
        case .firstThreeFourths: return "rectangle.lefthalf.inset.filled"
        case .lastThreeFourths: return "rectangle.righthalf.inset.filled"
        case .firstThird, .firstTwoThirds: return "rectangle.leadingthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .lastThird, .lastTwoThirds: return "rectangle.trailingthird.inset.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .almostMaximize: return "rectangle.inset.filled"
        case .reasonableSize: return "macwindow"
        case .maximizeHeight: return "arrow.up.and.down"
        case .maximizeWidth: return "arrow.left.and.right"
        case .center: return "rectangle.center.inset.filled"
        case .centerHalf: return "rectangle.split.3x1"
        case .makeLarger: return "plus.magnifyingglass"
        case .makeSmaller: return "minus.magnifyingglass"
        case .restore: return "arrow.uturn.backward"
        case .moveLeft: return "arrow.left"
        case .moveRight: return "arrow.right"
        case .moveUp: return "arrow.up"
        case .moveDown: return "arrow.down"
        case .nextDisplay: return "rectangle.on.rectangle.angled"
        case .previousDisplay: return "rectangle.on.rectangle.angled"
        case .toggleFullscreen: return "arrow.up.left.and.arrow.down.right.square"
        case .previousSpace: return "chevron.backward.2"
        case .nextSpace: return "chevron.forward.2"
        case .restoreWorkspace: return "square.3.layers.3d.top.filled"
        }
    }

    private static func kind(for id: WindowCommand.ID) -> WindowCommand.Kind {
        switch id {
        case .restore: return .restore
        case .toggleFullscreen: return .fullscreen
        case .previousSpace, .nextSpace: return .space
        case .restoreWorkspace: return .workspace
        default: return .geometry
        }
    }

    private static func group(for id: WindowCommand.ID) -> WindowCommand.Group {
        switch id {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            return .halves
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return .quarters
        case .firstThreeFourths, .lastThreeFourths:
            return .fourths
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
            return .thirds
        case .maximize, .almostMaximize, .reasonableSize, .maximizeHeight, .maximizeWidth, .center,
            .centerHalf, .makeLarger, .makeSmaller, .restore:
            return .sizing
        case .moveLeft, .moveRight, .moveUp, .moveDown, .nextDisplay, .previousDisplay:
            return .moving
        case .toggleFullscreen:
            return .fullscreen
        case .previousSpace, .nextSpace:
            return .spaces
        case .restoreWorkspace:
            return .workspaces
        }
    }
}
