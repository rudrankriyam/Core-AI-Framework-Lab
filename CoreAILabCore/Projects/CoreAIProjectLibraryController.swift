import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CoreAIProjectLibraryController {
    private(set) var activeProjectID: UUID?
    private(set) var errorMessage: String?
    var isShowingError = false

    @ObservationIgnored
    private let artifactStore: CoreAIArtifactStore

    init(artifactStore: CoreAIArtifactStore = .shared) {
        self.artifactStore = artifactStore
    }

    var isImporting: Bool {
        activeProjectID != nil
    }

    func createProject(
        named proposedName: String,
        modelContext: ModelContext
    ) throws -> LabProject {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw CoreAIProjectLibraryError.projectNameRequired
        }

        let project = LabProject(name: name)
        modelContext.insert(project)
        do {
            try modelContext.save()
            clearError()
            return project
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func renameProject(
        _ project: LabProject,
        to proposedName: String,
        modelContext: ModelContext
    ) throws {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw CoreAIProjectLibraryError.projectNameRequired
        }
        let previousName = project.name
        let previousUpdatedAt = project.updatedAt
        project.name = name
        project.updatedAt = .now
        do {
            try modelContext.save()
            clearError()
        } catch {
            project.name = previousName
            project.updatedAt = previousUpdatedAt
            modelContext.rollback()
            throw error
        }
    }

    func markOpened(
        _ project: LabProject,
        modelContext: ModelContext
    ) throws {
        project.lastOpenedAt = .now
        try modelContext.save()
    }

    @discardableResult
    func importArtifact(
        from sourceURL: URL,
        into project: LabProject,
        modelContext: ModelContext
    ) async throws -> ProjectArtifactLink {
        guard activeProjectID == nil else {
            throw CoreAIProjectLibraryError.operationInProgress
        }
        let projectID = project.id
        activeProjectID = projectID
        defer { activeProjectID = nil }

        let storedArtifact = try await artifactStore.importArtifact(from: sourceURL)
        guard project.id == projectID else {
            throw CoreAIProjectLibraryError.projectUnavailable
        }

        let existingRecord = try artifactRecord(
            sha256Digest: storedArtifact.sha256Digest,
            modelContext: modelContext
        )
        if let existingRecord,
           existingRecord.storageRelativePath != storedArtifact.storageRelativePath {
            throw CoreAIProjectLibraryError.inconsistentArtifactRecord
        }
        if let existingLink = project.artifactLinks.first(where: {
            $0.artifact?.sha256Digest == storedArtifact.sha256Digest
        }) {
            project.updatedAt = .now
            try modelContext.save()
            clearError()
            return existingLink
        }

        let record = existingRecord ?? ModelArtifactRecord(
            sha256Digest: storedArtifact.sha256Digest,
            storageRelativePath: storedArtifact.storageRelativePath,
            originalFilename: storedArtifact.originalFilename,
            kind: storedArtifact.kind,
            byteCount: storedArtifact.byteCount,
            fileCount: storedArtifact.fileCount
        )
        let link = ProjectArtifactLink(
            displayName: sourceURL.lastPathComponent,
            project: project,
            artifact: record
        )

        if existingRecord == nil {
            modelContext.insert(record)
        }
        modelContext.insert(link)
        project.updatedAt = .now

        do {
            try modelContext.save()
            clearError()
            return link
        } catch {
            modelContext.rollback()
            if existingRecord == nil && !storedArtifact.wasAlreadyStored {
                try? await artifactStore.removeArtifact(
                    at: storedArtifact.storageRelativePath
                )
            }
            throw error
        }
    }

    func removeArtifactLink(
        _ link: ProjectArtifactLink,
        modelContext: ModelContext
    ) async throws {
        guard activeProjectID == nil else {
            throw CoreAIProjectLibraryError.operationInProgress
        }
        guard let project = link.project,
              let artifact = link.artifact else {
            throw CoreAIProjectLibraryError.artifactUnavailable
        }
        activeProjectID = project.id
        defer { activeProjectID = nil }

        let shouldRemoveStoredArtifact = artifact.projectLinks.allSatisfy {
            $0.id == link.id
        }
        let storageRelativePath = artifact.storageRelativePath
        modelContext.delete(link)
        if shouldRemoveStoredArtifact {
            modelContext.delete(artifact)
        }
        project.updatedAt = .now

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        if shouldRemoveStoredArtifact {
            try await artifactStore.removeArtifact(at: storageRelativePath)
        }
        clearError()
    }

    func deleteProject(
        _ project: LabProject,
        modelContext: ModelContext
    ) async throws {
        guard activeProjectID == nil else {
            throw CoreAIProjectLibraryError.operationInProgress
        }
        activeProjectID = project.id
        defer { activeProjectID = nil }

        let orphanedArtifacts = project.artifactLinks.compactMap(\.artifact).filter { artifact in
            artifact.projectLinks.allSatisfy { $0.project?.id == project.id }
        }
        let storagePaths = Array(Set(orphanedArtifacts.map(\.storageRelativePath)))
        modelContext.delete(project)
        for artifact in orphanedArtifacts {
            modelContext.delete(artifact)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        for storagePath in storagePaths {
            try await artifactStore.removeArtifact(at: storagePath)
        }
        clearError()
    }

    func storedURL(for artifact: ModelArtifactRecord) -> URL {
        artifactStore.url(for: artifact.storageRelativePath)
    }

    func present(_ error: any Error) {
        guard (error as? CocoaError)?.code != .userCancelled else { return }
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private func artifactRecord(
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

    private func clearError() {
        errorMessage = nil
        isShowingError = false
    }
}
