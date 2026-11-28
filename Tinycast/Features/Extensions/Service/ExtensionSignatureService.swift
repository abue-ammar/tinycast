import Foundation
import Security

/// The trust chain's last link: Developer ID, Tinycast's team and the extension's fixed identifier.
nonisolated struct ExtensionSignatureService: Sendable {
    enum Failure: Error, Equatable {
        /// Info.plist names no extensions team, so nothing runs until it does.
        case noTeamID
        case invalidID
        case invalidSignature(OSStatus)
    }

    static let identifierPrefix = "com.abueammar.tinycast.ext."

    private let teamID: String?

    init(teamID: String? = Bundle.main.object(forInfoDictionaryKey: "TinycastExtensionsTeamID") as? String) {
        self.teamID = teamID
    }

    func verify(_ bundle: URL, id: String) throws(Failure) {
        guard let teamID, teamID.wholeMatch(of: /[A-Z0-9]{10}/) != nil else { throw .noTeamID }
        // Both go into the requirement's text, so neither may carry a quote or an operator.
        guard id.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil else { throw .invalidID }
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(bundle as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw .invalidSignature(status) }
        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(
            Self.requirement(teamID: teamID, id: id) as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else { throw .invalidSignature(status) }
        status = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement)
        guard status == errSecSuccess else { throw .invalidSignature(status) }
    }

    /// Developer ID: Apple's intermediate for it and its leaf marker, as Gatekeeper reads them.
    private static func requirement(teamID: String, id: String) -> String {
        """
        anchor apple generic and identifier "\(identifierPrefix)\(id)" \
        and certificate leaf[subject.OU] = "\(teamID)" \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
        """
    }
}
