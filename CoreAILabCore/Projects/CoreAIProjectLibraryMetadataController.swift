import Foundation
import SwiftData

extension CoreAIProjectLibraryController {
    func removeSpecializationCache(
        _ record: CoreAISpecializationCacheRecord,
        modelContext: ModelContext
    ) async throws {
        guard let initialProject = record.project else {
            throw CoreAIProjectLibraryError.artifactUnavailable
        }
        guard beginProjectOperation(projectID: initialProject.id) else {
            throw CoreAIProjectLibraryError.operationInProgress
        }
        defer { endProjectOperation(projectID: initialProject.id) }
        let recordID = record.id
        try await performSerializedStorageMutation {
            guard let currentRecord = try specializationCacheRecord(
                id: recordID,
                modelContext: modelContext
            ),
                  let project = currentRecord.project else {
                throw CoreAIProjectLibraryError.artifactUnavailable
            }
            guard let link = currentRecord.artifactLink,
                  link.project?.id == project.id,
                  let artifact = link.artifact else {
                throw CoreAIProjectLibraryError.artifactUnavailable
            }
            guard let configuration = currentRecord.configuration else {
                throw CoreAIProjectLibraryError.invalidSpecializationCacheRecord
            }
            let isRetainedByAnotherRecord = try specializationCacheRecords(
                forArtifactDigest: artifact.sha256Digest,
                modelContext: modelContext
            ).contains { otherRecord in
                otherRecord.id != currentRecord.id
                    && otherRecord.configuration == configuration
            }
            if !isRetainedByAnotherRecord {
                do {
                    try await removeSystemCacheEntry(
                        at: try validatedStoredURL(for: artifact),
                        configuration: configuration
                    )
                } catch where CoreAISpecializationService.isMissingCacheEntry(error) {
                    // The persisted record can safely be reconciled with an already-empty cache.
                }
            }
            modelContext.delete(currentRecord)
            try saveLibraryMetadata(project: project, modelContext: modelContext)
        }
    }

    func removeAllSpecializationCaches(
        for link: ProjectArtifactLink,
        modelContext: ModelContext
    ) async throws {
        guard let initialProject = link.project else {
            throw CoreAIProjectLibraryError.artifactUnavailable
        }
        guard beginProjectOperation(projectID: initialProject.id) else {
            throw CoreAIProjectLibraryError.operationInProgress
        }
        defer { endProjectOperation(projectID: initialProject.id) }
        let linkID = link.id
        try await performSerializedStorageMutation {
            guard let currentLink = try projectArtifactLink(
                id: linkID,
                modelContext: modelContext
            ),
                  let project = currentLink.project,
                  let artifact = currentLink.artifact else {
                throw CoreAIProjectLibraryError.artifactUnavailable
            }

            let allRecords = try specializationCacheRecords(
                forArtifactDigest: artifact.sha256Digest,
                modelContext: modelContext
            )
            let recordsToRemove = allRecords.filter {
                $0.artifactLink?.id == currentLink.id
            }
            let retainedRecords = allRecords.filter {
                $0.artifactLink?.id != currentLink.id
            }
            let otherLinksExist = try projectArtifactLinks(
                forArtifactDigest: artifact.sha256Digest,
                modelContext: modelContext
            ).contains { $0.id != currentLink.id }
            if !otherLinksExist {
                do {
                    try await removeAllSystemCacheEntries(
                        at: try validatedStoredURL(for: artifact)
                    )
                } catch where CoreAISpecializationService.isMissingCacheEntry(error) {
                    // The persisted records can safely be reconciled with an already-empty cache.
                }
            } else {
                var configurations = Set<CoreAISpecializationConfiguration>()
                for record in recordsToRemove {
                    guard let configuration = record.configuration else {
                        throw CoreAIProjectLibraryError.invalidSpecializationCacheRecord
                    }
                    configurations.insert(configuration)
                }
                for configuration in configurations {
                    let isRetained = retainedRecords.contains { otherRecord in
                        otherRecord.configuration == configuration
                    }
                    guard !isRetained else { continue }
                    do {
                        try await removeSystemCacheEntry(
                            at: try validatedStoredURL(for: artifact),
                            configuration: configuration
                        )
                    } catch where CoreAISpecializationService.isMissingCacheEntry(error) {
                        // The persisted record can safely be reconciled with an already-empty cache.
                    }
                }
            }
            for record in recordsToRemove {
                modelContext.delete(record)
            }
            try saveLibraryMetadata(project: project, modelContext: modelContext)
        }
    }

    private func specializationCacheRecord(
        id: UUID,
        modelContext: ModelContext
    ) throws -> CoreAISpecializationCacheRecord? {
        try modelContext.fetch(
            FetchDescriptor<CoreAISpecializationCacheRecord>()
        ).first { $0.id == id }
    }

    private func projectArtifactLink(
        id: UUID,
        modelContext: ModelContext
    ) throws -> ProjectArtifactLink? {
        try modelContext.fetch(FetchDescriptor<ProjectArtifactLink>())
            .first { $0.id == id }
    }

    private func projectArtifactLinks(
        forArtifactDigest artifactDigest: String,
        modelContext: ModelContext
    ) throws -> [ProjectArtifactLink] {
        try modelContext.fetch(FetchDescriptor<ProjectArtifactLink>()).filter {
            $0.artifact?.sha256Digest == artifactDigest
        }
    }

    private func specializationCacheRecords(
        forArtifactDigest artifactDigest: String,
        modelContext: ModelContext
    ) throws -> [CoreAISpecializationCacheRecord] {
        try modelContext.fetch(
            FetchDescriptor<CoreAISpecializationCacheRecord>()
        ).filter { $0.artifactLink?.artifact?.sha256Digest == artifactDigest }
    }

    private func saveLibraryMetadata(
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

}
