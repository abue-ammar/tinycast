import Foundation

/// What `closeMainWindow` and `showHUD` ask of the palette they close, read from their options.
struct ExtensionWindowClose: Equatable, Sendable {
    /// `PopToRootType`, spelled as the API's raw values.
    enum PopToRoot: String, Sendable {
        case `default`
        case immediate
        case suspended
    }

    let clearsRootSearch: Bool
    let popToRoot: PopToRoot

    /// A paste or a copy closes the way an extension passing no options would.
    static let standard = ExtensionWindowClose(clearsRootSearch: false, popToRoot: .default)

    init(clearsRootSearch: Bool, popToRoot: PopToRoot) {
        self.clearsRootSearch = clearsRootSearch
        self.popToRoot = popToRoot
    }

    /// An unknown `popToRootType` falls back to the user's own Pop to Root Search setting.
    init(options: [String: RenderValue]) {
        clearsRootSearch = options["clearRootSearch"]?.boolValue ?? false
        popToRoot = options["popToRootType"]?.stringValue.flatMap(PopToRoot.init) ?? .default
    }
}
