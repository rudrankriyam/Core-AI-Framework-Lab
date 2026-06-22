import Foundation

struct CoreAIResourceFileSnapshot: Codable, Equatable, Sendable {
    let relativePath: String
    let sha256Digest: String
    let byteCount: Int64

    func validate(path: String) throws {
        try CoreAIManifestValidator.requireSafeRelativePath(
            relativePath,
            path: "\(path).relativePath"
        )
        guard sha256Digest.count == 64,
              sha256Digest.allSatisfy({ $0.isHexDigit }),
              sha256Digest == sha256Digest.lowercased() else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "\(path).sha256Digest",
                reason: "expected a lowercase SHA-256 digest"
            )
        }
        guard byteCount >= 0 else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "\(path).byteCount",
                reason: "must not be negative"
            )
        }
    }
}
