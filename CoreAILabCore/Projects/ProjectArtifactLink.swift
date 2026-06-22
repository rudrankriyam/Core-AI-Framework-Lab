import Foundation
import SwiftData

@Model
final class ProjectArtifactLink {
    @Attribute(.unique) private(set) var id: UUID
    private(set) var displayName: String
    private(set) var addedAt: Date
    private(set) var project: LabProject?
    private(set) var artifact: ModelArtifactRecord?

    @Relationship(deleteRule: .cascade, inverse: \CoreAISourceProvenanceRecord.artifactLink)
    private(set) var provenance: CoreAISourceProvenanceRecord?

    @Relationship(deleteRule: .cascade, inverse: \CoreAISpecializationCacheRecord.artifactLink)
    private(set) var specializationCaches: [CoreAISpecializationCacheRecord] = []

    init(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        id: UUID = UUID(),
        displayName: String,
        addedAt: Date = .now,
        project: LabProject? = nil,
        artifact: ModelArtifactRecord? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.addedAt = addedAt
        self.project = project
        self.artifact = artifact
        provenance = nil
        specializationCaches = []
    }

    var sortedSpecializationCaches: [CoreAISpecializationCacheRecord] {
        specializationCaches.sorted { first, second in
            if first.lastUsedAt != second.lastUsedAt {
                return first.lastUsedAt > second.lastUsedAt
            }
            return first.configurationTitle < second.configurationTitle
        }
    }

    func attachProvenance(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        _ provenance: CoreAISourceProvenanceRecord
    ) {
        self.provenance = provenance
    }
}
