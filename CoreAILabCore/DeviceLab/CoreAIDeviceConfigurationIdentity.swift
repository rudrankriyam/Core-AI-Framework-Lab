import Foundation

struct CoreAIDeviceConfigurationIdentity: Codable, Equatable, Sendable {
    let identifier: String
    let sha256Digest: String
    let preferredComputeUnit: CoreAIComputeUnitPreference
    let expectsFrequentReshapes: Bool
    let contextTokens: Int?
    let staticInputShapes: [String: [Int]]

    func validate(path: String = "configuration") throws {
        try CoreAIManifestValidator.requireNonempty(identifier, path: "\(path).identifier")
        guard CoreAIDeviceArtifactIdentity.isSHA256Digest(sha256Digest) else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).sha256Digest",
                reason: "expected 64 lowercase hexadecimal characters"
            )
        }
        try Self.validateShapeConfiguration(
            contextTokens: contextTokens,
            staticInputShapes: staticInputShapes,
            path: path
        )
    }

    static func validateShapeConfiguration(
        contextTokens: Int?,
        staticInputShapes: [String: [Int]],
        path: String
    ) throws {
        try CoreAIDeviceShapeLimits.validate(
            contextTokens: contextTokens,
            staticInputShapes: staticInputShapes,
            path: path
        )
    }
}
