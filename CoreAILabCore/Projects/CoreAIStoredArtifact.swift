import Foundation

struct CoreAIStoredArtifact: Equatable, Sendable {
    let sha256Digest: String
    let storageRelativePath: String
    let originalFilename: String
    let kind: CoreAIArtifactKind
    let byteCount: Int64
    let fileCount: Int
    let wasAlreadyStored: Bool
}
