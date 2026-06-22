import Foundation

struct CoreAIDeviceArtifactIdentity: Codable, Equatable, Sendable {
    let identifier: String
    let sha256Digest: String
    let byteCount: UInt64

    func validate(path: String = "artifact") throws {
        try CoreAIManifestValidator.requireNonempty(identifier, path: "\(path).identifier")
        guard Self.isSHA256Digest(sha256Digest) else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).sha256Digest",
                reason: "expected 64 lowercase hexadecimal characters"
            )
        }
        guard byteCount > 0 else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).byteCount",
                reason: "it must be greater than zero"
            )
        }
    }

    static func isSHA256Digest(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
    }
}
