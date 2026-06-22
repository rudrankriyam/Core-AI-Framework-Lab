import Darwin
import Foundation
import Testing
@testable import CoreAILab

struct CoreAIConversionJobStoreTests {
    @Test
    func fingerprintsBindVersionedMachineIdentityWithoutVolatileDiagnostics() throws {
        let original = try identity(
            environment: ["NO_COLOR": "1", "PYTHONUNBUFFERED": "1"]
        )
        let reordered = try identity(
            environment: ["PYTHONUNBUFFERED": "1", "NO_COLOR": "1"]
        )
        let changedArgument = try identity(arguments: ["export", "qwen", "--int4"])
        let changedOutput = try identity(outputName: "second")
        let changedEnvironment = try identity(xcodeBuild: "27A2")
        let changedSource = try identity(sourceDigestCharacter: "9")

        #expect(original.fingerprint == reordered.fingerprint)
        #expect(original.fingerprint.requestSHA256 != changedArgument.fingerprint.requestSHA256)
        #expect(original.fingerprint.requestSHA256 != changedOutput.fingerprint.requestSHA256)
        #expect(original.fingerprint.environmentSHA256 != changedEnvironment.fingerprint.environmentSHA256)
        #expect(original.fingerprint.environmentSHA256 != changedSource.fingerprint.environmentSHA256)
        #expect(original.fingerprint.requestSHA256.count == 64)
        #expect(original.environment.schemaVersion == 1)
    }

    @Test
    func transitionsPersistAndTerminalJobsCannotRestartInPlace() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreAIConversionJobStore(rootURL: root)
        let createdAt = Date(timeIntervalSince1970: 100)
        let record = try await store.createJob(
            identity: try identity(),
            now: createdAt
        )
        let running = try await store.transition(
            jobID: record.id,
            to: .running,
            now: Date(timeIntervalSince1970: 101)
        )
        let succeeded = try await store.transition(
            jobID: record.id,
            to: .succeeded,
            detail: "Created one artifact.",
            now: Date(timeIntervalSince1970: 102)
        )

        #expect(running.state == .running)
        #expect(succeeded.state == .succeeded)
        #expect(succeeded.statusDetail == "Created one artifact.")
        #expect(succeeded.attempt == 1)
        do {
            _ = try await store.transition(jobID: record.id, to: .running)
            Issue.record("Expected a terminal conversion job to reject restarting in place.")
        } catch is CoreAIConversionJobStoreError {
            // Expected.
        }

        let reopened = CoreAIConversionJobStore(rootURL: root)
        #expect(try await reopened.job(id: record.id) == succeeded)
    }

    @Test
    func interruptedAttemptRetriesAsANewAttempt() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreAIConversionJobStore(rootURL: root)
        let record = try await store.createJob(identity: try identity(modelName: "audio"))
        _ = try await store.transition(jobID: record.id, to: .running)
        let firstAttemptLog = try await store.appendLog(
            jobID: record.id,
            kind: .lifecycle,
            message: "attempt one"
        )
        _ = try await store.transition(jobID: record.id, to: .interrupted)
        let retry = try await store.transition(jobID: record.id, to: .queued)
        let secondAttemptLog = try await store.appendLog(
            jobID: record.id,
            kind: .lifecycle,
            message: "attempt two"
        )

        #expect(retry.state == .queued)
        #expect(retry.attempt == 2)
        #expect(firstAttemptLog.attempt == 1 && firstAttemptLog.sequence == 1)
        #expect(secondAttemptLog.attempt == 2 && secondAttemptLog.sequence == 1)
    }

    @Test
    func launchReconciliationInterruptsOnlyOrphanedActiveJobs() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreAIConversionJobStore(rootURL: root)
        let running = try await store.createJob(identity: try identity(modelName: "running"))
        let canceling = try await store.createJob(identity: try identity(modelName: "canceling"))
        let succeeded = try await store.createJob(identity: try identity(modelName: "succeeded"))
        _ = try await store.transition(jobID: running.id, to: .running)
        _ = try await store.transition(jobID: canceling.id, to: .running)
        _ = try await store.transition(jobID: canceling.id, to: .cancellationRequested)
        _ = try await store.transition(jobID: succeeded.id, to: .running)
        _ = try await store.transition(jobID: succeeded.id, to: .succeeded)

        let reconciled = try await store.reconcileInterruptedJobs(
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(Set(reconciled.map(\.id)) == Set([running.id, canceling.id]))
        #expect(reconciled.allSatisfy { $0.state == .interrupted })
        #expect(reconciled.allSatisfy { $0.statusDetail?.contains("does not claim") == true })
        #expect(try await store.job(id: succeeded.id).state == .succeeded)
    }

    @Test
    func structuredLogsAreAppendOnlyAndSurviveReopen() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreAIConversionJobStore(rootURL: root)
        let record = try await store.createJob(identity: try identity(modelName: "vision"))
        let firstID = UUID()
        let secondID = UUID()
        let first = try await store.appendLog(
            jobID: record.id,
            kind: .lifecycle,
            message: "started",
            now: Date(timeIntervalSince1970: 1),
            id: firstID
        )
        let second = try await store.appendLog(
            jobID: record.id,
            kind: .standardOutput,
            message: "saved artifact",
            now: Date(timeIntervalSince1970: 2),
            id: secondID
        )

        let reopened = CoreAIConversionJobStore(rootURL: root)
        #expect(try await reopened.logs(jobID: record.id) == [first, second])
        let data = try Data(
            contentsOf: root
                .appending(path: record.id.uuidString.lowercased())
                .appending(path: "events.jsonl")
        )
        #expect(data.last == 0x0A)
        #expect(data.split(separator: 0x0A).count == 2)
    }

    @Test
    func checkpointReuseRequiresExactRequestEnvironmentAndVerifiedArtifacts() throws {
        let current = fingerprint()
        let artifact = try CoreAIConversionCheckpointArtifact(
            relativePath: "models/qwen.aimodel",
            sha256: String(repeating: "a", count: 64),
            byteCount: 42
        )
        let jobID = UUID()
        let checkpoint = try CoreAIConversionCheckpoint(
            jobID: jobID,
            gate: "asset-saved",
            artifactRootPath: "/tmp/artifacts",
            fingerprint: current,
            artifacts: [artifact]
        )

        #expect(
            CoreAIConversionCheckpointReuseEvaluator.evaluate(
                checkpoint,
                expectedGate: "asset-saved",
                currentFingerprint: current,
                verifiedArtifacts: [artifact]
            ) == .reusable
        )
        #expect(
            CoreAIConversionCheckpointReuseEvaluator.evaluate(
                checkpoint,
                expectedGate: "smoke-inference",
                currentFingerprint: current,
                verifiedArtifacts: [artifact]
            ) == .gateChanged
        )
        #expect(
            CoreAIConversionCheckpointReuseEvaluator.evaluate(
                checkpoint,
                expectedGate: "asset-saved",
                currentFingerprint: .init(
                    requestSHA256: String(repeating: "b", count: 64),
                    environmentSHA256: current.environmentSHA256
                ),
                verifiedArtifacts: [artifact]
            ) == .requestChanged
        )
        #expect(
            CoreAIConversionCheckpointReuseEvaluator.evaluate(
                checkpoint,
                expectedGate: "asset-saved",
                currentFingerprint: .init(
                    requestSHA256: current.requestSHA256,
                    environmentSHA256: String(repeating: "c", count: 64)
                ),
                verifiedArtifacts: [artifact]
            ) == .environmentChanged
        )
        let changedArtifact = try CoreAIConversionCheckpointArtifact(
            relativePath: artifact.relativePath,
            sha256: String(repeating: "d", count: 64),
            byteCount: artifact.byteCount
        )
        #expect(
            CoreAIConversionCheckpointReuseEvaluator.evaluate(
                checkpoint,
                expectedGate: "asset-saved",
                currentFingerprint: current,
                verifiedArtifacts: [changedArtifact]
            ) == .artifactsChanged
        )
    }

    @Test
    func checkpointStoreRoundTripsAndRejectsTraversal() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreAIConversionJobStore(rootURL: root)
        let record = try await store.createJob(identity: try identity())
        let artifact = try CoreAIConversionCheckpointArtifact(
            relativePath: "qwen/model.aimodel",
            sha256: String(repeating: "e", count: 64),
            byteCount: 9
        )
        let checkpoint = try CoreAIConversionCheckpoint(
            jobID: record.id,
            gate: "inspection",
            artifactRootPath: record.identity.request.outputDirectoryPath,
            fingerprint: record.fingerprint,
            artifacts: [artifact]
        )
        try await store.saveCheckpoint(jobID: record.id, checkpoint: checkpoint)

        #expect(try await store.checkpoint(jobID: record.id, gate: "inspection") == checkpoint)
        #expect(throws: CoreAIConversionJobStoreError.self) {
            _ = try CoreAIConversionCheckpointArtifact(
                relativePath: "../escape.aimodel",
                sha256: String(repeating: "f", count: 64),
                byteCount: 1
            )
        }
        let otherFingerprint = CoreAIConversionJobFingerprint(
            requestSHA256: String(repeating: "a", count: 64),
            environmentSHA256: String(repeating: "b", count: 64)
        )
        let foreignCheckpoint = try CoreAIConversionCheckpoint(
            jobID: record.id,
            gate: "foreign",
            artifactRootPath: record.identity.request.outputDirectoryPath,
            fingerprint: otherFingerprint,
            artifacts: []
        )
        do {
            try await store.saveCheckpoint(jobID: record.id, checkpoint: foreignCheckpoint)
            Issue.record("Expected the store to reject a checkpoint from another job fingerprint.")
        } catch CoreAIConversionJobStoreError.checkpointFingerprintMismatch {
            // Expected.
        }
        #expect(throws: CoreAIConversionJobStoreError.self) {
            _ = try CoreAIConversionCheckpoint(
                jobID: UUID(),
                gate: "../escape",
                artifactRootPath: "/tmp/artifacts",
                fingerprint: fingerprint(),
                artifacts: []
            )
        }
    }

    @Test
    func checkpointDecodingRevalidatesStoredPaths() throws {
        let json = """
            {
              "schemaVersion": 1,
              "jobID": "\(UUID().uuidString)",
              "gate": "asset-saved",
              "artifactRootPath": "/tmp/artifacts",
              "fingerprint": {
                "requestSHA256": "\(String(repeating: "1", count: 64))",
                "environmentSHA256": "\(String(repeating: "2", count: 64))"
              },
              "artifacts": [{
                "kind": "modelAsset",
                "digestScheme": "sha256TreeV1",
                "relativePath": "../escape.aimodel",
                "sha256": "\(String(repeating: "a", count: 64))",
                "byteCount": 1,
                "fileCount": 1
              }],
              "createdAt": 0
            }
            """

        #expect(throws: CoreAIConversionJobStoreError.self) {
            _ = try JSONDecoder().decode(
                CoreAIConversionCheckpoint.self,
                from: Data(json.utf8)
            )
        }
    }

    @Test
    func incompleteJobDirectoryIsReportedWithoutPoisoningDiscovery() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreAIConversionJobStore(rootURL: root)
        let valid = try await store.createJob(identity: try identity(modelName: "valid"))
        let incompleteID = UUID()
        try FileManager.default.createDirectory(
            at: root.appending(path: incompleteID.uuidString.lowercased()),
            withIntermediateDirectories: true
        )

        let scan = try await store.scanJobs()

        #expect(scan.jobs.map(\.id) == [valid.id])
        #expect(scan.issues.count == 1)
        #expect(scan.issues.first?.directoryName == incompleteID.uuidString.lowercased())
        #expect(try await store.reconcileInterruptedJobs().isEmpty)
    }

    @Test
    func tornFinalLogFramePreservesCompletePrefixAndIsQuarantinedBeforeAppend() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreAIConversionJobStore(rootURL: root)
        let record = try await store.createJob(identity: try identity())
        let first = try await store.appendLog(
            jobID: record.id,
            kind: .lifecycle,
            message: "started"
        )
        let directory = root.appending(path: record.id.uuidString.lowercased())
        let logURL = directory.appending(path: "events.jsonl")
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"partial\":".utf8))
        try handle.close()

        let recovered = try await store.readLogs(jobID: record.id)
        #expect(recovered.entries == [first])
        #expect(recovered.tornTailByteCount > 0)

        let second = try await store.appendLog(
            jobID: record.id,
            kind: .standardOutput,
            message: "continued"
        )
        #expect(try await store.logs(jobID: record.id) == [first, second])
        #expect(second.attempt == 1)
        #expect(second.sequence == 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains { $0.hasPrefix("events-torn-") && $0.hasSuffix(".bin") })
    }

    @Test
    func separateStoreActorsSerializeLogSequencesWithAFileLock() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = CoreAIConversionJobStore(rootURL: root)
        let secondStore = CoreAIConversionJobStore(rootURL: root)
        let record = try await firstStore.createJob(identity: try identity())

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                let store = index.isMultiple(of: 2) ? firstStore : secondStore
                group.addTask {
                    _ = try await store.appendLog(
                        jobID: record.id,
                        kind: .standardOutput,
                        message: "line \(index)"
                    )
                }
            }
            try await group.waitForAll()
        }

        let entries = try await firstStore.logs(jobID: record.id)
        #expect(entries.count == 40)
        #expect(entries.map(\.sequence) == Array(1...40).map(Int64.init))
        #expect(entries.allSatisfy { $0.attempt == 1 })
    }

    @Test
    func logAppendRejectsASymlinkWithoutTouchingItsTarget() async throws {
        let root = temporaryDirectory()
        let outside = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).log")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let store = CoreAIConversionJobStore(rootURL: root)
        let record = try await store.createJob(identity: try identity())
        let logURL = root
            .appending(path: record.id.uuidString.lowercased())
            .appending(path: "events.jsonl")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: logURL, withDestinationURL: outside)

        do {
            _ = try await store.appendLog(
                jobID: record.id,
                kind: .lifecycle,
                message: "must not escape"
            )
            Issue.record("Expected a symbolic-link log to be rejected.")
        } catch {
            #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
        }
    }

    @Test
    func checkpointLookupRejectsRenamedGateAndMismatchedRecordID() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreAIConversionJobStore(rootURL: root)
        let record = try await store.createJob(identity: try identity())
        let checkpoint = try CoreAIConversionCheckpoint(
            jobID: record.id,
            gate: "inspection",
            artifactRootPath: record.identity.request.outputDirectoryPath,
            fingerprint: record.fingerprint,
            artifacts: []
        )
        try await store.saveCheckpoint(jobID: record.id, checkpoint: checkpoint)
        let checkpointsURL = root
            .appending(path: record.id.uuidString.lowercased())
            .appending(path: "checkpoints")
        try FileManager.default.moveItem(
            at: checkpointsURL.appending(path: "inspection.json"),
            to: checkpointsURL.appending(path: "smoke.json")
        )
        do {
            _ = try await store.checkpoint(jobID: record.id, gate: "smoke")
            Issue.record("Expected a checkpoint renamed to another gate to be rejected.")
        } catch CoreAIConversionJobStoreError.checkpointFingerprintMismatch {
            // Expected.
        }

        let recordURL = root
            .appending(path: record.id.uuidString.lowercased())
            .appending(path: "job.json")
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any]
        )
        object["id"] = UUID().uuidString
        try JSONSerialization.data(withJSONObject: object).write(to: recordURL, options: .atomic)
        let scan = try await store.scanJobs()
        #expect(scan.jobs.isEmpty)
        #expect(scan.issues.count == 1)
    }

    @Test
    func checkpointWritesRejectLinkedParentsAndCrossJobTransplants() async throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let store = CoreAIConversionJobStore(rootURL: root)
        let sharedIdentity = try identity()
        let first = try await store.createJob(identity: sharedIdentity)
        let second = try await store.createJob(identity: sharedIdentity)
        let checkpoint = try CoreAIConversionCheckpoint(
            jobID: first.id,
            gate: "inspection",
            artifactRootPath: first.identity.request.outputDirectoryPath,
            fingerprint: first.fingerprint,
            artifacts: []
        )

        do {
            try await store.saveCheckpoint(jobID: second.id, checkpoint: checkpoint)
            Issue.record("Expected a same-fingerprint checkpoint from another job to be rejected.")
        } catch CoreAIConversionJobStoreError.checkpointFingerprintMismatch {
            // Expected.
        }

        let checkpointsURL = root
            .appending(path: first.id.uuidString.lowercased())
            .appending(path: "checkpoints")
        try FileManager.default.removeItem(at: checkpointsURL)
        try FileManager.default.createSymbolicLink(at: checkpointsURL, withDestinationURL: outside)
        do {
            try await store.saveCheckpoint(jobID: first.id, checkpoint: checkpoint)
            Issue.record("Expected a linked checkpoint directory to be rejected.")
        } catch {
            #expect(
                !FileManager.default.fileExists(
                    atPath: outside.appending(path: "inspection.json").path
                )
            )
        }
    }

    @Test
    func storeOwnedCheckpointVerifierRejectsMutationAndSymlinks() async throws {
        let root = temporaryDirectory()
        let artifacts = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: artifacts)
        }
        let modelURL = artifacts.appending(path: "model.aimodel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        let modelFileURL = modelURL.appending(path: "main.mlirb")
        try Data("model-v1".utf8).write(to: modelFileURL)
        let prototype = try CoreAIConversionCheckpointArtifact(
            kind: .modelAsset,
            digestScheme: .sha256TreeV1,
            relativePath: "model.aimodel",
            sha256: String(repeating: "0", count: 64),
            byteCount: 0,
            fileCount: 0
        )
        let verifier = CoreAIConversionCheckpointArtifactVerifier()
        let evidence = try verifier.evidence(for: prototype, under: artifacts)
        #expect(evidence.fileCount == 1)
        #expect(evidence.byteCount == 8)

        let store = CoreAIConversionJobStore(rootURL: root)
        let jobIdentity = try identity(outputDirectoryURL: artifacts)
        let record = try await store.createJob(identity: jobIdentity)
        let checkpoint = try CoreAIConversionCheckpoint(
            jobID: record.id,
            gate: "asset-saved",
            artifactRootPath: artifacts.standardizedFileURL.path,
            fingerprint: record.fingerprint,
            artifacts: [evidence]
        )
        try await store.saveCheckpoint(jobID: record.id, checkpoint: checkpoint)
        #expect(
            try await store.checkpointReuseDecision(
                jobID: record.id,
                gate: "asset-saved",
                currentIdentity: jobIdentity
            ) == .reusable
        )

        try Data("model-v2".utf8).write(to: modelFileURL, options: .atomic)
        #expect(
            try await store.checkpointReuseDecision(
                jobID: record.id,
                gate: "asset-saved",
                currentIdentity: jobIdentity
            ) == .artifactsChanged
        )

        try FileManager.default.removeItem(at: modelFileURL)
        try FileManager.default.createSymbolicLink(
            at: modelFileURL,
            withDestinationURL: URL(filePath: "/etc/hosts")
        )
        do {
            _ = try await store.checkpointReuseDecision(
                jobID: record.id,
                gate: "asset-saved",
                currentIdentity: jobIdentity
            )
            Issue.record("Expected a linked artifact member to be rejected.")
        } catch CoreAIConversionJobStoreError.artifactVerificationFailed {
            // Expected.
        }
    }

    @Test
    func checkpointReuseHoldsTheStoreLockThroughArtifactVerification() async throws {
        let root = temporaryDirectory()
        let artifacts = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: artifacts)
        }
        try FileManager.default.createDirectory(
            at: artifacts,
            withIntermediateDirectories: true
        )
        let artifact = try CoreAIConversionCheckpointArtifact(
            relativePath: "model.aimodel",
            sha256: String(repeating: "a", count: 64),
            byteCount: 8
        )
        let verifier = BlockingCheckpointArtifactVerifier(evidence: artifact)
        let store = CoreAIConversionJobStore(
            rootURL: root,
            checkpointArtifactVerifier: verifier
        )
        let jobIdentity = try identity(outputDirectoryURL: artifacts)
        let record = try await store.createJob(identity: jobIdentity)
        let checkpoint = try CoreAIConversionCheckpoint(
            jobID: record.id,
            gate: "asset-saved",
            artifactRootPath: artifacts.standardizedFileURL.path,
            fingerprint: record.fingerprint,
            artifacts: [artifact]
        )
        try await store.saveCheckpoint(jobID: record.id, checkpoint: checkpoint)

        let decision = Task {
            try await store.checkpointReuseDecision(
                jobID: record.id,
                gate: "asset-saved",
                currentIdentity: jobIdentity
            )
        }
        verifier.waitUntilVerificationBegins()

        let lockDescriptor = open(
            root.appending(path: ".store.lock").path,
            O_RDWR | O_CLOEXEC | O_NOFOLLOW
        )
        #expect(lockDescriptor >= 0)
        if lockDescriptor >= 0 {
            defer { close(lockDescriptor) }
            errno = 0
            #expect(flock(lockDescriptor, LOCK_EX | LOCK_NB) == -1)
            #expect(errno == EWOULDBLOCK || errno == EAGAIN)
        }

        verifier.allowVerificationToFinish()
        #expect(try await decision.value == .reusable)
    }

    private func identity(
        modelName: String = "qwen",
        arguments: [String] = ["export", "qwen"],
        outputName: String = "first",
        outputDirectoryURL: URL? = nil,
        xcodeBuild: String = "27A1",
        sourceDigestCharacter: Character = "3",
        environment: [String: String] = ["NO_COLOR": "1"]
    ) throws -> CoreAIConversionJobIdentity {
        let request = CoreAIConversionRequest(
            modelName: modelName,
            command: CoreAIConversionCommand(
                executableURL: URL(filePath: "/usr/bin/true"),
                arguments: arguments,
                workingDirectoryURL: URL(filePath: "/tmp/recipes")
            ),
            outputDirectoryURL: outputDirectoryURL ?? URL(filePath: "/tmp/\(outputName)")
        )
        return CoreAIConversionJobIdentity(
            request: try CoreAIConversionJobRequestIdentity(
                modelIdentifier: "apple/\(modelName)",
                request: request
            ),
            environment: try CoreAIConversionEnvironmentIdentity(
                xcodeBuildVersion: xcodeBuild,
                sdkBuildVersion: "27A1",
                recipeRepositoryRevision: String(repeating: "a", count: 40),
                sourceTreeSHA256: String(repeating: sourceDigestCharacter, count: 64),
                lockfileSHA256: String(repeating: "4", count: 64),
                executableSHA256: String(repeating: "5", count: 64),
                executableVersion: "uv 0.8.0",
                relevantEnvironment: environment
            )
        )
    }

    private func fingerprint() -> CoreAIConversionJobFingerprint {
        CoreAIConversionJobFingerprint(
            requestSHA256: String(repeating: "1", count: 64),
            environmentSHA256: String(repeating: "2", count: 64)
        )
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

private final class BlockingCheckpointArtifactVerifier:
    CoreAIConversionCheckpointArtifactVerifying,
    @unchecked Sendable
{
    private let didBegin = DispatchSemaphore(value: 0)
    private let mayFinish = DispatchSemaphore(value: 0)
    private let verifiedEvidence: CoreAIConversionCheckpointArtifact

    init(evidence: CoreAIConversionCheckpointArtifact) {
        verifiedEvidence = evidence
    }

    func evidence(
        for _: CoreAIConversionCheckpointArtifact,
        under _: URL
    ) throws -> CoreAIConversionCheckpointArtifact {
        didBegin.signal()
        mayFinish.wait()
        return verifiedEvidence
    }

    func waitUntilVerificationBegins() {
        didBegin.wait()
    }

    func allowVerificationToFinish() {
        mayFinish.signal()
    }
}
