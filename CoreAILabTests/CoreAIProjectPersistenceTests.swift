import Foundation
import SwiftData
import Testing
@testable import CoreAILab

@MainActor
struct CoreAIProjectPersistenceTests {
    @Test
    func recipeTargetRunAndEvidenceSurviveReopeningThePersistentStore() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storeURL = directory.appending(path: "projects.store")
        let manifest = ChatterboxRecipeFixture.manifest
        let target = try #require(manifest.defaultTarget)
        let projectID: UUID
        let runID: UUID
        let evidenceID: UUID

        do {
            let container = try CoreAIProjectModelContainer.makePersistent(
                storeURL: storeURL
            )
            let controller = CoreAIProjectLibraryController(
                artifactStore: CoreAIArtifactStore(
                    rootURL: directory.appending(path: "artifacts")
                )
            )
            let project = try controller.createProject(
                named: "Persistent Chatterbox Lab",
                modelContext: container.mainContext
            )
            projectID = project.id
            let recipeRecord = try controller.addRecipeRevision(
                manifest,
                to: project,
                modelContext: container.mainContext
            )
            let targetRecord = try controller.addTargetProfile(
                target,
                to: project,
                modelContext: container.mainContext
            )
            let run = try controller.createRun(
                kind: .inference,
                status: .running,
                in: project,
                recipeRevision: recipeRecord,
                targetProfile: targetRecord,
                modelContext: container.mainContext
            )
            runID = run.id
            let evidence = try controller.recordEvidence(
                kind: .output,
                label: "Generated speech",
                relativePath: "outputs/sample.wav",
                sha256Digest: String(repeating: "a", count: 64),
                mediaType: "audio/wav",
                metadata: ["seed": "42"],
                for: run,
                modelContext: container.mainContext
            )
            evidenceID = evidence.id
            try controller.updateRun(
                run,
                status: .succeeded,
                summary: "Stop token reached",
                modelContext: container.mainContext
            )
        }

        do {
            let reopenedContainer = try CoreAIProjectModelContainer.makePersistent(
                storeURL: storeURL
            )
            let context = reopenedContainer.mainContext
            let project = try #require(
                try context.fetch(FetchDescriptor<LabProject>()).first
            )
            let run = try #require(
                try context.fetch(FetchDescriptor<CoreAIRunRecord>()).first
            )
            let evidence = try #require(
                try context.fetch(FetchDescriptor<CoreAIEvidenceRecord>()).first
            )

            #expect(project.id == projectID)
            #expect(project.recipeRevisions.count == 1)
            #expect(project.targetProfiles.count == 1)
            #expect(project.runs.map(\.id) == [runID])
            #expect(project.evidence.map(\.id) == [evidenceID])
            #expect(try project.recipeRevisions.first?.decodedManifest() == manifest)
            #expect(try project.targetProfiles.first?.decodedManifest() == target)
            #expect(run.status == .succeeded)
            #expect(run.recipeRevision?.recipeIdentifier == manifest.id)
            #expect(run.targetProfile?.targetIdentifier == target.id)
            #expect(run.evidence.map(\.id) == [evidenceID])
            #expect(evidence.run?.id == runID)
            #expect(try evidence.decodedMetadata() == ["seed": "42"])
        }
    }

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

        do {
            let reopenedContainer = try CoreAIProjectModelContainer.makePersistent(
                storeURL: storeURL
            )
            let projects = try reopenedContainer.mainContext.fetch(
                FetchDescriptor<LabProject>()
            )
            #expect(projects.count == 1)
            #expect(projects.first?.id == projectID)
            #expect(projects.first?.name == "Persistent Qwen Lab")
            #expect(projects.first?.schemaVersion == 1)
        }
    }

    @Test
    func runRejectsARecipeRevisionOwnedByAnotherProject() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let firstProject = try controller.createProject(
            named: "First",
            modelContext: context
        )
        let secondProject = try controller.createProject(
            named: "Second",
            modelContext: context
        )
        let manifest = ChatterboxRecipeFixture.manifest
        let recipe = try controller.addRecipeRevision(
            manifest,
            to: firstProject,
            modelContext: context
        )

        #expect(throws: CoreAIProjectLibraryError.domainRecordProjectMismatch) {
            _ = try controller.createRun(
                kind: .inference,
                in: secondProject,
                recipeRevision: recipe,
                modelContext: context
            )
        }
    }

    @Test
    func nonterminalRunCannotRetainAnEndDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let project = try controller.createProject(
            named: "Run lifecycle",
            modelContext: context
        )
        let run = try controller.createRun(
            kind: .inference,
            in: project,
            modelContext: context
        )

        try controller.updateRun(
            run,
            status: .running,
            endedAt: .distantPast,
            modelContext: context
        )

        #expect(run.status == .running)
        #expect(run.endedAt == nil)
    }

    @Test
    func statusOnlyUpdatePreservesTheExistingSummary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let project = try controller.createProject(
            named: "Run summary",
            modelContext: context
        )
        let run = try controller.createRun(
            kind: .inference,
            in: project,
            modelContext: context
        )

        try controller.updateRun(
            run,
            status: .running,
            summary: "Model loaded",
            modelContext: context
        )
        try controller.updateRun(
            run,
            status: .running,
            modelContext: context
        )

        #expect(run.summary == "Model loaded")
    }

    @Test
    func runLifecycleRejectsBackwardAndPostTerminalTransitions() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let project = try controller.createProject(
            named: "Immutable terminal run",
            modelContext: context
        )
        let run = try controller.createRun(
            kind: .inference,
            status: .running,
            in: project,
            modelContext: context
        )

        #expect(
            throws: CoreAIProjectLibraryError.invalidRunStatusTransition(
                from: .running,
                to: .pending
            )
        ) {
            try controller.updateRun(
                run,
                status: .pending,
                modelContext: context
            )
        }

        let endedAt = Date(timeIntervalSince1970: 42)
        try controller.updateRun(
            run,
            status: .succeeded,
            summary: "Final result",
            endedAt: endedAt,
            modelContext: context
        )

        #expect(
            throws: CoreAIProjectLibraryError.invalidRunStatusTransition(
                from: .succeeded,
                to: .running
            )
        ) {
            try controller.updateRun(
                run,
                status: .running,
                summary: "Mutated",
                modelContext: context
            )
        }
        #expect(run.status == .succeeded)
        #expect(run.summary == "Final result")
        #expect(run.endedAt == endedAt)
    }

    @Test
    func pendingRunMustEnterRunningBeforeATerminalStatus() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let project = try controller.createProject(
            named: "Pending run lifecycle",
            modelContext: context
        )
        let run = try controller.createRun(
            kind: .inference,
            in: project,
            modelContext: context
        )

        #expect(
            throws: CoreAIProjectLibraryError.invalidRunStatusTransition(
                from: .pending,
                to: .succeeded
            )
        ) {
            try controller.updateRun(
                run,
                status: .succeeded,
                modelContext: context
            )
        }
        #expect(run.status == .pending)
        #expect(run.endedAt == nil)
    }

    @Test
    func terminalRunsMustTransitionThroughUpdate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let project = try controller.createProject(
            named: "Run transitions",
            modelContext: context
        )

        #expect(throws: CoreAIProjectLibraryError.terminalRunRequiresUpdate) {
            _ = try controller.createRun(
                kind: .inference,
                status: .succeeded,
                in: project,
                modelContext: context
            )
        }
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
            ProjectArtifactLink.self,
            CoreAIRecipeRevisionRecord.self,
            CoreAITargetProfileRecord.self,
            CoreAIRunRecord.self,
            CoreAIEvidenceRecord.self
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
