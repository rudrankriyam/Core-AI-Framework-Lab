import Foundation
import SwiftData

@Model
final class ModelArtifactRecord {
    @Attribute(.unique) private(set) var sha256Digest: String
    private(set) var storageRelativePath: String
    private(set) var originalFilename: String
    private(set) var kindRawValue: String
    private(set) var byteCount: Int64
    private(set) var fileCount: Int
    private(set) var importedAt: Date
    private(set) var resourceSnapshotData: Data?
    private(set) var descriptorSnapshotData: Data?
    private(set) var descriptorInspectedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ProjectArtifactLink.artifact)
    private(set) var projectLinks: [ProjectArtifactLink]

    init(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        sha256Digest: String,
        storageRelativePath: String,
        originalFilename: String,
        kind: CoreAIArtifactKind,
        byteCount: Int64,
        fileCount: Int,
        resourceSnapshotData: Data?,
        importedAt: Date = .now
    ) {
        self.sha256Digest = sha256Digest
        self.storageRelativePath = storageRelativePath
        self.originalFilename = originalFilename
        kindRawValue = kind.rawValue
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.resourceSnapshotData = resourceSnapshotData
        descriptorSnapshotData = nil
        descriptorInspectedAt = nil
        self.importedAt = importedAt
        projectLinks = []
    }

    var kind: CoreAIArtifactKind? {
        CoreAIArtifactKind(rawValue: kindRawValue)
    }

    var shortDigest: String {
        String(sha256Digest.prefix(12))
    }

    func decodedResourceSnapshot() throws -> CoreAIResourceFolderSnapshot? {
        guard let resourceSnapshotData else { return nil }
        let snapshot = try JSONDecoder().decode(
            CoreAIResourceFolderSnapshot.self,
            from: resourceSnapshotData
        )
        try snapshot.validate()
        guard snapshot.files.count == fileCount,
              snapshot.byteCount == byteCount else {
            throw CoreAIProjectLibraryError.inconsistentArtifactRecord
        }
        return snapshot
    }

    func decodedDescriptorSnapshot() throws -> CoreAIAssetDescriptorSnapshot? {
        guard let descriptorSnapshotData else { return nil }
        let snapshot = try JSONDecoder().decode(
            CoreAIAssetDescriptorSnapshot.self,
            from: descriptorSnapshotData
        )
        try snapshot.validate()
        return snapshot
    }

    func recordDescriptorSnapshot(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        data: Data,
        inspectedAt: Date = .now
    ) {
        descriptorSnapshotData = data
        descriptorInspectedAt = inspectedAt
    }

    func recordResourceSnapshot(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        data: Data
    ) {
        resourceSnapshotData = data
    }
}
