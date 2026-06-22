import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import CoreAILab

@MainActor
struct CoreAIProjectLibraryMetadataTests {
    @Test
    func resourceFolderImportPersistsDeterministicFileMetadataAndProvenance() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "Tokenizer", directoryHint: .isDirectory)
        let nested = source.appending(path: "vocab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let configData = Data("{\"normalizer\":\"nfc\"}".utf8)
        let vocabData = Data("hello\nworld\n".utf8)
        try configData.write(to: source.appending(path: "config.json"))
        try vocabData.write(to: nested.appending(path: "tokens.txt"))

        let store = CoreAIArtifactStore(rootURL: directory.appending(path: "store"))
        let controller = CoreAIProjectLibraryController(artifactStore: store)
        let container = try makeContainer()
        let project = try controller.createProject(
            named: "Resources",
            modelContext: container.mainContext
        )

        let link = try await controller.importArtifact(
            from: source,
            into: project,
            modelContext: container.mainContext
        )
        let artifact = try #require(link.artifact)
        let snapshot = try #require(try artifact.decodedResourceSnapshot())

        #expect(artifact.kind == .resourceBundle)
        #expect(snapshot.directories == ["vocab"])
        #expect(snapshot.files.map(\.relativePath) == ["config.json", "vocab/tokens.txt"])
        #expect(snapshot.files.map(\.sha256Digest) == [
            digest(configData),
            digest(vocabData)
        ])
        #expect(snapshot.byteCount == Int64(configData.count + vocabData.count))
        #expect(link.provenance?.kind == .localFile)
        #expect(link.provenance?.sourceLocation == source.path(percentEncoded: false))

        let duplicate = try await store.importArtifact(from: source)
        #expect(duplicate.resourceSnapshot == snapshot)
        #expect(duplicate.sha256Digest == artifact.sha256Digest)
    }

    @Test
    func resourceFolderRejectsUnsafeRelativePaths() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "Unsafe", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("unsafe".utf8).write(to: source.appending(path: "bad\\name.txt"))
        let store = CoreAIArtifactStore(rootURL: directory.appending(path: "store"))

        await #expect(throws: CoreAIArtifactStoreError.unsafeRelativePath("bad\\name.txt")) {
            try await store.importArtifact(from: source)
        }
    }

    @Test
    func descriptorAndEditedProvenanceSurvivePersistentStoreReopen() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appending(path: "third-party.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let storeURL = directory.appending(path: "projects.store")
        let artifactRoot = directory.appending(path: "artifacts")
        let projectID: UUID

        do {
            let container = try CoreAIProjectModelContainer.makePersistent(storeURL: storeURL)
            let controller = CoreAIProjectLibraryController(
                artifactStore: CoreAIArtifactStore(rootURL: artifactRoot)
            )
            let project = try controller.createProject(
                named: "Third Party",
                modelContext: container.mainContext
            )
            projectID = project.id
            let link = try await controller.importArtifact(
                from: source,
                into: project,
                modelContext: container.mainContext
            )
            let artifact = try #require(link.artifact)
            let report = descriptorReport(url: try controller.validatedStoredURL(for: artifact))
            try controller.recordDescriptorSnapshot(
                report,
                for: link,
                modelContext: container.mainContext
            )
            try controller.updateSourceProvenance(
                for: link,
                kind: .sourceRepository,
                sourceLocation: "https://example.com/models/demo",
                providerName: "Example Research",
                licenseName: "Apache-2.0",
                notes: "Pinned at revision abc123.",
                modelContext: container.mainContext
            )
            try await controller.recordSpecializationCache(
                CoreAISpecializationResult(
                    configuration: CoreAISpecializationConfiguration(
                        profile: .cpuOnly,
                        expectFrequentReshapes: true
                    ),
                    artifactDigest: testArtifactDigest,
                    duration: .milliseconds(3),
                    loadedFromCache: false,
                    functionNames: ["main"],
                    bookmarkData: Data()
                ),
                sourceURL: try controller.validatedStoredURL(for: artifact),
                for: link,
                modelContext: container.mainContext
            )
        }

        do {
            let container = try CoreAIProjectModelContainer.makePersistent(storeURL: storeURL)
            let project = try #require(
                try container.mainContext.fetch(FetchDescriptor<LabProject>()).first
            )
            let link = try #require(project.artifactLinks.first)
            let artifact = try #require(link.artifact)
            let descriptor = try #require(try artifact.decodedDescriptorSnapshot())

            #expect(project.id == projectID)
            #expect(descriptor.functions.map(\.name) == ["encode", "main"])
            #expect(descriptor.functions[1].inputs.map(\.name) == ["mask", "tokens"])
            #expect(descriptor.storageTypes == [
                CoreAIAssetStorageTypeSummary(typeName: "Float16", count: 2),
                CoreAIAssetStorageTypeSummary(typeName: "Int8", count: 1)
            ])
            #expect(descriptor.computeTypes == ["Float16", "Int8"])
            #expect(descriptor.operationDistribution == [
                CoreAIAssetOperationCount(operationName: "add", count: 4),
                CoreAIAssetOperationCount(operationName: "matmul", count: 2)
            ])
            #expect(link.provenance?.kind == .sourceRepository)
            #expect(link.provenance?.providerName == "Example Research")
            #expect(link.provenance?.licenseName == "Apache-2.0")
            #expect(link.provenance?.notes == "Pinned at revision abc123.")
            #expect(link.specializationCaches.count == 1)
            #expect(link.specializationCaches.first?.configuration
                == CoreAISpecializationConfiguration(
                    profile: .cpuOnly,
                    expectFrequentReshapes: true
                ))
        }
    }

    @Test
    func descriptorSnapshotRejectsAReportForAnotherURL() async throws {
        let fixture = try await importedModelFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let wrongURL = fixture.directory.appending(path: "other.aimodel")
        let project = try #require(fixture.link.project)
        let artifact = try #require(fixture.link.artifact)
        let originalUpdatedAt = project.updatedAt

        #expect(throws: CoreAIProjectLibraryError.descriptorSourceMismatch) {
            try fixture.controller.recordDescriptorSnapshot(
                descriptorReport(url: wrongURL),
                for: fixture.link,
                modelContext: fixture.container.mainContext
            )
        }
        #expect(artifact.descriptorSnapshotData == nil)
        #expect(project.updatedAt == originalUpdatedAt)
        #expect(!fixture.container.mainContext.hasChanges)
    }

    @Test
    func foreignProjectContextRejectsMetadataMutationsWithoutSaving() async throws {
        let fixture = try await importedModelFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let foreignContainer = try makeContainer()
        let foreignProject = try fixture.controller.createProject(
            named: "Foreign",
            modelContext: foreignContainer.mainContext
        )
        let sourceProject = try #require(fixture.link.project)
        let artifact = try #require(fixture.link.artifact)
        let provenance = try #require(fixture.link.provenance)
        let sourceUpdatedAt = sourceProject.updatedAt
        let foreignUpdatedAt = foreignProject.updatedAt
        let provenanceUpdatedAt = provenance.updatedAt
        let report = descriptorReport(
            url: try fixture.controller.validatedStoredURL(for: artifact)
        )
        let result = specializationResult(
            configuration: CoreAISpecializationConfiguration(profile: .cpuOnly)
        )

        #expect(throws: CoreAIProjectLibraryError.artifactUnavailable) {
            try fixture.controller.recordDescriptorSnapshot(
                report,
                for: fixture.link,
                modelContext: foreignContainer.mainContext
            )
        }
        #expect(throws: CoreAIProjectLibraryError.artifactUnavailable) {
            try fixture.controller.updateSourceProvenance(
                for: fixture.link,
                kind: .sourceRepository,
                sourceLocation: "https://example.com/foreign",
                providerName: "Foreign",
                licenseName: "Unknown",
                notes: "Must not persist.",
                modelContext: foreignContainer.mainContext
            )
        }
        await #expect(throws: CoreAIProjectLibraryError.artifactUnavailable) {
            try await fixture.controller.recordSpecializationCache(
                result,
                sourceURL: report.url,
                for: fixture.link,
                modelContext: foreignContainer.mainContext
            )
        }

        #expect(artifact.descriptorSnapshotData == nil)
        #expect(provenance.updatedAt == provenanceUpdatedAt)
        #expect(fixture.link.specializationCaches.isEmpty)
        #expect(sourceProject.updatedAt == sourceUpdatedAt)
        #expect(foreignProject.updatedAt == foreignUpdatedAt)
        #expect(!fixture.container.mainContext.hasChanges)
        #expect(!foreignContainer.mainContext.hasChanges)
        #expect(try foreignContainer.mainContext.fetch(
            FetchDescriptor<ModelArtifactRecord>()
        ).isEmpty)
    }

    @Test
    func malformedProvenanceDoesNotMutateOrSave() async throws {
        let fixture = try await importedModelFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let project = try #require(fixture.link.project)
        let provenance = try #require(fixture.link.provenance)
        let originalProjectUpdatedAt = project.updatedAt
        let originalProvenanceUpdatedAt = provenance.updatedAt
        let originalSourceLocation = provenance.sourceLocation

        #expect(throws: CoreAIProjectLibraryError.invalidSourceProvenance(
            "enter a source location"
        )) {
            try fixture.controller.updateSourceProvenance(
                for: fixture.link,
                kind: .localFile,
                sourceLocation: "   ",
                providerName: "",
                licenseName: "",
                notes: "",
                modelContext: fixture.container.mainContext
            )
        }

        #expect(provenance.sourceLocation == originalSourceLocation)
        #expect(provenance.updatedAt == originalProvenanceUpdatedAt)
        #expect(project.updatedAt == originalProjectUpdatedAt)
        #expect(!fixture.container.mainContext.hasChanges)
    }

    @Test
    func legacyDescriptorSnapshotsDefaultMissingPublicStatistics() throws {
        let snapshot = CoreAIAssetDescriptorSnapshot(
            report: descriptorReport(url: URL(filePath: "/tmp/legacy.aimodel"))
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "storageTypes")
        object.removeValue(forKey: "operationDistribution")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            CoreAIAssetDescriptorSnapshot.self,
            from: legacyData
        )

        #expect(decoded.storageTypes.isEmpty)
        #expect(decoded.operationDistribution.isEmpty)
        try decoded.validate()
    }

    @Test
    func descriptorSnapshotRejectsInvalidPublicStatistics() {
        let invalidStorage = CoreAIAssetDescriptorSnapshot(report: CoreAIModelAssetReport(
            url: URL(filePath: "/tmp/invalid-storage.aimodel"),
            isValid: true,
            author: "",
            license: "",
            description: "",
            functions: [],
            storageTypes: [
                CoreAIAssetStorageTypeSummary(typeName: "Float16", count: -1)
            ],
            computeTypes: []
        ))
        let duplicateOperations = CoreAIAssetDescriptorSnapshot(report: CoreAIModelAssetReport(
            url: URL(filePath: "/tmp/duplicate-operations.aimodel"),
            isValid: true,
            author: "",
            license: "",
            description: "",
            functions: [],
            computeTypes: [],
            operationDistribution: [
                CoreAIAssetOperationCount(operationName: "add", count: 1),
                CoreAIAssetOperationCount(operationName: "add", count: 2)
            ]
        ))

        #expect(throws: CoreAIManifestValidationError.self) {
            try invalidStorage.validate()
        }
        #expect(throws: CoreAIManifestValidationError.self) {
            try duplicateOperations.validate()
        }
    }

    @Test
    func specializationCacheRecordsAreProjectOwnedUpsertedAndCleaned() async throws {
        let cacheManager = CoreAITestSpecializationCacheManager()
        let fixture = try await importedModelFixture(cacheManager: cacheManager)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let configuration = CoreAISpecializationConfiguration(
            profile: .cpuOnly,
            expectFrequentReshapes: true
        )
        let firstResult = CoreAISpecializationResult(
            configuration: configuration,
            artifactDigest: testArtifactDigest,
            duration: .milliseconds(10),
            loadedFromCache: false,
            functionNames: ["main"],
            bookmarkData: Data()
        )
        let cachedResult = CoreAISpecializationResult(
            configuration: configuration,
            artifactDigest: testArtifactDigest,
            duration: .milliseconds(1),
            loadedFromCache: true,
            functionNames: ["main"],
            bookmarkData: Data()
        )

        try await fixture.controller.recordSpecializationCache(
            firstResult,
            sourceURL: try fixture.controller.validatedStoredURL(
                for: #require(fixture.link.artifact)
            ),
            for: fixture.link,
            modelContext: fixture.container.mainContext
        )
        let record = try #require(fixture.link.specializationCaches.first)
        let createdAt = record.createdAt
        try await fixture.controller.recordSpecializationCache(
            cachedResult,
            sourceURL: try fixture.controller.validatedStoredURL(
                for: #require(fixture.link.artifact)
            ),
            for: fixture.link,
            modelContext: fixture.container.mainContext
        )

        #expect(fixture.link.specializationCaches.count == 1)
        #expect(record.createdAt == createdAt)
        #expect(record.wasLoadedFromCache)
        #expect(record.project?.id == fixture.link.project?.id)

        try await fixture.controller.removeSpecializationCache(
            record,
            modelContext: fixture.container.mainContext
        )

        #expect(fixture.link.specializationCaches.isEmpty)
        let removals = await cacheManager.removedEntries
        let expectedURL = try fixture.controller.validatedStoredURL(
            for: #require(fixture.link.artifact)
        )
        #expect(removals.count == 1)
        #expect(removals.first?.url == expectedURL)
        #expect(removals.first?.configuration == configuration)
    }

    @Test
    func deletingLastArtifactReferenceCleansOwnedCoreAICache() async throws {
        let cacheManager = CoreAITestSpecializationCacheManager()
        let fixture = try await importedModelFixture(cacheManager: cacheManager)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let result = CoreAISpecializationResult(
            configuration: CoreAISpecializationConfiguration(profile: .automatic),
            artifactDigest: testArtifactDigest,
            duration: .milliseconds(2),
            loadedFromCache: false,
            functionNames: ["main"],
            bookmarkData: Data()
        )
        try await fixture.controller.recordSpecializationCache(
            result,
            sourceURL: try fixture.controller.validatedStoredURL(
                for: #require(fixture.link.artifact)
            ),
            for: fixture.link,
            modelContext: fixture.container.mainContext
        )

        try await fixture.controller.removeArtifactLink(
            fixture.link,
            modelContext: fixture.container.mainContext
        )

        let removedAssetURLs = await cacheManager.removedAssetURLs
        #expect(removedAssetURLs.count == 1)
    }

    @Test
    func failedCoreAICacheDeletionKeepsTheProjectRecordRetryable() async throws {
        let cacheManager = CoreAITestSpecializationCacheManager()
        let fixture = try await importedModelFixture(cacheManager: cacheManager)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let result = CoreAISpecializationResult(
            configuration: CoreAISpecializationConfiguration(profile: .automatic),
            artifactDigest: testArtifactDigest,
            duration: .milliseconds(2),
            loadedFromCache: false,
            functionNames: ["main"],
            bookmarkData: Data()
        )
        let sourceURL = try fixture.controller.validatedStoredURL(
            for: #require(fixture.link.artifact)
        )
        try await fixture.controller.recordSpecializationCache(
            result,
            sourceURL: sourceURL,
            for: fixture.link,
            modelContext: fixture.container.mainContext
        )
        let record = try #require(fixture.link.specializationCaches.first)
        await cacheManager.rejectRemovals()

        await #expect(throws: CocoaError.self) {
            try await fixture.controller.removeSpecializationCache(
                record,
                modelContext: fixture.container.mainContext
            )
        }

        #expect(fixture.link.specializationCaches.map(\.id) == [record.id])
        #expect(fixture.controller.activeProjectID == nil)
    }

    @Test
    func sharedArtifactRetainsAConfigurationUntilItsLastProjectReferenceIsRemoved() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let cacheManager = CoreAITestSpecializationCacheManager()
        let container = try makeContainer()
        let controller = CoreAIProjectLibraryController(
            artifactStore: CoreAIArtifactStore(rootURL: directory.appending(path: "store")),
            specializationCacheManager: cacheManager
        )
        let firstProject = try controller.createProject(
            named: "First",
            modelContext: container.mainContext
        )
        let secondProject = try controller.createProject(
            named: "Second",
            modelContext: container.mainContext
        )
        let firstLink = try await controller.importArtifact(
            from: source,
            into: firstProject,
            modelContext: container.mainContext
        )
        let secondLink = try await controller.importArtifact(
            from: source,
            into: secondProject,
            modelContext: container.mainContext
        )
        let artifact = try #require(firstLink.artifact)
        let sourceURL = try controller.validatedStoredURL(for: artifact)
        let result = CoreAISpecializationResult(
            configuration: CoreAISpecializationConfiguration(profile: .cpuOnly),
            artifactDigest: testArtifactDigest,
            duration: .milliseconds(2),
            loadedFromCache: false,
            functionNames: ["main"],
            bookmarkData: Data()
        )
        try await controller.recordSpecializationCache(
            result,
            sourceURL: sourceURL,
            for: firstLink,
            modelContext: container.mainContext
        )
        try await controller.recordSpecializationCache(
            result,
            sourceURL: sourceURL,
            for: secondLink,
            modelContext: container.mainContext
        )

        let firstRecord = try #require(firstLink.specializationCaches.first)
        try await controller.removeSpecializationCache(
            firstRecord,
            modelContext: container.mainContext
        )
        let explicitRemovalEntries = await cacheManager.removedEntries
        #expect(explicitRemovalEntries.isEmpty)
        #expect(secondLink.specializationCaches.count == 1)

        try await controller.removeArtifactLink(
            firstLink,
            modelContext: container.mainContext
        )
        let firstRemovedEntries = await cacheManager.removedEntries
        let firstRemovedAssetURLs = await cacheManager.removedAssetURLs
        #expect(firstRemovedEntries.isEmpty)
        #expect(firstRemovedAssetURLs.isEmpty)

        try await controller.removeArtifactLink(
            secondLink,
            modelContext: container.mainContext
        )
        let finalRemovedAssetURLs = await cacheManager.removedAssetURLs
        #expect(finalRemovedAssetURLs.count == 1)
    }

    @Test
    func duplicateContextCacheUpsertsConvergeOnDeterministicIdentity() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let container = try makeContainer()
        let store = CoreAIArtifactStore(rootURL: directory.appending(path: "store"))
        let setupController = CoreAIProjectLibraryController(artifactStore: store)
        let project = try setupController.createProject(
            named: "Identity",
            modelContext: container.mainContext
        )
        let importedLink = try await setupController.importArtifact(
            from: source,
            into: project,
            modelContext: container.mainContext
        )
        let linkID = importedLink.id
        let sourceURL = try setupController.validatedStoredURL(
            for: #require(importedLink.artifact)
        )
        let firstContext = ModelContext(container)
        let secondContext = ModelContext(container)
        let firstLink = try #require(
            try firstContext.fetch(FetchDescriptor<ProjectArtifactLink>())
                .first { $0.id == linkID }
        )
        let secondLink = try #require(
            try secondContext.fetch(FetchDescriptor<ProjectArtifactLink>())
                .first { $0.id == linkID }
        )
        let firstController = CoreAIProjectLibraryController(artifactStore: store)
        let secondController = CoreAIProjectLibraryController(artifactStore: store)
        let configuration = CoreAISpecializationConfiguration(
            profile: .preferGPU,
            expectFrequentReshapes: true
        )

        let firstUpsert = Task { @MainActor in
            try await firstController.recordSpecializationCache(
                specializationResult(configuration: configuration, loadedFromCache: false),
                sourceURL: sourceURL,
                for: firstLink,
                modelContext: firstContext
            )
        }
        let secondUpsert = Task { @MainActor in
            try await secondController.recordSpecializationCache(
                specializationResult(configuration: configuration, loadedFromCache: true),
                sourceURL: sourceURL,
                for: secondLink,
                modelContext: secondContext
            )
        }
        try await firstUpsert.value
        try await secondUpsert.value

        let verificationContext = ModelContext(container)
        let records = try verificationContext.fetch(
            FetchDescriptor<CoreAISpecializationCacheRecord>()
        )
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.identityKey == "\(linkID.uuidString.lowercased()):preferGPU:reshape")
    }

    @Test
    func concurrentLastReferenceRemovalsCannotOrphanArtifactStorage() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let container = try makeContainer()
        let store = CoreAIArtifactStore(rootURL: directory.appending(path: "store"))
        let cacheManager = CoreAITestSpecializationCacheManager()
        let setupController = CoreAIProjectLibraryController(
            artifactStore: store,
            specializationCacheManager: cacheManager
        )
        let firstProject = try setupController.createProject(
            named: "First",
            modelContext: container.mainContext
        )
        let secondProject = try setupController.createProject(
            named: "Second",
            modelContext: container.mainContext
        )
        let importedFirstLink = try await setupController.importArtifact(
            from: source,
            into: firstProject,
            modelContext: container.mainContext
        )
        let importedSecondLink = try await setupController.importArtifact(
            from: source,
            into: secondProject,
            modelContext: container.mainContext
        )
        let artifact = try #require(importedFirstLink.artifact)
        let storedURL = try setupController.validatedStoredURL(for: artifact)
        try await setupController.recordSpecializationCache(
            specializationResult(
                configuration: CoreAISpecializationConfiguration(profile: .cpuOnly)
            ),
            sourceURL: storedURL,
            for: importedFirstLink,
            modelContext: container.mainContext
        )
        try await setupController.recordSpecializationCache(
            specializationResult(
                configuration: CoreAISpecializationConfiguration(profile: .preferGPU)
            ),
            sourceURL: storedURL,
            for: importedSecondLink,
            modelContext: container.mainContext
        )
        await cacheManager.delayRemovals(by: .milliseconds(25))

        let firstContext = ModelContext(container)
        let secondContext = ModelContext(container)
        let firstLink = try #require(
            try firstContext.fetch(FetchDescriptor<ProjectArtifactLink>())
                .first { $0.id == importedFirstLink.id }
        )
        let secondLink = try #require(
            try secondContext.fetch(FetchDescriptor<ProjectArtifactLink>())
                .first { $0.id == importedSecondLink.id }
        )
        let firstController = CoreAIProjectLibraryController(
            artifactStore: store,
            specializationCacheManager: cacheManager
        )
        let secondController = CoreAIProjectLibraryController(
            artifactStore: store,
            specializationCacheManager: cacheManager
        )

        let firstRemoval = Task { @MainActor in
            try await firstController.removeArtifactLink(
                firstLink,
                modelContext: firstContext
            )
        }
        let secondRemoval = Task { @MainActor in
            try await secondController.removeArtifactLink(
                secondLink,
                modelContext: secondContext
            )
        }
        try await firstRemoval.value
        try await secondRemoval.value

        let verificationContext = ModelContext(container)
        #expect(try verificationContext.fetch(FetchDescriptor<ProjectArtifactLink>()).isEmpty)
        #expect(try verificationContext.fetch(FetchDescriptor<ModelArtifactRecord>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))
    }

    @Test
    func symlinkedStoredParentBlocksReadAndCacheRemovalWithoutTouchingOutside() async throws {
        let cacheManager = CoreAITestSpecializationCacheManager()
        let fixture = try await importedModelFixture(cacheManager: cacheManager)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let artifact = try #require(fixture.link.artifact)
        let configuration = CoreAISpecializationConfiguration(profile: .automatic)
        try await fixture.controller.recordSpecializationCache(
            specializationResult(configuration: configuration),
            sourceURL: try fixture.controller.validatedStoredURL(for: artifact),
            for: fixture.link,
            modelContext: fixture.container.mainContext
        )
        let record = try #require(fixture.link.specializationCaches.first)
        let storeRoot = fixture.directory.appending(path: "store", directoryHint: .isDirectory)
        let contentAddressedRoot = storeRoot.appending(path: "sha256", directoryHint: .isDirectory)
        let outsideRoot = fixture.directory.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.removeItem(at: contentAddressedRoot)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        let markerURL = outsideRoot.appending(path: "keep-me")
        try Data("outside".utf8).write(to: markerURL)
        try FileManager.default.createSymbolicLink(
            at: contentAddressedRoot,
            withDestinationURL: outsideRoot
        )

        #expect(throws: CoreAIArtifactStoreError.self) {
            _ = try fixture.controller.validatedStoredURL(for: artifact)
        }
        await #expect(throws: CoreAIArtifactStoreError.self) {
            try await fixture.controller.removeSpecializationCache(
                record,
                modelContext: fixture.container.mainContext
            )
        }

        #expect(FileManager.default.fileExists(atPath: markerURL.path))
        #expect(fixture.link.specializationCaches.map(\.id) == [record.id])
        #expect(await cacheManager.removedEntries.isEmpty)
        #expect(await cacheManager.removedAssetURLs.isEmpty)
    }

    @Test
    func xcodePublicSummaryStatisticsAreCaptured() throws {
        let report = try CoreAIModelAssetInspector.inspect(
            url: CoreAITestFixtures.tensorModelURL(),
            includingStatistics: true
        )

        #expect(!report.storageTypes.isEmpty)
        #expect(report.storageTypes.allSatisfy { !$0.typeName.isEmpty && $0.count >= 0 })
        #expect(!report.operationDistribution.isEmpty)
        #expect(report.operationDistribution.allSatisfy {
            !$0.operationName.isEmpty && $0.count >= 0
        })
    }

    private func importedModelFixture(
        cacheManager: any CoreAISpecializationCacheManaging = CoreAITestSpecializationCacheManager()
    ) async throws -> (
        directory: URL,
        container: ModelContainer,
        controller: CoreAIProjectLibraryController,
        link: ProjectArtifactLink
    ) {
        let directory = temporaryDirectory()
        let source = directory.appending(path: "model.aimodel", directoryHint: .isDirectory)
        try makeModelFixture(at: source)
        let container = try makeContainer()
        let controller = CoreAIProjectLibraryController(
            artifactStore: CoreAIArtifactStore(rootURL: directory.appending(path: "store")),
            specializationCacheManager: cacheManager
        )
        let project = try controller.createProject(
            named: "Model",
            modelContext: container.mainContext
        )
        let link = try await controller.importArtifact(
            from: source,
            into: project,
            modelContext: container.mainContext
        )
        return (
            directory: directory,
            container: container,
            controller: controller,
            link: link
        )
    }

    private func specializationResult(
        configuration: CoreAISpecializationConfiguration,
        loadedFromCache: Bool = false
    ) -> CoreAISpecializationResult {
        CoreAISpecializationResult(
            configuration: configuration,
            artifactDigest: testArtifactDigest,
            duration: .milliseconds(1),
            loadedFromCache: loadedFromCache,
            functionNames: ["main"],
            bookmarkData: Data()
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            LabProject.self,
            ModelArtifactRecord.self,
            ProjectArtifactLink.self,
            CoreAISourceProvenanceRecord.self,
            CoreAISpecializationCacheRecord.self,
            CoreAIRecipeRevisionRecord.self,
            CoreAITargetProfileRecord.self,
            CoreAIRunRecord.self,
            CoreAIEvidenceRecord.self
        ])
        let configuration = ModelConfiguration(
            "CoreAIProjectLibraryMetadataTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private var testArtifactDigest: CoreAIArtifactDigest {
        CoreAIArtifactDigesterStub().artifactDigest
    }

    private func descriptorReport(url: URL) -> CoreAIModelAssetReport {
        CoreAIModelAssetReport(
            url: url,
            isValid: true,
            author: "Example Research",
            license: "Apache-2.0",
            description: "A generic third-party model.",
            functions: [
                CoreAIAssetFunctionSignature(
                    name: "main",
                    inputs: [
                        CoreAIAssetValueSignature(name: "tokens", typeName: "Int32[1, 8]"),
                        CoreAIAssetValueSignature(name: "mask", typeName: "Int32[1, 8]")
                    ],
                    states: [],
                    outputs: [
                        CoreAIAssetValueSignature(name: "hidden", typeName: "Float16[1, 8, 32]")
                    ]
                ),
                CoreAIAssetFunctionSignature(
                    name: "encode",
                    inputs: [],
                    states: [],
                    outputs: []
                )
            ],
            storageTypes: [
                CoreAIAssetStorageTypeSummary(typeName: "Int8", count: 1),
                CoreAIAssetStorageTypeSummary(typeName: "Float16", count: 2)
            ],
            computeTypes: ["Int8", "Float16", "Int8"],
            operationDistribution: [
                CoreAIAssetOperationCount(operationName: "matmul", count: 2),
                CoreAIAssetOperationCount(operationName: "add", count: 4)
            ]
        )
    }

    private func makeModelFixture(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: url.appending(path: "main.mlirb"))
        try Data("{}".utf8).write(to: url.appending(path: "metadata.json"))
    }

    private func digest(_ data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(SHA256.byteCount * 2)
        for byte in SHA256.hash(data: data) {
            output.append(digits[Int(byte >> 4)])
            output.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: output, as: UTF8.self)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "CoreAIProjectLibraryMetadataTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}
