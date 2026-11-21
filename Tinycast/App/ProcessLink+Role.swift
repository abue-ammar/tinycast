import Foundation

extension ProcessLink {
    static func spawn(_ role: ProcessRole) throws -> ProcessLink {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        return try spawn(executable, arguments: [role.argument])
    }
}
