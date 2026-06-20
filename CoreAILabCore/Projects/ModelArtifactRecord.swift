import Foundation
import SwiftData

@Model
final class ModelArtifactRecord {
    @Attribute(.unique) var sha256Digest: String
    var storageRelativePath: String
    var originalFilename: String
    var kindRawValue: String
    var byteCount: Int64
    var fileCount: Int
    var importedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ProjectArtifactLink.artifact)
    var projectLinks: [ProjectArtifactLink]

    init(
        sha256Digest: String,
        storageRelativePath: String,
        originalFilename: String,
        kind: CoreAIArtifactKind,
        byteCount: Int64,
        fileCount: Int,
        importedAt: Date = .now,
        projectLinks: [ProjectArtifactLink] = []
    ) {
        self.sha256Digest = sha256Digest
        self.storageRelativePath = storageRelativePath
        self.originalFilename = originalFilename
        kindRawValue = kind.rawValue
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.importedAt = importedAt
        self.projectLinks = projectLinks
    }

    var kind: CoreAIArtifactKind {
        CoreAIArtifactKind(rawValue: kindRawValue) ?? .auxiliaryFile
    }

    var shortDigest: String {
        String(sha256Digest.prefix(12))
    }
}
