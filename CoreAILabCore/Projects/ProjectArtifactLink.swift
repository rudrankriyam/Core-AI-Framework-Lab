import Foundation
import SwiftData

@Model
final class ProjectArtifactLink {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var addedAt: Date
    var project: LabProject?
    var artifact: ModelArtifactRecord?

    init(
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
    }
}
