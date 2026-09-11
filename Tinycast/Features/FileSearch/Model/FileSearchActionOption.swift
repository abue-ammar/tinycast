import Foundation

enum FileSearchActionOption: String, CaseIterable, Identifiable, Sendable {
    case open = "open"
    case showInFinder = "showInFinder"
    case quickLook = "quickLook"
    case showInfoInFinder = "showInfoInFinder"
    case toggleInfoPanel = "toggleInfoPanel"
    case copyFile = "copyFile"
    case copyName = "copyName"
    case copyPath = "copyPath"
    case saveAsQuicklink = "saveAsQuicklink"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open File"
        case .showInFinder: "Show in Finder"
        case .quickLook: "Quick Look"
        case .showInfoInFinder: "Show Info in Finder"
        case .toggleInfoPanel: "Toggle Preview Panel"
        case .copyFile: "Copy File"
        case .copyName: "Copy Name"
        case .copyPath: "Copy Path"
        case .saveAsQuicklink: "Save as Quicklink"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "arrow.turn.down.left"
        case .showInFinder: "folder"
        case .quickLook: "eye"
        case .showInfoInFinder: "info.circle"
        case .toggleInfoPanel: "sidebar.right"
        case .copyFile: "doc.on.doc"
        case .copyName: "doc.text"
        case .copyPath: "doc.on.clipboard"
        case .saveAsQuicklink: "link"
        }
    }

    var defaultShortcut: String? {
        switch self {
        case .open: "↵"
        case .showInFinder: "⌘↵"
        case .quickLook: "⌘Y"
        case .showInfoInFinder: "⌥⌘I"
        case .toggleInfoPanel: "⌘I"
        case .copyFile: "⇧⌘C"
        case .copyName: "⌥⌘C"
        case .copyPath: nil
        case .saveAsQuicklink: "⌘S"
        }
    }
}
