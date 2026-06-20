import Foundation
import SwiftData

@Model
final class LabProject {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var name: String
    var projectDescription: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ProjectArtifactLink.project)
    var artifactLinks: [ProjectArtifactLink]

    init(
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        name: String,
        projectDescription: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastOpenedAt: Date = .now,
        artifactLinks: [ProjectArtifactLink] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.projectDescription = projectDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.artifactLinks = artifactLinks
    }

    var sortedArtifactLinks: [ProjectArtifactLink] {
        artifactLinks.sorted { first, second in
            if first.addedAt != second.addedAt {
                return first.addedAt > second.addedAt
            }
            return first.displayName.localizedStandardCompare(second.displayName)
                == .orderedAscending
        }
    }

    var storedByteCount: Int64 {
        artifactLinks.reduce(into: 0) { total, link in
            guard let artifact = link.artifact else { return }
            let (updatedTotal, overflow) = total.addingReportingOverflow(
                artifact.byteCount
            )
            total = overflow ? Int64.max : updatedTotal
        }
    }
}
