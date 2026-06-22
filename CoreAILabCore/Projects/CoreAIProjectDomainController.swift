import Foundation
import SwiftData

struct CoreAIProjectDomainWriteAuthorization {
    fileprivate init() {}
}

extension CoreAIProjectLibraryController {
    func persistImportedArtifact(
        _ storedArtifact: CoreAIStoredArtifact,
        sourceURL: URL,
        projectID: UUID,
        modelContext: ModelContext
    ) throws -> ProjectArtifactLink {
        try validateImportedArtifact(storedArtifact, sourceURL: sourceURL)
        guard let project = try domainProject(id: projectID, modelContext: modelContext) else {
            throw CoreAIProjectLibraryError.projectUnavailable
        }

        let existingRecord = try domainArtifactRecord(
            sha256Digest: storedArtifact.sha256Digest,
            modelContext: modelContext
        )
        if let existingRecord,
           existingRecord.storageRelativePath != storedArtifact.storageRelativePath {
            throw CoreAIProjectLibraryError.inconsistentArtifactRecord
        }
        let resourceSnapshotData = try storedArtifact.resourceSnapshot.map(encoded)
        if let existingRecord {
            guard existingRecord.byteCount == storedArtifact.byteCount,
                  existingRecord.fileCount == storedArtifact.fileCount,
                  existingRecord.kind == storedArtifact.kind else {
                throw CoreAIProjectLibraryError.inconsistentArtifactRecord
            }
            if let resourceSnapshotData,
               existingRecord.resourceSnapshotData == nil {
                existingRecord.recordResourceSnapshot(
                    authorization: CoreAIProjectDomainWriteAuthorization(),
                    data: resourceSnapshotData
                )
            }
            if let existingSnapshot = try existingRecord.decodedResourceSnapshot(),
               existingSnapshot != storedArtifact.resourceSnapshot {
                throw CoreAIProjectLibraryError.inconsistentArtifactRecord
            }
        }
        if let existingLink = try domainArtifactLinks(
            sha256Digest: storedArtifact.sha256Digest,
            modelContext: modelContext
        ).first(where: { $0.project?.id == projectID }) {
            if existingLink.provenance == nil {
                let provenance = importedProvenance(
                    sourceURL: sourceURL,
                    link: existingLink
                )
                modelContext.insert(provenance)
                existingLink.attachProvenance(
                    authorization: CoreAIProjectDomainWriteAuthorization(),
                    provenance
                )
            }
            try saveDomainChange(project: project, modelContext: modelContext)
            return existingLink
        }

        let record = existingRecord ?? ModelArtifactRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            sha256Digest: storedArtifact.sha256Digest,
            storageRelativePath: storedArtifact.storageRelativePath,
            originalFilename: storedArtifact.originalFilename,
            kind: storedArtifact.kind,
            byteCount: storedArtifact.byteCount,
            fileCount: storedArtifact.fileCount,
            resourceSnapshotData: resourceSnapshotData
        )
        let link = ProjectArtifactLink(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            displayName: sourceURL.lastPathComponent,
            project: project,
            artifact: record
        )
        let provenance = importedProvenance(sourceURL: sourceURL, link: link)
        link.attachProvenance(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            provenance
        )
        if existingRecord == nil {
            modelContext.insert(record)
        }
        modelContext.insert(link)
        modelContext.insert(provenance)
        try saveDomainChange(project: project, modelContext: modelContext)
        return link
    }

    func recordDescriptorSnapshot(
        _ report: CoreAIModelAssetReport,
        for link: ProjectArtifactLink,
        modelContext: ModelContext
    ) throws {
        guard let currentLink = try domainArtifactLink(id: link.id, modelContext: modelContext),
              let project = currentLink.project,
              let artifact = currentLink.artifact else {
            throw CoreAIProjectLibraryError.artifactUnavailable
        }
        guard artifact.kind == .modelAsset else {
            throw CoreAIProjectLibraryError.modelAssetRequired
        }
        let expectedURL = try validatedStoredURL(for: artifact).standardizedFileURL
        guard report.url.standardizedFileURL == expectedURL else {
            throw CoreAIProjectLibraryError.descriptorSourceMismatch
        }
        let snapshot = CoreAIAssetDescriptorSnapshot(report: report)
        try snapshot.validate()
        artifact.recordDescriptorSnapshot(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            data: try encoded(snapshot)
        )
        try saveDomainChange(project: project, modelContext: modelContext)
    }

    func updateSourceProvenance(
        for link: ProjectArtifactLink,
        kind: CoreAISourceProvenanceKind,
        sourceLocation proposedSourceLocation: String,
        providerName proposedProviderName: String,
        licenseName proposedLicenseName: String,
        notes proposedNotes: String,
        modelContext: ModelContext
    ) throws {
        guard let currentLink = try domainArtifactLink(id: link.id, modelContext: modelContext),
              let project = currentLink.project,
              currentLink.artifact != nil else {
            throw CoreAIProjectLibraryError.artifactUnavailable
        }
        let sourceLocation = proposedSourceLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let providerName = proposedProviderName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let licenseName = proposedLicenseName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let notes = proposedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateProvenance(
            kind: kind,
            sourceLocation: sourceLocation,
            providerName: providerName,
            licenseName: licenseName,
            notes: notes
        )

        if let provenance = currentLink.provenance {
            provenance.update(
                authorization: CoreAIProjectDomainWriteAuthorization(),
                kind: kind,
                sourceLocation: sourceLocation,
                providerName: providerName,
                licenseName: licenseName,
                notes: notes
            )
        } else {
            let provenance = CoreAISourceProvenanceRecord(
                authorization: CoreAIProjectDomainWriteAuthorization(),
                kind: kind,
                sourceLocation: sourceLocation,
                providerName: providerName,
                licenseName: licenseName,
                notes: notes,
                artifactLink: currentLink
            )
            modelContext.insert(provenance)
            currentLink.attachProvenance(
                authorization: CoreAIProjectDomainWriteAuthorization(),
                provenance
            )
        }
        try saveDomainChange(project: project, modelContext: modelContext)
    }

    func recordSpecializationCache(
        _ result: CoreAISpecializationResult,
        sourceURL: URL,
        for link: ProjectArtifactLink,
        modelContext: ModelContext
    ) async throws {
        let linkID = link.id
        try await performSerializedStorageMutation {
            guard let currentLink = try domainArtifactLink(
                id: linkID,
                modelContext: modelContext
            ),
                  let project = currentLink.project,
                  let artifact = currentLink.artifact else {
                throw CoreAIProjectLibraryError.artifactUnavailable
            }
            guard artifact.kind == .modelAsset else {
                throw CoreAIProjectLibraryError.modelAssetRequired
            }
            let expectedURL = try validatedStoredURL(for: artifact).standardizedFileURL
            guard sourceURL.standardizedFileURL == expectedURL else {
                throw CoreAIProjectLibraryError.descriptorSourceMismatch
            }
            try upsertSpecializationCacheRecord(
                result,
                project: project,
                link: currentLink,
                modelContext: modelContext
            )
        }
    }

    @discardableResult
    func addRecipeRevision(
        _ manifest: CoreAIRecipeManifest,
        to project: LabProject,
        modelContext: ModelContext
    ) throws -> CoreAIRecipeRevisionRecord {
        try manifest.validate()
        let currentProject = try requireDomainProject(project, modelContext: modelContext)
        let record = CoreAIRecipeRevisionRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            recipeIdentifier: manifest.id,
            recipeRevision: manifest.revision,
            displayName: manifest.displayName,
            manifestData: try encoded(manifest),
            project: currentProject
        )
        modelContext.insert(record)
        try saveDomainChange(project: currentProject, modelContext: modelContext)
        return record
    }

    @discardableResult
    func addTargetProfile(
        _ manifest: CoreAITargetManifest,
        to project: LabProject,
        modelContext: ModelContext
    ) throws -> CoreAITargetProfileRecord {
        try manifest.validate()
        let currentProject = try requireDomainProject(project, modelContext: modelContext)
        let record = CoreAITargetProfileRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            targetIdentifier: manifest.id,
            displayName: manifest.displayName,
            platform: manifest.platform,
            preferredComputeUnit: manifest.preferredComputeUnit,
            manifestData: try encoded(manifest),
            project: currentProject
        )
        modelContext.insert(record)
        try saveDomainChange(project: currentProject, modelContext: modelContext)
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
        let currentProject = try requireDomainProject(project, modelContext: modelContext)
        let currentRecipeRevision = try recipeRevision.map {
            guard let record = try domainRecipeRevision(
                id: $0.id,
                modelContext: modelContext
            ) else {
                throw CoreAIProjectLibraryError.domainRecordProjectMismatch
            }
            try requireSameProject(currentProject, recordProject: record.project)
            return record
        }
        let currentTargetProfile = try targetProfile.map {
            guard let record = try domainTargetProfile(
                id: $0.id,
                modelContext: modelContext
            ) else {
                throw CoreAIProjectLibraryError.domainRecordProjectMismatch
            }
            try requireSameProject(currentProject, recordProject: record.project)
            return record
        }
        let record = CoreAIRunRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            kind: kind,
            status: status,
            project: currentProject,
            recipeRevision: currentRecipeRevision,
            targetProfile: currentTargetProfile
        )
        modelContext.insert(record)
        try saveDomainChange(project: currentProject, modelContext: modelContext)
        return record
    }

    func updateRun(
        _ run: CoreAIRunRecord,
        status: CoreAIRunStatus,
        summary: String? = nil,
        endedAt: Date? = nil,
        modelContext: ModelContext
    ) throws {
        guard let currentRun = try domainRun(id: run.id, modelContext: modelContext),
              let project = currentRun.project else {
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
        currentRun.update(
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
        guard let currentRun = try domainRun(id: run.id, modelContext: modelContext),
              let project = currentRun.project else {
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
            run: currentRun
        )
        modelContext.insert(record)
        try saveDomainChange(project: project, modelContext: modelContext)
        return record
    }

    private func validateImportedArtifact(
        _ storedArtifact: CoreAIStoredArtifact,
        sourceURL: URL
    ) throws {
        let components: [String]
        do {
            components = try CoreAIStoredPathSecurity.contentAddressedComponents(
                for: storedArtifact.storageRelativePath
            )
        } catch {
            throw CoreAIProjectLibraryError.inconsistentArtifactRecord
        }
        guard components[2] == storedArtifact.sha256Digest,
              storedArtifact.sourceURL.standardizedFileURL
                == sourceURL.standardizedFileURL,
              storedArtifact.originalFilename == sourceURL.lastPathComponent,
              !storedArtifact.originalFilename.isEmpty,
              storedArtifact.byteCount >= 0,
              storedArtifact.fileCount >= 0 else {
            throw CoreAIProjectLibraryError.inconsistentArtifactRecord
        }
        try validateProvenance(
            kind: .localFile,
            sourceLocation: sourceURL.path(percentEncoded: false),
            providerName: "",
            licenseName: "",
            notes: ""
        )

        let storedURL = try validatedStoredURL(for: storedArtifact)
        let values = try storedURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        )
        let isDirectory = values.isDirectory == true
        guard isDirectory || values.isRegularFile == true,
              CoreAIArtifactKind.infer(from: storedURL, isDirectory: isDirectory)
                == storedArtifact.kind else {
            throw CoreAIProjectLibraryError.inconsistentArtifactRecord
        }
        if isDirectory {
            guard let snapshot = storedArtifact.resourceSnapshot else {
                throw CoreAIProjectLibraryError.inconsistentArtifactRecord
            }
            try snapshot.validate()
            guard snapshot.files.count == storedArtifact.fileCount,
                  snapshot.byteCount == storedArtifact.byteCount else {
                throw CoreAIProjectLibraryError.inconsistentArtifactRecord
            }
        } else {
            guard storedArtifact.resourceSnapshot == nil,
                  storedArtifact.fileCount == 1,
                  values.fileSize.map(Int64.init) == storedArtifact.byteCount else {
                throw CoreAIProjectLibraryError.inconsistentArtifactRecord
            }
        }
    }

    private func importedProvenance(
        sourceURL: URL,
        link: ProjectArtifactLink
    ) -> CoreAISourceProvenanceRecord {
        CoreAISourceProvenanceRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            kind: .localFile,
            sourceLocation: sourceURL.path(percentEncoded: false),
            artifactLink: link
        )
    }

    private func validateProvenance(
        kind: CoreAISourceProvenanceKind,
        sourceLocation: String,
        providerName: String,
        licenseName: String,
        notes: String
    ) throws {
        if kind != .unknown, sourceLocation.isEmpty {
            throw CoreAIProjectLibraryError.invalidSourceProvenance(
                "enter a source location"
            )
        }
        let values = [
            (sourceLocation, 16_384, "source location"),
            (providerName, 256, "provider"),
            (licenseName, 256, "license"),
            (notes, 16_384, "notes")
        ]
        for (value, maximumCount, label) in values {
            guard value.count <= maximumCount else {
                throw CoreAIProjectLibraryError.invalidSourceProvenance(
                    "\(label) exceeds \(maximumCount.formatted()) characters"
                )
            }
            guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
                throw CoreAIProjectLibraryError.invalidSourceProvenance(
                    "\(label) contains a null character"
                )
            }
        }
    }

    private func upsertSpecializationCacheRecord(
        _ result: CoreAISpecializationResult,
        project: LabProject,
        link: ProjectArtifactLink,
        modelContext: ModelContext
    ) throws {
        guard link.project?.id == project.id,
              link.artifact != nil else {
            throw CoreAIProjectLibraryError.domainRecordProjectMismatch
        }
        let identityKey = CoreAISpecializationCacheRecord.identityKey(
            artifactLinkID: link.id,
            configuration: result.configuration
        )
        let matchingRecords = try modelContext.fetch(
            FetchDescriptor<CoreAISpecializationCacheRecord>()
        ).filter { record in
            record.identityKey == identityKey
                || (record.identityKey == nil
                    && record.artifactLink?.id == link.id
                    && record.configuration == result.configuration)
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        if let canonicalRecord = matchingRecords.first {
            canonicalRecord.markUsed(
                authorization: CoreAIProjectDomainWriteAuthorization(),
                identityKey: identityKey,
                wasLoadedFromCache: result.loadedFromCache
            )
            for duplicateRecord in matchingRecords.dropFirst() {
                modelContext.delete(duplicateRecord)
            }
        } else {
            modelContext.insert(
                CoreAISpecializationCacheRecord(
                    authorization: CoreAIProjectDomainWriteAuthorization(),
                    configuration: result.configuration,
                    wasLoadedFromCache: result.loadedFromCache,
                    project: project,
                    artifactLink: link
                )
            )
        }

        do {
            try saveDomainChange(project: project, modelContext: modelContext)
        } catch {
            modelContext.rollback()
            let persistedRecords = try modelContext.fetch(
                FetchDescriptor<CoreAISpecializationCacheRecord>()
            ).filter { $0.identityKey == identityKey }
                .sorted { $0.id.uuidString < $1.id.uuidString }
            guard let persistedRecord = persistedRecords.first else {
                throw error
            }
            persistedRecord.markUsed(
                authorization: CoreAIProjectDomainWriteAuthorization(),
                identityKey: identityKey,
                wasLoadedFromCache: result.loadedFromCache
            )
            for duplicateRecord in persistedRecords.dropFirst() {
                modelContext.delete(duplicateRecord)
            }
            try saveDomainChange(project: project, modelContext: modelContext)
        }
    }

    private func domainProject(
        id: UUID,
        modelContext: ModelContext
    ) throws -> LabProject? {
        try modelContext.fetch(FetchDescriptor<LabProject>())
            .first { $0.id == id }
    }

    private func requireDomainProject(
        _ project: LabProject,
        modelContext: ModelContext
    ) throws -> LabProject {
        guard let currentProject = try domainProject(
            id: project.id,
            modelContext: modelContext
        ) else {
            throw CoreAIProjectLibraryError.projectUnavailable
        }
        return currentProject
    }

    private func domainRecipeRevision(
        id: UUID,
        modelContext: ModelContext
    ) throws -> CoreAIRecipeRevisionRecord? {
        try modelContext.fetch(FetchDescriptor<CoreAIRecipeRevisionRecord>())
            .first { $0.id == id }
    }

    private func domainTargetProfile(
        id: UUID,
        modelContext: ModelContext
    ) throws -> CoreAITargetProfileRecord? {
        try modelContext.fetch(FetchDescriptor<CoreAITargetProfileRecord>())
            .first { $0.id == id }
    }

    private func domainRun(
        id: UUID,
        modelContext: ModelContext
    ) throws -> CoreAIRunRecord? {
        try modelContext.fetch(FetchDescriptor<CoreAIRunRecord>())
            .first { $0.id == id }
    }

    private func domainArtifactRecord(
        sha256Digest: String,
        modelContext: ModelContext
    ) throws -> ModelArtifactRecord? {
        let digest = sha256Digest
        var descriptor = FetchDescriptor<ModelArtifactRecord>(
            predicate: #Predicate { $0.sha256Digest == digest }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func domainArtifactLink(
        id: UUID,
        modelContext: ModelContext
    ) throws -> ProjectArtifactLink? {
        try modelContext.fetch(FetchDescriptor<ProjectArtifactLink>())
            .first { $0.id == id }
    }

    private func domainArtifactLinks(
        sha256Digest: String,
        modelContext: ModelContext
    ) throws -> [ProjectArtifactLink] {
        try modelContext.fetch(FetchDescriptor<ProjectArtifactLink>()).filter {
            $0.artifact?.sha256Digest == sha256Digest
        }
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
        id: UUID,
        in project: LabProject,
        recipeRevision: CoreAIRecipeRevisionRecord?,
        provenanceEvidence: CoreAIRuntimeProvenanceEvidence,
        modelContext: ModelContext
    ) throws -> CoreAIRunRecord {
        if let recipeRevision {
            try requireSameProject(project, recordProject: recipeRevision.project)
        }
        let descriptor = FetchDescriptor<CoreAIRunRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            try requireSameProject(project, recordProject: existing.project)
            guard let status = existing.status else {
                throw CoreAIProjectLibraryError.runStatusUnavailable
            }
            guard status == .running else {
                throw CoreAIProjectLibraryError.invalidRunStatusTransition(
                    from: status,
                    to: .running
                )
            }
            return existing
        }
        let metadataData = try encoded(provenanceEvidence.metadata)
        let run = CoreAIRunRecord(
            authorization: CoreAIProjectDomainWriteAuthorization(),
            id: id,
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

    func recoverInterruptedRuntimeRuns(
        in project: LabProject,
        endedAt: Date,
        modelContext: ModelContext
    ) throws -> Int {
        let runs = try modelContext.fetch(FetchDescriptor<CoreAIRunRecord>())
        let interruptedRuns = runs.filter {
            $0.project?.id == project.id && $0.status == .running
        }
        guard !interruptedRuns.isEmpty else { return 0 }

        for run in interruptedRuns {
            run.update(
                authorization: CoreAIProjectDomainWriteAuthorization(),
                status: .failed,
                summary: "Run was interrupted before completion and recovered when project recording resumed.",
                endedAt: endedAt
            )
        }
        try saveDomainChange(project: project, modelContext: modelContext)
        return interruptedRuns.count
    }
}
