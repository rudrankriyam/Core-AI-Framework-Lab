import Foundation
import SwiftData
import Testing
@testable import CoreAILab

@MainActor
struct CoreAIProjectPersistenceTests {
    @Test
    func projectMetadataSurvivesReopeningThePersistentStore() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storeURL = directory.appending(path: "projects.store")
        let projectID: UUID

        do {
            let container = try CoreAIProjectModelContainer.makePersistent(
                storeURL: storeURL
            )
            let controller = CoreAIProjectLibraryController(
                artifactStore: CoreAIArtifactStore(rootURL: directory.appending(path: "artifacts"))
            )
            let project = try controller.createProject(
                named: "Persistent Qwen Lab",
                modelContext: container.mainContext
            )
            projectID = project.id
        }

        let reopenedContainer = try CoreAIProjectModelContainer.makePersistent(
            storeURL: storeURL
        )
        let projects = try reopenedContainer.mainContext.fetch(FetchDescriptor<LabProject>())
        #expect(projects.count == 1)
        #expect(projects.first?.id == projectID)
        #expect(projects.first?.name == "Persistent Qwen Lab")
        #expect(projects.first?.schemaVersion == 1)
    }

    @Test
    func directoryImportIsContentAddressedAndDeduplicated() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSource = directory.appending(path: "first.aimodel", directoryHint: .isDirectory)
        let secondSource = directory.appending(path: "second.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: firstSource)
        try makeModelFixture(at: secondSource)
        let store = CoreAIArtifactStore(rootURL: directory.appending(path: "store"))

        let first = try await store.importArtifact(from: firstSource)
        let second = try await store.importArtifact(from: secondSource)

        #expect(first.sha256Digest.count == 64)
        #expect(first.sha256Digest == second.sha256Digest)
        #expect(first.storageRelativePath == second.storageRelativePath)
        #expect(!first.wasAlreadyStored)
        #expect(second.wasAlreadyStored)
        #expect(first.kind == .modelAsset)
        #expect(first.fileCount == 2)
        #expect(first.byteCount == 13)
        #expect(FileManager.default.fileExists(atPath: store.url(for: first.storageRelativePath).path))
    }

    @Test
    func concurrentStoreInstancesConvergeOnOneArtifact() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let storeRoot = directory.appending(path: "store")
        let firstStore = CoreAIArtifactStore(rootURL: storeRoot)
        let secondStore = CoreAIArtifactStore(rootURL: storeRoot)

        async let first = firstStore.importArtifact(from: source)
        async let second = secondStore.importArtifact(from: source)
        let imports = try await [first, second]

        #expect(Set(imports.map(\.sha256Digest)).count == 1)
        #expect(Set(imports.map(\.storageRelativePath)).count == 1)
        #expect(FileManager.default.fileExists(
            atPath: firstStore.url(for: imports[0].storageRelativePath).path
        ))
    }

    @Test
    func duplicateProjectsShareOneBlobUntilTheLastReferenceIsRemoved() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let store = CoreAIArtifactStore(rootURL: directory.appending(path: "store"))
        let controller = CoreAIProjectLibraryController(artifactStore: store)
        let container = try makeContainer()
        let context = container.mainContext
        let firstProject = try controller.createProject(named: "First", modelContext: context)
        let secondProject = try controller.createProject(named: "Second", modelContext: context)

        let firstLink = try await controller.importArtifact(
            from: source,
            into: firstProject,
            modelContext: context
        )
        let duplicateLink = try await controller.importArtifact(
            from: source,
            into: firstProject,
            modelContext: context
        )
        let secondLink = try await controller.importArtifact(
            from: source,
            into: secondProject,
            modelContext: context
        )
        let record = try #require(firstLink.artifact)
        let storedURL = controller.storedURL(for: record)

        #expect(firstLink.id == duplicateLink.id)
        #expect(firstProject.artifactLinks.count == 1)
        #expect(secondLink.artifact?.sha256Digest == record.sha256Digest)
        #expect(try context.fetch(FetchDescriptor<ModelArtifactRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProjectArtifactLink>()).count == 2)

        try await controller.removeArtifactLink(firstLink, modelContext: context)
        #expect(FileManager.default.fileExists(atPath: storedURL.path))
        #expect(try context.fetch(FetchDescriptor<ModelArtifactRecord>()).count == 1)

        try await controller.removeArtifactLink(secondLink, modelContext: context)
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))
        #expect(try context.fetch(FetchDescriptor<ModelArtifactRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProjectArtifactLink>()).isEmpty)
    }

    @Test
    func deletingAProjectKeepsArtifactsReferencedByAnotherProject() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let controller = CoreAIProjectLibraryController(
            artifactStore: CoreAIArtifactStore(rootURL: directory.appending(path: "store"))
        )
        let container = try makeContainer()
        let context = container.mainContext
        let first = try controller.createProject(named: "First", modelContext: context)
        let second = try controller.createProject(named: "Second", modelContext: context)
        _ = try await controller.importArtifact(from: source, into: first, modelContext: context)
        let survivingLink = try await controller.importArtifact(
            from: source,
            into: second,
            modelContext: context
        )
        let storedURL = controller.storedURL(for: try #require(survivingLink.artifact))

        try await controller.deleteProject(first, modelContext: context)

        #expect(FileManager.default.fileExists(atPath: storedURL.path))
        #expect(try context.fetch(FetchDescriptor<LabProject>()).map(\.name) == ["Second"])
        #expect(try context.fetch(FetchDescriptor<ModelArtifactRecord>()).count == 1)

        try await controller.deleteProject(second, modelContext: context)
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))
        #expect(try context.fetch(FetchDescriptor<LabProject>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ModelArtifactRecord>()).isEmpty)
    }

    @Test
    func symbolicLinksAreRejectedWithoutCreatingAnArtifact() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "unsafe.aimodel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: source.appending(path: "main.mlirb"))
        try FileManager.default.createSymbolicLink(
            at: source.appending(path: "outside"),
            withDestinationURL: directory
        )
        let storeRoot = directory.appending(path: "store")
        let store = CoreAIArtifactStore(rootURL: storeRoot)

        await #expect(throws: CoreAIArtifactStoreError.self) {
            try await store.importArtifact(from: source)
        }
        #expect(!FileManager.default.fileExists(atPath: storeRoot.appending(path: "sha256").path))
    }

    @Test
    func corruptedStoredContentIsNotSilentlyReused() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "model.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let store = CoreAIArtifactStore(rootURL: directory.appending(path: "store"))
        let imported = try await store.importArtifact(from: source)
        try Data("corrupted".utf8).write(
            to: store.url(for: imported.storageRelativePath).appending(path: "main.mlirb")
        )

        await #expect(throws: CoreAIArtifactStoreError.self) {
            try await store.importArtifact(from: source)
        }
    }

    @Test
    func invalidMetadataCannotDeleteTheArtifactStoreRoot() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let markerURL = directory.appending(path: "keep-me")
        try Data("safe".utf8).write(to: markerURL)
        let store = CoreAIArtifactStore(rootURL: directory)

        await #expect(throws: CoreAIArtifactStoreError.self) {
            try await store.removeArtifact(at: "artifact")
        }
        #expect(FileManager.default.fileExists(atPath: markerURL.path))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            LabProject.self,
            ModelArtifactRecord.self,
            ProjectArtifactLink.self
        ])
        let configuration = ModelConfiguration(
            "CoreAIProjectPersistenceTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeModelFixture(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("model-bytes".utf8).write(to: url.appending(path: "main.mlirb"))
        try Data("{}".utf8).write(to: url.appending(path: "metadata.json"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "CoreAIProjectPersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}
