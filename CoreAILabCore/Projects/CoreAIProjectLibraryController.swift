import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CoreAIProjectLibraryController {
    private(set) var activeProjectID: UUID?
    private(set) var activeOperation: CoreAIProjectLibraryOperation?
    private(set) var errorMessage: String?
    var isShowingError = false

    @ObservationIgnored
    private let artifactStore: CoreAIArtifactStore
    @ObservationIgnored
    private let specializationCacheManager: any CoreAISpecializationCacheManaging
    @ObservationIgnored
    private let mutationCoordinator = CoreAIProjectLibraryMutationCoordinator.shared

    init(
        artifactStore: CoreAIArtifactStore = .shared,
        specializationCacheManager: any CoreAISpecializationCacheManaging = CoreAISpecializationService()
    ) {
        self.artifactStore = artifactStore
        self.specializationCacheManager = specializationCacheManager
    }

    var isPerformingOperation: Bool {
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
        activeOperation = .importingArtifact
        defer {
            activeProjectID = nil
            activeOperation = nil
        }

        return try await mutationCoordinator.withLock(key: storageMutationKey) {
            let storedArtifact = try await artifactStore.importArtifact(from: sourceURL)
            do {
                return try persistImportedArtifact(
                    storedArtifact,
                    sourceURL: sourceURL,
                    projectID: projectID,
                    modelContext: modelContext
                )
            } catch {
                if !storedArtifact.wasAlreadyStored {
                    try? await artifactStore.removeArtifact(
                        at: storedArtifact.storageRelativePath
                    )
                }
                throw error
            }
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
              link.artifact != nil else {
            throw CoreAIProjectLibraryError.artifactUnavailable
        }
        activeProjectID = project.id
        activeOperation = .removingArtifact
        defer {
            activeProjectID = nil
            activeOperation = nil
        }

        try await mutationCoordinator.withLock(key: storageMutationKey) {
            guard let currentLink = try artifactLink(
                id: link.id,
                modelContext: modelContext
            ),
                  let currentProject = currentLink.project,
                  let currentArtifact = currentLink.artifact else {
                throw CoreAIProjectLibraryError.artifactUnavailable
            }
            let currentLinks = try artifactLinks(
                sha256Digest: currentArtifact.sha256Digest,
                modelContext: modelContext
            )
            let survivingLinks = currentLinks.filter { $0.id != currentLink.id }
            let shouldRemoveStoredArtifact = survivingLinks.isEmpty
            let storageRelativePath = currentArtifact.storageRelativePath
            if shouldRemoveStoredArtifact {
                _ = try validatedStoredURL(
                    for: currentArtifact,
                    requireExisting: false
                )
            }
            try await removeUnsharedSpecializationCaches(
                ownedBy: currentLink,
                survivingLinks: survivingLinks,
                artifact: currentArtifact
            )
            modelContext.delete(currentLink)
            if shouldRemoveStoredArtifact {
                modelContext.delete(currentArtifact)
            }
            currentProject.updatedAt = .now

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
    }

    func deleteProject(
        _ project: LabProject,
        modelContext: ModelContext
    ) async throws {
        guard activeProjectID == nil else {
            throw CoreAIProjectLibraryError.operationInProgress
        }
        activeProjectID = project.id
        activeOperation = .deletingProject
        defer {
            activeProjectID = nil
            activeOperation = nil
        }

        try await mutationCoordinator.withLock(key: storageMutationKey) {
            guard let currentProject = try persistedProject(
                id: project.id,
                modelContext: modelContext
            ) else {
                throw CoreAIProjectLibraryError.projectUnavailable
            }
            let projectLinks = currentProject.artifactLinks
            var orphanedArtifacts: [ModelArtifactRecord] = []
            for currentLink in projectLinks {
                guard let artifact = currentLink.artifact else { continue }
                let currentLinks = try artifactLinks(
                    sha256Digest: artifact.sha256Digest,
                    modelContext: modelContext
                )
                let survivingLinks = currentLinks.filter {
                    $0.project?.id != currentProject.id
                }
                try await removeUnsharedSpecializationCaches(
                    ownedBy: currentLink,
                    survivingLinks: survivingLinks,
                    artifact: artifact
                )
                if survivingLinks.isEmpty {
                    _ = try validatedStoredURL(
                        for: artifact,
                        requireExisting: false
                    )
                    orphanedArtifacts.append(artifact)
                }
            }
            let storagePaths = Array(Set(orphanedArtifacts.map(\.storageRelativePath)))
            modelContext.delete(currentProject)
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
    }

    func validatedStoredURL(
        for artifact: ModelArtifactRecord,
        requireExisting: Bool = true
    ) throws -> URL {
        try artifactStore.validatedURL(
            for: artifact.storageRelativePath,
            requireExisting: requireExisting
        )
    }

    func validatedStoredURL(
        for storedArtifact: CoreAIStoredArtifact,
        requireExisting: Bool = true
    ) throws -> URL {
        try artifactStore.validatedURL(
            for: storedArtifact.storageRelativePath,
            requireExisting: requireExisting
        )
    }

    func present(_ error: any Error) {
        guard (error as? CocoaError)?.code != .userCancelled else { return }
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private func artifactLink(
        id: UUID,
        modelContext: ModelContext
    ) throws -> ProjectArtifactLink? {
        try modelContext.fetch(FetchDescriptor<ProjectArtifactLink>())
            .first { $0.id == id }
    }

    private func artifactLinks(
        sha256Digest: String,
        modelContext: ModelContext
    ) throws -> [ProjectArtifactLink] {
        try modelContext.fetch(FetchDescriptor<ProjectArtifactLink>()).filter {
            $0.artifact?.sha256Digest == sha256Digest
        }
    }

    private func persistedProject(
        id: UUID,
        modelContext: ModelContext
    ) throws -> LabProject? {
        try modelContext.fetch(FetchDescriptor<LabProject>())
            .first { $0.id == id }
    }

    func clearError() {
        errorMessage = nil
        isShowingError = false
    }

    func beginProjectOperation(projectID: UUID) -> Bool {
        guard activeProjectID == nil else { return false }
        activeProjectID = projectID
        activeOperation = .managingSpecializationCache
        return true
    }

    func endProjectOperation(projectID: UUID) {
        guard activeProjectID == projectID else { return }
        activeProjectID = nil
        activeOperation = nil
    }

    func removeSystemCacheEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws {
        try await specializationCacheManager.removeCachedEntry(
            at: url,
            configuration: configuration
        )
    }

    func removeAllSystemCacheEntries(at url: URL) async throws {
        try await specializationCacheManager.removeCachedEntries(at: url)
    }

    func performSerializedStorageMutation<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        try await mutationCoordinator.withLock(
            key: storageMutationKey,
            operation: operation
        )
    }

    private var storageMutationKey: String {
        "artifact-store:\(artifactStore.rootURL.resolvingSymlinksInPath().standardizedFileURL.path)"
    }

    private func removeUnsharedSpecializationCaches(
        ownedBy link: ProjectArtifactLink,
        survivingLinks: [ProjectArtifactLink],
        artifact: ModelArtifactRecord
    ) async throws {
        guard !link.specializationCaches.isEmpty else { return }
        let artifactURL = try validatedStoredURL(for: artifact)
        if survivingLinks.isEmpty {
            do {
                try await specializationCacheManager.removeCachedEntries(at: artifactURL)
            } catch where CoreAISpecializationService.isMissingCacheEntry(error) {
                // The project records can be deleted when the OS cache is already empty.
            }
            return
        }

        for record in link.specializationCaches {
            guard let configuration = record.configuration else {
                throw CoreAIProjectLibraryError.invalidSpecializationCacheRecord
            }
            let isRetained = survivingLinks.contains { survivingLink in
                survivingLink.specializationCaches.contains {
                    $0.configuration == configuration
                }
            }
            guard !isRetained else { continue }
            do {
                try await specializationCacheManager.removeCachedEntry(
                    at: artifactURL,
                    configuration: configuration
                )
            } catch where CoreAISpecializationService.isMissingCacheEntry(error) {
                // The project records can be deleted when the OS cache is already empty.
            }
        }
    }
}

@MainActor
private final class CoreAIProjectLibraryMutationCoordinator {
    static let shared = CoreAIProjectLibraryMutationCoordinator()

    private var heldKeys = Set<String>()
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func withLock<T>(
        key: String,
        operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        await acquire(key)
        do {
            let result = try await operation()
            release(key)
            return result
        } catch {
            release(key)
            throw error
        }
    }

    private func acquire(_ key: String) async {
        if heldKeys.insert(key).inserted {
            return
        }
        await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
        }
    }

    private func release(_ key: String) {
        guard var keyWaiters = waiters[key], !keyWaiters.isEmpty else {
            heldKeys.remove(key)
            waiters[key] = nil
            return
        }
        let nextWaiter = keyWaiters.removeFirst()
        waiters[key] = keyWaiters.isEmpty ? nil : keyWaiters
        nextWaiter.resume()
    }
}
