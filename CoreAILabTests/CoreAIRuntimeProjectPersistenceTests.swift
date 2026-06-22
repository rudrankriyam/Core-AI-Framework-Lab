import Foundation
import SwiftData
import Testing
@testable import CoreAILab

@MainActor
struct CoreAIRuntimeProjectPersistenceTests {
    @Test
    func successfulRunPersistsTimingMetricWithoutFabricatingAnOutputArtifact() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let project = try controller.createProject(
            named: "Runtime Evidence",
            modelContext: context
        )
        let persistence = CoreAIProjectRunPersistence(
            project: project,
            modelContext: context,
            controller: controller
        )
        var dates = [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 101.25)
        ]
        var monotonicTimes = [100.0, 101.25]
        let coordinator = CoreAIRunLifecycleCoordinator(
            persistence: persistence,
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() }
        )
        let runContext = CoreAIRuntimeRunContext.workspaceDefault(
            experienceID: "audio",
            title: "Audio",
            modelIdentifier: "wav2vec2-base"
        )

        let token = coordinator.start(
            context: runContext,
            modelIdentity: "wav2vec2.aimodel"
        )
        coordinator.succeed(token, summary: "Transcribed locally")

        let run = try #require(
            try context.fetch(FetchDescriptor<CoreAIRunRecord>()).first
        )
        let evidenceRecords = try context.fetch(
            FetchDescriptor<CoreAIEvidenceRecord>()
        )
        let evidence = try #require(
            evidenceRecords.first { $0.kind == .metric }
        )
        let provenance = try #require(
            evidenceRecords.first { $0.kind == .validation }
        )
        #expect(run.status == .succeeded)
        #expect(run.summary == "Transcribed locally")
        #expect(evidence.kind == .metric)
        #expect(evidence.relativePath == nil)
        #expect(evidence.sha256Digest == nil)
        #expect(evidence.mediaType == nil)
        let metadata = try evidence.decodedMetadata()
        #expect(metadata["timing_class"] == "cold")
        #expect(metadata["duration_seconds"] == "1.25")
        #expect(metadata["model_identifier"] == "wav2vec2.aimodel")
        #expect(metadata["recipe_provenance"] == "unattributed")
        #expect(
            try provenance.decodedMetadata()["recipe_provenance"]
                == "unattributed"
        )
        #expect(evidenceRecords.allSatisfy { $0.kind != .output })
    }

    @Test
    func failedRunPersistsItsTerminalStateWithoutOutputEvidence() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let project = try controller.createProject(
            named: "Failed Runtime Run",
            modelContext: context
        )
        let persistence = CoreAIProjectRunPersistence(
            project: project,
            modelContext: context,
            controller: controller
        )
        var dates = [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 2)]
        var monotonicTimes = [1.0, 2.0]
        let coordinator = CoreAIRunLifecycleCoordinator(
            persistence: persistence,
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() }
        )
        let token = coordinator.start(
            context: .workspaceDefault(
                experienceID: "vision",
                title: "Vision",
                modelIdentifier: "vision-model"
            ),
            modelIdentity: "vision.aimodel"
        )

        coordinator.fail(token, error: RuntimePersistenceFixtureError.failed)

        let runs = try context.fetch(FetchDescriptor<CoreAIRunRecord>())
        let evidence = try context.fetch(FetchDescriptor<CoreAIEvidenceRecord>())
        let provenanceMetadata = try #require(evidence.first).decodedMetadata()
        #expect(runs.first?.status == .failed)
        #expect(runs.first?.summary == "Fixture runtime failed.")
        #expect(evidence.count == 1)
        #expect(evidence.first?.kind == .validation)
        #expect(provenanceMetadata["recipe_provenance"] == "unattributed")
        #expect(evidence.allSatisfy { $0.kind != .output })
    }

    @Test
    func selectedRecipeIntentIsPersistedAsUnverifiedAndNeverLinked() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let controller = CoreAIProjectLibraryController()
        let project = try controller.createProject(
            named: "Unverified Recipe Intent",
            modelContext: context
        )
        _ = try controller.addRecipeRevision(
            ChatterboxRecipeFixture.manifest,
            to: project,
            modelContext: context
        )
        let persistence = CoreAIProjectRunPersistence(
            project: project,
            modelContext: context,
            controller: controller
        )
        var dates = [Date(timeIntervalSince1970: 10), Date(timeIntervalSince1970: 11)]
        var monotonicTimes = [10.0, 11.0]
        let coordinator = CoreAIRunLifecycleCoordinator(
            persistence: persistence,
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() }
        )
        let manifest = ChatterboxRecipeFixture.manifest
        let runContext = CoreAIRuntimeRunContext(
            experienceID: "selected-recipe",
            experienceTitle: "Selected Recipe",
            recipeIdentifier: manifest.id,
            recipeRevision: manifest.revision,
            recipeProvenance: .unverifiedIntent,
            comparisonIdentity: CoreAIRuntimeComparisonIdentity(
                experienceID: "selected-recipe",
                modelIdentifier: "fixture-model",
                displayName: "Selected Recipe"
            )
        )

        let token = coordinator.start(
            context: runContext,
            modelIdentity: "fixture-model.aimodel"
        )
        coordinator.succeed(token, summary: "Finished")

        let run = try #require(
            try context.fetch(FetchDescriptor<CoreAIRunRecord>()).first
        )
        let evidenceRecords = try context.fetch(
            FetchDescriptor<CoreAIEvidenceRecord>()
        )
        let evidence = try #require(
            evidenceRecords.first { $0.kind == .validation }
        )
        let metadata = try evidence.decodedMetadata()
        #expect(run.recipeRevision == nil)
        #expect(metadata["recipe_provenance"] == "unverified_intent")
        #expect(metadata["intended_recipe_identifier"] == manifest.id)
        #expect(metadata["intended_recipe_revision"] == manifest.revision)
        #expect(metadata["recipe_identifier"] == nil)
        #expect(evidenceRecords.allSatisfy { $0.kind != .output })
    }

    @Test
    func startFailureRemainsRetryableBeforeTheRunFinishes() throws {
        try verifyStartRetry(
            after: .startFailureBeforeCommit,
            retryBeforeFinish: true
        )
    }

    @Test
    func ambiguousStartSaveFinishesExactlyOnePersistentRun() throws {
        try verifyStartRetry(
            after: .reportedStartFailureAfterCommit,
            retryBeforeFinish: false
        )
    }

    @Test
    func repositoryRestartRecoversInterruptedRunningRecordsExactlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "CoreAIRuntimeRecoveryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "projects.store")
        let runID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000099")
        )
        let projectID: UUID

        do {
            let container = try CoreAIProjectModelContainer.makePersistent(
                storeURL: storeURL
            )
            let context = container.mainContext
            let controller = CoreAIProjectLibraryController()
            let project = try controller.createProject(
                named: "Interrupted Runtime Run",
                modelContext: context
            )
            projectID = project.id
            let persistence = CoreAIProjectRunPersistence(
                project: project,
                modelContext: context,
                controller: controller
            )
            let start = CoreAIRuntimeRunStart(
                id: runID,
                context: .workspaceDefault(
                    experienceID: "interrupted",
                    title: "Interrupted",
                    modelIdentifier: "fixture"
                ),
                modelIdentity: "fixture.aimodel",
                timingClass: .cold,
                selectedComparisonIdentity: nil,
                startedAt: Date(timeIntervalSince1970: 30)
            )
            _ = try persistence.startRun(start: start)
        }

        do {
            let reopenedContainer = try CoreAIProjectModelContainer.makePersistent(
                storeURL: storeURL
            )
            let context = reopenedContainer.mainContext
            let project = try #require(
                try context.fetch(FetchDescriptor<LabProject>())
                    .first { $0.id == projectID }
            )
            let restartedPersistence = CoreAIProjectRunPersistence(
                project: project,
                modelContext: context
            )
            let recoveredAt = Date(timeIntervalSince1970: 40)
            let recoveredCount = try restartedPersistence.recoverInterruptedRuns(
                endedAt: recoveredAt
            )
            let secondRecoveryCount = try restartedPersistence.recoverInterruptedRuns(
                endedAt: Date(timeIntervalSince1970: 50)
            )

            let runs = try context.fetch(FetchDescriptor<CoreAIRunRecord>())
            let run = try #require(runs.first)
            #expect(recoveredCount == 1)
            #expect(secondRecoveryCount == 0)
            #expect(runs.count == 1)
            #expect(run.id == runID)
            #expect(run.status == .failed)
            #expect(run.endedAt == recoveredAt)
            #expect(
                run.summary
                    == "Run was interrupted before completion and recovered when project recording resumed."
            )
        }
    }

    @Test
    func evidenceFailureRetainsTheTerminalWriteForRetry() throws {
        try verifyRetry(after: .evidenceFailureBeforeCommit)
    }

    @Test
    func reportedSaveFailureAfterCommitRetriesWithoutDuplicatingTheMetric() throws {
        try verifyRetry(after: .reportedSaveFailureAfterCommit)
    }

    private func verifyStartRetry(
        after failure: ProjectRunWriterFailureMode,
        retryBeforeFinish: Bool
    ) throws {
        let container = try makeContainer()
        let context = container.mainContext
        let libraryController = CoreAIProjectLibraryController()
        let project = try libraryController.createProject(
            named: "Retryable Runtime Start",
            modelContext: context
        )
        let writer = ProjectRunWriterFailureFixture(
            controller: libraryController,
            failureMode: failure
        )
        let persistence = CoreAIProjectRunPersistence(
            project: project,
            modelContext: context,
            controller: writer
        )
        var dates = [Date(timeIntervalSince1970: 20), Date(timeIntervalSince1970: 21)]
        var monotonicTimes = [20.0, 21.0]
        let coordinator = CoreAIRunLifecycleCoordinator(
            persistence: persistence,
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() }
        )
        let token = coordinator.start(
            context: .workspaceDefault(
                experienceID: "retryable-start",
                title: "Retryable Start",
                modelIdentifier: "fixture"
            ),
            modelIdentity: "fixture.aimodel"
        )

        #expect(coordinator.hasPendingPersistenceWrites)
        #expect(writer.startAttempts == 1)
        if retryBeforeFinish {
            coordinator.retryPendingPersistence()
            #expect(!coordinator.hasPendingPersistenceWrites)
            #expect(writer.startAttempts == 2)
        }

        coordinator.succeed(token, summary: "Finished after a start retry")

        let runs = try context.fetch(FetchDescriptor<CoreAIRunRecord>())
        let evidence = try context.fetch(FetchDescriptor<CoreAIEvidenceRecord>())
        #expect(!coordinator.hasPendingPersistenceWrites)
        #expect(coordinator.persistenceMessage == nil)
        #expect(coordinator.history.count == 1)
        #expect(coordinator.history.first?.id == token.id)
        #expect(writer.startAttempts == 2)
        #expect(writer.finishAttempts == 1)
        #expect(runs.count == 1)
        #expect(runs.first?.id == token.id)
        #expect(runs.first?.status == .succeeded)
        #expect(evidence.filter { $0.kind == .validation }.count == 1)
        #expect(evidence.filter { $0.kind == .metric }.count == 1)
    }

    private func verifyRetry(
        after failure: ProjectRunWriterFailureMode
    ) throws {
        let container = try makeContainer()
        let context = container.mainContext
        let libraryController = CoreAIProjectLibraryController()
        let project = try libraryController.createProject(
            named: "Retryable Runtime Run",
            modelContext: context
        )
        let writer = ProjectRunWriterFailureFixture(
            controller: libraryController,
            failureMode: failure
        )
        let persistence = CoreAIProjectRunPersistence(
            project: project,
            modelContext: context,
            controller: writer
        )
        var dates = [Date(timeIntervalSince1970: 20), Date(timeIntervalSince1970: 21)]
        var monotonicTimes = [20.0, 21.0]
        let coordinator = CoreAIRunLifecycleCoordinator(
            persistence: persistence,
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() }
        )
        let token = coordinator.start(
            context: .workspaceDefault(
                experienceID: "retryable",
                title: "Retryable",
                modelIdentifier: "fixture"
            ),
            modelIdentity: "fixture.aimodel"
        )

        coordinator.succeed(token, summary: "Finished once")

        #expect(coordinator.hasPendingPersistenceWrites)
        #expect(writer.finishAttempts == 1)

        coordinator.retryPendingPersistence()

        #expect(!coordinator.hasPendingPersistenceWrites)
        #expect(coordinator.persistenceMessage == nil)
        #expect(writer.finishAttempts == 2)
        let runs = try context.fetch(FetchDescriptor<CoreAIRunRecord>())
        let evidence = try context.fetch(FetchDescriptor<CoreAIEvidenceRecord>())
        let metrics = evidence.filter { $0.kind == .metric }
        #expect(runs.count == 1)
        #expect(runs.first?.status == .succeeded)
        #expect(evidence.count == 2)
        #expect(metrics.count == 1)
        #expect(metrics.first?.id == token.id)
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
            "CoreAIRuntimeProjectPersistenceTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private enum ProjectRunWriterFailureMode: Equatable {
    case startFailureBeforeCommit
    case reportedStartFailureAfterCommit
    case evidenceFailureBeforeCommit
    case reportedSaveFailureAfterCommit
}

@MainActor
private final class ProjectRunWriterFailureFixture: CoreAIProjectRunWriting {
    private let controller: CoreAIProjectLibraryController
    private var failureMode: ProjectRunWriterFailureMode?
    private(set) var startAttempts = 0
    private(set) var finishAttempts = 0

    init(
        controller: CoreAIProjectLibraryController,
        failureMode: ProjectRunWriterFailureMode
    ) {
        self.controller = controller
        self.failureMode = failureMode
    }

    func createRuntimeRun(
        id: UUID,
        in project: LabProject,
        recipeRevision: CoreAIRecipeRevisionRecord?,
        provenanceEvidence: CoreAIRuntimeProvenanceEvidence,
        modelContext: ModelContext
    ) throws -> CoreAIRunRecord {
        startAttempts += 1
        let pendingFailure = failureMode
        if pendingFailure == .startFailureBeforeCommit {
            failureMode = nil
            throw ProjectRunWriterFixtureError.startWriteFailed
        }
        let run = try controller.createRuntimeRun(
            id: id,
            in: project,
            recipeRevision: recipeRevision,
            provenanceEvidence: provenanceEvidence,
            modelContext: modelContext
        )
        if pendingFailure == .reportedStartFailureAfterCommit {
            failureMode = nil
            throw ProjectRunWriterFixtureError.startSaveReportedFailure
        }
        return run
    }

    func finishRuntimeRun(
        _ run: CoreAIRunRecord,
        status: CoreAIRunStatus,
        summary: String,
        endedAt: Date,
        metricEvidence: CoreAIRuntimeMetricEvidence?,
        modelContext: ModelContext
    ) throws {
        finishAttempts += 1
        let pendingFailure = failureMode
        failureMode = nil

        if pendingFailure == .evidenceFailureBeforeCommit {
            throw ProjectRunWriterFixtureError.evidenceWriteFailed
        }
        try controller.finishRuntimeRun(
            run,
            status: status,
            summary: summary,
            endedAt: endedAt,
            metricEvidence: metricEvidence,
            modelContext: modelContext
        )
        if pendingFailure == .reportedSaveFailureAfterCommit {
            throw ProjectRunWriterFixtureError.saveReportedFailure
        }
    }

    func recoverInterruptedRuntimeRuns(
        in project: LabProject,
        endedAt: Date,
        modelContext: ModelContext
    ) throws -> Int {
        try controller.recoverInterruptedRuntimeRuns(
            in: project,
            endedAt: endedAt,
            modelContext: modelContext
        )
    }
}

private enum ProjectRunWriterFixtureError: LocalizedError {
    case startWriteFailed
    case startSaveReportedFailure
    case evidenceWriteFailed
    case saveReportedFailure

    var errorDescription: String? {
        switch self {
        case .startWriteFailed:
            "The run start write failed."
        case .startSaveReportedFailure:
            "The run start save reported failure after committing."
        case .evidenceWriteFailed:
            "The metric evidence write failed."
        case .saveReportedFailure:
            "The save reported failure after committing."
        }
    }
}
