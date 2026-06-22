import Foundation
import SwiftData

enum CoreAIRunKind: String, Codable, CaseIterable, Sendable {
    case benchmark
    case conversion
    case export
    case inference
    case specialization
    case validation
}

enum CoreAIRunStatus: String, Codable, CaseIterable, Sendable {
    case cancelled
    case failed
    case pending
    case running
    case succeeded
}

@Model
final class CoreAIRunRecord {
    @Attribute(.unique) private(set) var id: UUID = UUID()
    private(set) var schemaVersion: Int = 1
    private(set) var kindRawValue: String = CoreAIRunKind.inference.rawValue
    private(set) var statusRawValue: String = CoreAIRunStatus.pending.rawValue
    private(set) var summary: String = ""
    private(set) var startedAt: Date = Date.now
    private(set) var endedAt: Date?
    private(set) var project: LabProject?
    private(set) var recipeRevision: CoreAIRecipeRevisionRecord?
    private(set) var targetProfile: CoreAITargetProfileRecord?

    @Relationship(deleteRule: .nullify, inverse: \CoreAIEvidenceRecord.run)
    private(set) var evidence: [CoreAIEvidenceRecord] = []

    init(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        kind: CoreAIRunKind,
        status: CoreAIRunStatus = .pending,
        summary: String = "",
        startedAt: Date = .now,
        endedAt: Date? = nil,
        project: LabProject? = nil,
        recipeRevision: CoreAIRecipeRevisionRecord? = nil,
        targetProfile: CoreAITargetProfileRecord? = nil,
        evidence: [CoreAIEvidenceRecord] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        kindRawValue = kind.rawValue
        statusRawValue = status.rawValue
        self.summary = summary
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.project = project
        self.recipeRevision = recipeRevision
        self.targetProfile = targetProfile
        self.evidence = evidence
    }

    var kind: CoreAIRunKind? {
        CoreAIRunKind(rawValue: kindRawValue)
    }

    var status: CoreAIRunStatus? {
        CoreAIRunStatus(rawValue: statusRawValue)
    }

    func update(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        status: CoreAIRunStatus,
        summary: String,
        endedAt: Date?
    ) {
        statusRawValue = status.rawValue
        self.summary = summary
        self.endedAt = endedAt
    }
}
