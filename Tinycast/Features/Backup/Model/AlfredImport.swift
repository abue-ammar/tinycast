import Foundation

/// The independently importable categories in an Alfred preferences package.
struct AlfredImportOptions: OptionSet, Sendable {
    let rawValue: Int
    static let shortcuts = AlfredImportOptions(rawValue: 1 << 0)
    static let searchScope = AlfredImportOptions(rawValue: 1 << 1)
    static let snippets = AlfredImportOptions(rawValue: 1 << 2)
    static let quicklinks = AlfredImportOptions(rawValue: 1 << 3)
    static let workflows = AlfredImportOptions(rawValue: 1 << 4)
    static let all: AlfredImportOptions = [
        .shortcuts, .searchScope, .snippets, .quicklinks, .workflows
    ]
}

/// What an `Alfred.alfredpreferences` package yields, before it reaches the app.
/// See docs/features/alfred-import.md.
enum AlfredImport {
    /// A workflow that came over as a command, with the one chord it declared, if any.
    struct Command: Sendable {
        var command: CustomCommand
        var hotkey: HotKeyBinding?
    }

    struct Result: Sendable {
        var searchScopes: [String]?
        var paletteHotkey: HotKeyBinding?
        var clipboardHotkey: HotKeyBinding?
        var snippets: [Snippet]
        var quicklinks: [Quicklink]
        var commands: [Command]
        /// Workflows Tinycast cannot run, and the searches whose URL only Alfred knows.
        var skippedWorkflows: Int
        var skippedSearches: [String]

        /// Trimmed to the chosen categories; the applier being per-field, dropping is enough.
        func selecting(_ options: AlfredImportOptions) -> Result {
            let shortcuts = options.contains(.shortcuts)
            // A workflow's chord belongs to Shortcuts, not to the workflow category.
            let commands: [Command] =
                options.contains(.workflows)
                ? commands.map { entry in
                    var trimmed = entry
                    trimmed.hotkey = shortcuts ? entry.hotkey : nil
                    return trimmed
                } : []
            return Result(
                searchScopes: options.contains(.searchScope) ? searchScopes : nil,
                paletteHotkey: shortcuts ? paletteHotkey : nil,
                clipboardHotkey: shortcuts ? clipboardHotkey : nil,
                snippets: options.contains(.snippets) ? snippets : [],
                quicklinks: options.contains(.quicklinks) ? quicklinks : [],
                commands: commands,
                skippedWorkflows: options.contains(.workflows) ? skippedWorkflows : 0,
                skippedSearches: options.contains(.quicklinks) ? skippedSearches : [])
        }
    }

    /// Custom commands have no keyword field, so an invoked-by-keyword workflow stays typeable.
    static func named(_ title: String, keyword: String?) -> String {
        guard let keyword, !keyword.isEmpty,
            title.range(of: keyword, options: .caseInsensitive) == nil
        else { return title }
        return "\(title) (\(keyword))"
    }
}
