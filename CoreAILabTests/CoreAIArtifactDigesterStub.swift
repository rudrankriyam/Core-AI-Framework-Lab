import Foundation
@testable import CoreAILab

struct CoreAIArtifactDigesterStub: CoreAIArtifactDigesting {
    let artifactDigest: CoreAIArtifactDigest

    init(
        artifactDigest: CoreAIArtifactDigest = CoreAIArtifactDigest(
            sha256: String(repeating: "a", count: 64),
            kind: .modelAsset,
            byteCount: 13,
            fileCount: 2
        )
    ) {
        self.artifactDigest = artifactDigest
    }

    func digest(at url: URL) async throws -> CoreAIArtifactDigest {
        artifactDigest
    }
}
