import Foundation

struct CoreAIDeviceEvidenceExpectation: Equatable, Sendable {
    let artifact: CoreAIDeviceArtifactIdentity
    let configurationIdentifier: String
    let configurationSHA256Digest: String

    func validate(path: String = "evidenceExpectation") throws {
        try artifact.validate(path: "\(path).artifact")
        try CoreAIManifestValidator.requireNonempty(
            configurationIdentifier,
            path: "\(path).configurationIdentifier"
        )
        guard CoreAIDeviceArtifactIdentity.isSHA256Digest(
            configurationSHA256Digest
        ) else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).configurationSHA256Digest",
                reason: "expected 64 lowercase hexadecimal characters"
            )
        }
    }

    func matches(_ evidence: CoreAIDeviceTrialEvidence) -> Bool {
        artifact == evidence.artifact
            && configurationIdentifier == evidence.configuration.identifier
            && configurationSHA256Digest
                == evidence.configuration.sha256Digest
    }
}
