import Foundation
import SwiftData

@Model
final class CoreAISourceProvenanceRecord {
    @Attribute(.unique) private(set) var id: UUID
    private(set) var kindRawValue: String
    private(set) var sourceLocation: String
    private(set) var providerName: String
    private(set) var licenseName: String
    private(set) var notes: String
    private(set) var updatedAt: Date
    private(set) var artifactLink: ProjectArtifactLink?

    init(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        id: UUID = UUID(),
        kind: CoreAISourceProvenanceKind,
        sourceLocation: String,
        providerName: String = "",
        licenseName: String = "",
        notes: String = "",
        updatedAt: Date = .now,
        artifactLink: ProjectArtifactLink? = nil
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.sourceLocation = sourceLocation
        self.providerName = providerName
        self.licenseName = licenseName
        self.notes = notes
        self.updatedAt = updatedAt
        self.artifactLink = artifactLink
    }

    var kind: CoreAISourceProvenanceKind? {
        CoreAISourceProvenanceKind(rawValue: kindRawValue)
    }

    func update(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        kind: CoreAISourceProvenanceKind,
        sourceLocation: String,
        providerName: String,
        licenseName: String,
        notes: String
    ) {
        kindRawValue = kind.rawValue
        self.sourceLocation = sourceLocation
        self.providerName = providerName
        self.licenseName = licenseName
        self.notes = notes
        updatedAt = .now
    }
}
