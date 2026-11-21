import Foundation

extension ProcessLink {
    /// A role speaks this build's messages, so it never starts from a file another build replaced.
    static func spawn(_ role: ProcessRole) throws -> ProcessLink {
        try LaunchedExecutable.checkUnchanged()
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        return try spawn(executable, arguments: [role.argument])
    }
}
