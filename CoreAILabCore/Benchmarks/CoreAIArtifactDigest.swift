import Foundation

struct CoreAIArtifactDigest: Codable, Sendable, Equatable {
    static let currentScheme = "CoreAIArtifactStore/v1"

    let scheme: String
    let sha256: String
    let kind: CoreAIArtifactKind
    let byteCount: Int64
    let fileCount: Int

    init(
        scheme: String = Self.currentScheme,
        sha256: String,
        kind: CoreAIArtifactKind,
        byteCount: Int64,
        fileCount: Int
    ) {
        self.scheme = scheme
        self.sha256 = sha256
        self.kind = kind
        self.byteCount = byteCount
        self.fileCount = fileCount
    }
}
