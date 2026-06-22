import Foundation
import SwiftData

struct CoreAIProjectDomainWriteAuthorization {
    fileprivate init() {}
}

extension CoreAIProjectLibraryController {
    @discardableResult
    func addRecipeRevision(
        _ manifest: CoreAIRecipeManifest,
        to project: LabProject,
        modelContext: ModelContext
    ) throws -> CoreAIRecipeRevisionRecord {
        try manifest.validate()
        let record = CoreAIRecipeRevisionRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            recipeIdentifier: manifest.id,
            recipeRevision: manifest.revision,
            displayName: manifest.displayName,
            manifestData: try encoded(manifest),
            project: project
        )
        modelContext.insert(record)
        try saveDomainChange(project: project, modelContext: modelContext)
        return record
    }

    @discardableResult
    func addTargetProfile(
        _ manifest: CoreAITargetManifest,
        to project: LabProject,
        modelContext: ModelContext
    ) throws -> CoreAITargetProfileRecord {
        try manifest.validate()
        let record = CoreAITargetProfileRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            targetIdentifier: manifest.id,
            displayName: manifest.displayName,
            platform: manifest.platform,
            preferredComputeUnit: manifest.preferredComputeUnit,
            manifestData: try encoded(manifest),
            project: project
        )
        modelContext.insert(record)
        try saveDomainChange(project: project, modelContext: modelContext)
        return record
    }

    @discardableResult
    func createRun(
        kind: CoreAIRunKind,
        status: CoreAIRunStatus = .pending,
        in project: LabProject,
        recipeRevision: CoreAIRecipeRevisionRecord? = nil,
        targetProfile: CoreAITargetProfileRecord? = nil,
        modelContext: ModelContext
    ) throws -> CoreAIRunRecord {
        guard status == .pending || status == .running else {
            throw CoreAIProjectLibraryError.terminalRunRequiresUpdate
        }
        if let recipeRevision {
            try requireSameProject(project, recordProject: recipeRevision.project)
        }
        if let targetProfile {
            try requireSameProject(project, recordProject: targetProfile.project)
        }
        let record = CoreAIRunRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            kind: kind,
            status: status,
            project: project,
            recipeRevision: recipeRevision,
            targetProfile: targetProfile
        )
        modelContext.insert(record)
        try saveDomainChange(project: project, modelContext: modelContext)
        return record
    }

    func updateRun(
        _ run: CoreAIRunRecord,
        status: CoreAIRunStatus,
        summary: String = "",
        endedAt: Date? = nil,
        modelContext: ModelContext
    ) throws {
        guard let project = run.project else {
            throw CoreAIProjectLibraryError.projectUnavailable
        }
        let resolvedEndedAt: Date? = switch status {
        case .cancelled, .failed, .succeeded:
            endedAt ?? .now
        case .pending, .running:
            nil
        }
        run.update(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            status: status,
            summary: summary,
            endedAt: resolvedEndedAt
        )
        try saveDomainChange(project: project, modelContext: modelContext)
    }

    @discardableResult
    func recordEvidence(
        kind: CoreAIEvidenceKind,
        label proposedLabel: String,
        summary: String = "",
        relativePath: String? = nil,
        sha256Digest: String? = nil,
        mediaType: String? = nil,
        metadata: [String: String] = [:],
        for run: CoreAIRunRecord,
        modelContext: ModelContext
    ) throws -> CoreAIEvidenceRecord {
        guard let project = run.project else {
            throw CoreAIProjectLibraryError.projectUnavailable
        }
        let label = proposedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            throw CoreAIProjectLibraryError.evidenceLabelRequired
        }
        if let relativePath {
            try CoreAIManifestValidator.requireSafeRelativePath(
                relativePath,
                path: "evidence.relativePath"
            )
        }
        let record = CoreAIEvidenceRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            kind: kind,
            label: label,
            summary: summary,
            relativePath: relativePath,
            sha256Digest: sha256Digest,
            mediaType: mediaType,
            metadataData: try encoded(metadata),
            project: project,
            run: run
        )
        modelContext.insert(record)
        try saveDomainChange(project: project, modelContext: modelContext)
        return record
    }

    private func saveDomainChange(
        project: LabProject,
        modelContext: ModelContext
    ) throws {
        project.updatedAt = .now
        do {
            try modelContext.save()
            clearError()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func requireSameProject(
        _ project: LabProject,
        recordProject: LabProject?
    ) throws {
        guard recordProject?.id == project.id else {
            throw CoreAIProjectLibraryError.domainRecordProjectMismatch
        }
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
