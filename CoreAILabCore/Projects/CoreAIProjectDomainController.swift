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
        summary: String? = nil,
        endedAt: Date? = nil,
        modelContext: ModelContext
    ) throws {
        guard let project = run.project else {
            throw CoreAIProjectLibraryError.projectUnavailable
        }
        guard let currentStatus = run.status else {
            throw CoreAIProjectLibraryError.runStatusUnavailable
        }
        guard currentStatus.canTransition(to: status) else {
            throw CoreAIProjectLibraryError.invalidRunStatusTransition(
                from: currentStatus,
                to: status
            )
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

    func finishRuntimeRun(
        _ run: CoreAIRunRecord,
        status: CoreAIRunStatus,
        summary: String,
        endedAt: Date,
        metricEvidence: CoreAIRuntimeMetricEvidence?,
        modelContext: ModelContext
    ) throws {
        guard status == .cancelled || status == .failed || status == .succeeded else {
            throw CoreAIProjectLibraryError.terminalRunRequiresUpdate
        }
        guard let project = run.project else {
            throw CoreAIProjectLibraryError.projectUnavailable
        }

        let encodedMetricMetadata = try metricEvidence.map {
            try encoded($0.metadata)
        }
        let alreadyHasMetric = metricEvidence.map { metric in
            run.evidence.contains { $0.id == metric.id }
        } ?? true
        if run.status == status,
           run.summary == summary,
           run.endedAt == endedAt,
           alreadyHasMetric {
            return
        }

        run.update(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            status: status,
            summary: summary,
            endedAt: endedAt
        )
        if let metricEvidence,
           let encodedMetricMetadata,
           !alreadyHasMetric {
            let evidence = CoreAIEvidenceRecord(
                authorization: CoreAIProjectDomainWriteAuthorization(),
                id: metricEvidence.id,
                kind: .metric,
                label: metricEvidence.label,
                summary: metricEvidence.summary,
                metadataData: encodedMetricMetadata,
                project: project,
                run: run
            )
            modelContext.insert(evidence)
        }
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

extension CoreAIProjectLibraryController: CoreAIProjectRunWriting {
    func createRuntimeRun(
        in project: LabProject,
        recipeRevision: CoreAIRecipeRevisionRecord?,
        provenanceEvidence: CoreAIRuntimeProvenanceEvidence,
        modelContext: ModelContext
    ) throws -> CoreAIRunRecord {
        if let recipeRevision {
            try requireSameProject(project, recordProject: recipeRevision.project)
        }
        let metadataData = try encoded(provenanceEvidence.metadata)
        let run = CoreAIRunRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            kind: .inference,
            status: .running,
            project: project,
            recipeRevision: recipeRevision
        )
        let evidence = CoreAIEvidenceRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            id: provenanceEvidence.id,
            kind: .validation,
            label: provenanceEvidence.label,
            summary: provenanceEvidence.summary,
            metadataData: metadataData,
            project: project,
            run: run
        )
        modelContext.insert(run)
        modelContext.insert(evidence)
        try saveDomainChange(project: project, modelContext: modelContext)
        return run
    }
}
