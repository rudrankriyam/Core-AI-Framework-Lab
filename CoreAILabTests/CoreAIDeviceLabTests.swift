import Foundation
import Testing
@testable import CoreAILab

struct CoreAIDeviceLabTests {
    @Test
    func pythonHarnessFixtureDecodesAndValidatesInSwift() throws {
        let evidence = try JSONDecoder().decode(
            CoreAIDeviceTrialEvidence.self,
            from: CoreAITestFixtures.deviceLabDryRunEvidenceData()
        )

        try evidence.validate()
        #expect(evidence.runMode == .dryRun)
        #expect(evidence.device.modelIdentifier == "iPhone18,1")
        #expect(evidence.artifact.byteCount == 1_694)
        #expect(evidence.placement == .unavailable)

        try CoreAIDeviceHarnessFixtureContract.expectation.validate()
        let diagnostics = CoreAIDeviceAuthoringDiagnostics.evaluate(
            shapeRequest: CoreAIDeviceHarnessFixtureContract.shapeRequest,
            preferredComputeUnit: .automatic,
            expectation: CoreAIDeviceHarnessFixtureContract.expectation,
            evidence: evidence
        )
        #expect(!diagnostics.contains { $0.id == "compatibility.identity-mismatch" })
        #expect(!diagnostics.contains { $0.id == "compatibility.evidence-mismatch" })
        #expect(diagnostics.contains {
            $0.id == "compatibility.precision.not-evaluated"
        })
    }

    @MainActor
    @Test
    func deviceLabDefaultsMatchTheGeneratedHarnessContract() {
        let workspace = CoreAIDeviceLabWorkspaceModel()

        #expect(workspace.shapeRequest == CoreAIDeviceHarnessFixtureContract.shapeRequest)
        #expect(workspace.preferredComputeUnit == .automatic)
        #expect(
            workspace.evidenceExpectation
                == CoreAIDeviceHarnessFixtureContract.expectation
        )
    }

    @Test
    func oversizedEvidenceIsRejectedBeforeDecode() async throws {
        let directory = URL.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "oversized.json")
        let byteCount = Int(CoreAIDeviceEvidenceImporter.maximumByteCount) + 1
        try Data(repeating: 0x20, count: byteCount).write(to: url)

        await #expect(
            throws: CoreAIDeviceEvidenceImportError.fileTooLarge(
                found: UInt64(byteCount),
                maximum: CoreAIDeviceEvidenceImporter.maximumByteCount
            )
        ) {
            _ = try await CoreAIDeviceEvidenceImporter.load(from: url)
        }
    }

    @MainActor
    @Test
    func staleEvidenceImportCannotReplaceTheNewestSelection() async {
        let first = trial(
            id: "first",
            mode: .physical,
            specializationStatus: .succeeded,
            inferenceStatus: .succeeded,
            checks: checks(result: .notEvaluated),
            placement: .unavailable
        )
        let second = trial(
            id: "second",
            mode: .physical,
            specializationStatus: .succeeded,
            inferenceStatus: .succeeded,
            checks: checks(result: .notEvaluated),
            placement: .unavailable
        )
        let workspace = CoreAIDeviceLabWorkspaceModel { url in
            if url.lastPathComponent == "first.json" {
                try? await Task.sleep(for: .milliseconds(50))
                return first
            }
            return second
        }

        workspace.importEvidence(
            from: URL(filePath: "/tmp/first.json")
        )
        workspace.importEvidence(
            from: URL(filePath: "/tmp/second.json")
        )
        while workspace.isImportingEvidence {
            await Task.yield()
        }
        try? await Task.sleep(for: .milliseconds(75))

        #expect(workspace.importedEvidence?.id == "second")
    }

    @Test
    func connectedTargetProfileIsVersionedAndRoundTrips() throws {
        let profile = CoreAIConnectedDeviceTargetProfile(
            id: "iphone-ane-static",
            displayName: "iPhone static profile",
            device: device,
            minimumOSVersion: "27.0",
            preferredComputeUnit: .neuralEngine,
            expectsFrequentReshapes: false,
            contextTokenLimit: 2_048,
            staticInputShapes: ["tokens": [1, 2_048]]
        )

        try profile.validate()
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(
            CoreAIConnectedDeviceTargetProfile.self,
            from: data
        )

        #expect(decoded == profile)
        #expect(decoded.schemaVersion == CoreAIConnectedDeviceTargetProfile.currentSchemaVersion)
    }

    @Test
    func dryRunEvidenceRoundTripsWithoutExecutionClaims() throws {
        let evidence = trial(
            mode: .dryRun,
            specializationStatus: .notRun,
            inferenceStatus: .notRun,
            checks: checks(result: .notEvaluated),
            placement: .unavailable
        )

        try evidence.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(evidence)
        let decoded = try JSONDecoder().decode(CoreAIDeviceTrialEvidence.self, from: data)

        #expect(decoded == evidence)
        #expect(decoded.energy.availability == .unavailable)
        #expect(decoded.placement.availability == .unavailable)
    }

    @Test
    func dryRunCannotClaimACompletedSpecialization() {
        let evidence = trial(
            mode: .dryRun,
            specializationStatus: .succeeded,
            inferenceStatus: .notRun,
            checks: checks(result: .notEvaluated),
            placement: .unavailable
        )

        #expect(throws: CoreAIDeviceEvidenceError.self) {
            try evidence.validate()
        }
    }

    @Test
    func artifactIdentityAcceptsOnlyLowercaseASCIIHex() throws {
        try artifact.validate()
        let uppercase = CoreAIDeviceArtifactIdentity(
            identifier: "fixture.aimodel",
            sha256Digest: String(repeating: "A", count: 64),
            byteCount: 1
        )
        let unicodeDigits = CoreAIDeviceArtifactIdentity(
            identifier: "fixture.aimodel",
            sha256Digest: String(repeating: "١", count: 64),
            byteCount: 1
        )

        #expect(throws: CoreAIDeviceEvidenceError.self) {
            try uppercase.validate()
        }
        #expect(throws: CoreAIDeviceEvidenceError.self) {
            try unicodeDigits.validate()
        }
    }

    @Test
    func latencyDistributionIsDerivedFromAndCheckedAgainstSamples() throws {
        let latency = try CoreAIDeviceLatencyEvidence(
            observedSamples: [10, 20, 30, 40]
        )
        try latency.validate()

        #expect(latency.minimumMilliseconds == 10)
        #expect(latency.medianMilliseconds == 25)
        #expect(latency.meanMilliseconds == 25)
        #expect(latency.p95Milliseconds == 40)
        #expect(latency.maximumMilliseconds == 40)

        let tampered = CoreAIDeviceLatencyEvidence(
            availability: .observed,
            samplesMilliseconds: [10, 20, 30, 40],
            minimumMilliseconds: 10,
            medianMilliseconds: 25,
            meanMilliseconds: 24,
            p95Milliseconds: 40,
            maximumMilliseconds: 40
        )
        #expect(throws: CoreAIDeviceEvidenceError.self) {
            try tampered.validate()
        }
    }

    @Test
    func storagePlannerSeparatesAppAndOnDemandSlices() throws {
        let plan = try CoreAIDeviceStoragePlanner.plan(
            request: CoreAIDeviceStoragePlanRequest(
                slices: [
                    CoreAIAssetDeliverySlice(
                        id: "runtime",
                        displayName: "Runtime",
                        downloadByteCount: 20,
                        installedByteCount: 25,
                        deliveryMode: .appDownload
                    ),
                    CoreAIAssetDeliverySlice(
                        id: "weights",
                        displayName: "Weights",
                        downloadByteCount: 80,
                        installedByteCount: 95,
                        deliveryMode: .onDemand
                    ),
                ],
                appDownloadBudgetBytes: 50,
                availableDeviceBytes: 150,
                temporaryWorkingBytes: 25
            )
        )

        #expect(plan.appDownloadBytes == 20)
        #expect(plan.onDemandDownloadBytes == 80)
        #expect(plan.installedAssetBytes == 120)
        #expect(plan.peakRequiredDeviceBytes == 145)
        #expect(plan.fitsBudgets)
    }

    @Test
    func storagePlannerRejectsOverflowInsteadOfWrapping() {
        let request = CoreAIDeviceStoragePlanRequest(
            slices: [
                CoreAIAssetDeliverySlice(
                    id: "large",
                    displayName: "Large",
                    downloadByteCount: .max,
                    installedByteCount: .max,
                    deliveryMode: .appDownload
                ),
                CoreAIAssetDeliverySlice(
                    id: "more",
                    displayName: "More",
                    downloadByteCount: 1,
                    installedByteCount: 1,
                    deliveryMode: .onDemand
                ),
            ],
            appDownloadBudgetBytes: .max,
            availableDeviceBytes: .max,
            temporaryWorkingBytes: 0
        )

        #expect(throws: CoreAIDeviceEvidenceError.self) {
            _ = try CoreAIDeviceStoragePlanner.plan(request: request)
        }
    }

    @Test
    func staticShapeDiagnosticsExposeContextDynamicShapeAndDimensionLimit() {
        let request = CoreAIDeviceShapeAuthoringRequest(
            requestedContextTokens: 8_192,
            maximumContextTokens: 4_096,
            expectsFrequentReshapes: false,
            shapes: [
                CoreAIDeviceShapeDefinition(
                    id: "tokens",
                    dimensions: [1, nil]
                ),
                CoreAIDeviceShapeDefinition(
                    id: "overflow",
                    dimensions: [.max, 2]
                ),
            ]
        )

        let diagnostics = CoreAIDeviceAuthoringDiagnostics.evaluate(
            shapeRequest: request,
            preferredComputeUnit: .automatic,
            expectation: expectation,
            evidence: nil
        )

        #expect(diagnostics.contains { $0.id == "context.exceeds-maximum" })
        #expect(diagnostics.contains { $0.id == "shape.tokens.dynamic" })
        #expect(diagnostics.contains {
            $0.id == "shape.overflow.dimension.0.limit"
        })
    }

    @Test
    func neuralEnginePreferenceAndPassingTrialDoNotProvePlacement() throws {
        let evidence = trial(
            mode: .physical,
            specializationStatus: .succeeded,
            inferenceStatus: .succeeded,
            checks: checks(result: .passed),
            placement: .unavailable
        )
        try evidence.validate()

        let diagnostics = CoreAIDeviceAuthoringDiagnostics.evaluate(
            shapeRequest: validShapeRequest,
            preferredComputeUnit: .neuralEngine,
            expectation: expectation,
            evidence: evidence
        )

        #expect(!evidence.placement.reportsNeuralEnginePlacement)
        #expect(diagnostics.contains { diagnostic in
            diagnostic.id == "placement.unavailable"
                && diagnostic.detail.contains("does not prove")
        })
    }

    @Test
    func evidenceDoesNotApplyAfterTheAuthoringConfigurationChanges() throws {
        let evidence = trial(
            mode: .physical,
            specializationStatus: .succeeded,
            inferenceStatus: .succeeded,
            checks: checks(result: .passed),
            placement: CoreAIDevicePlacementEvidence(
                availability: .observed,
                actualComputeUnits: ["Neural Engine"],
                source: "Instruments trace"
            )
        )
        try evidence.validate()
        let changedRequest = CoreAIDeviceShapeAuthoringRequest(
            requestedContextTokens: 4_096,
            maximumContextTokens: 4_096,
            expectsFrequentReshapes: false,
            shapes: [
                CoreAIDeviceShapeDefinition(id: "tokens", dimensions: [1, 4_096])
            ]
        )

        let diagnostics = CoreAIDeviceAuthoringDiagnostics.evaluate(
            shapeRequest: changedRequest,
            preferredComputeUnit: .neuralEngine,
            expectation: expectation,
            evidence: evidence
        )

        #expect(diagnostics.contains { $0.id == "compatibility.evidence-mismatch" })
        #expect(diagnostics.contains { $0.id == "placement.unavailable" })
        #expect(!diagnostics.contains { $0.id == "placement.observed-neural-engine" })
    }

    @Test
    func crossArtifactOrConfigurationEvidenceCannotSurfaceResults() throws {
        let evidence = trial(
            mode: .physical,
            specializationStatus: .succeeded,
            inferenceStatus: .succeeded,
            checks: checks(result: .passed),
            placement: CoreAIDevicePlacementEvidence(
                availability: .observed,
                actualComputeUnits: ["Neural Engine"],
                source: "Instruments trace"
            )
        )
        try evidence.validate()
        let otherArtifact = CoreAIDeviceEvidenceExpectation(
            artifact: CoreAIDeviceArtifactIdentity(
                identifier: artifact.identifier,
                sha256Digest: String(repeating: "c", count: 64),
                byteCount: artifact.byteCount
            ),
            configurationIdentifier: configuration.identifier,
            configurationSHA256Digest: configuration.sha256Digest
        )
        let otherConfiguration = CoreAIDeviceEvidenceExpectation(
            artifact: artifact,
            configurationIdentifier: configuration.identifier,
            configurationSHA256Digest: String(repeating: "d", count: 64)
        )
        let otherConfigurationIdentifier = CoreAIDeviceEvidenceExpectation(
            artifact: artifact,
            configurationIdentifier: "another-config",
            configurationSHA256Digest: configuration.sha256Digest
        )

        for mismatchedExpectation in [
            otherArtifact,
            otherConfiguration,
            otherConfigurationIdentifier,
        ] {
            let diagnostics = CoreAIDeviceAuthoringDiagnostics.evaluate(
                shapeRequest: validShapeRequest,
                preferredComputeUnit: .neuralEngine,
                expectation: mismatchedExpectation,
                evidence: evidence
            )
            #expect(diagnostics.contains {
                $0.id == "compatibility.identity-mismatch"
            })
            #expect(!diagnostics.contains {
                $0.id == "compatibility.precision.passed"
                    || $0.id == "placement.observed-neural-engine"
            })
        }
    }

    @Test
    func shapeContractsEnforceAllSafetyCeilings() {
        let tooManyShapes = Dictionary(
            uniqueKeysWithValues: (0...CoreAIDeviceShapeLimits.maximumShapeCount)
                .map { ("shape-\($0)", [1]) }
        )
        let tooManyElements = [
            "a": [10_000, 20_000],
            "b": [10_000, 20_000],
            "c": [10_000, 20_000],
        ]
        let invalidConfigurations: [(Int?, [String: [Int]])] = [
            (CoreAIDeviceShapeLimits.maximumContextTokens + 1, [:]),
            (nil, tooManyShapes),
            (
                nil,
                [
                    "rank": Array(
                        repeating: 1,
                        count: CoreAIDeviceShapeLimits.maximumRank + 1
                    )
                ]
            ),
            (nil, ["dimension": [CoreAIDeviceShapeLimits.maximumDimension + 1]]),
            (nil, ["elements": [16_384, 16_385]]),
            (nil, tooManyElements),
        ]

        for (context, shapes) in invalidConfigurations {
            #expect(throws: CoreAIDeviceEvidenceError.self) {
                try CoreAIDeviceShapeLimits.validate(
                    contextTokens: context,
                    staticInputShapes: shapes,
                    path: "test"
                )
            }
        }

        let diagnostics = CoreAIDeviceAuthoringDiagnostics.evaluate(
            shapeRequest: CoreAIDeviceShapeAuthoringRequest(
                requestedContextTokens:
                    CoreAIDeviceShapeLimits.maximumContextTokens + 1,
                maximumContextTokens:
                    CoreAIDeviceShapeLimits.maximumContextTokens + 1,
                expectsFrequentReshapes: false,
                shapes: tooManyElements.keys.sorted().map { name in
                    CoreAIDeviceShapeDefinition(
                        id: name,
                        dimensions: tooManyElements[name, default: []]
                            .map(Optional.some)
                    )
                }
            ),
            preferredComputeUnit: .automatic,
            expectation: expectation,
            evidence: nil
        )
        #expect(diagnostics.contains { $0.id == "context.safety-ceiling" })
        #expect(diagnostics.contains { $0.id == "shape.total-element-limit" })
    }

    @Test
    func onlyExplicitMeasuredNeuralEnginePlacementCountsAsProof() throws {
        let unrelated = CoreAIDevicePlacementEvidence(
            availability: .observed,
            actualComputeUnits: ["GPU plane"],
            source: "Instruments trace"
        )
        let neuralEngine = CoreAIDevicePlacementEvidence(
            availability: .observed,
            actualComputeUnits: ["Neural Engine"],
            source: "Instruments trace"
        )

        try unrelated.validate()
        try neuralEngine.validate()
        #expect(!unrelated.reportsNeuralEnginePlacement)
        #expect(neuralEngine.reportsNeuralEnginePlacement)
    }

    private var device: CoreAIDeviceFacts {
        CoreAIDeviceFacts(
            modelName: "Test iPhone",
            modelIdentifier: "iPhone18,1",
            operatingSystemVersion: "27.0",
            destinationIdentifier: "00008140-TEST"
        )
    }

    private var artifact: CoreAIDeviceArtifactIdentity {
        CoreAIDeviceArtifactIdentity(
            identifier: "fixture.aimodel",
            sha256Digest: String(repeating: "a", count: 64),
            byteCount: 1_024
        )
    }

    private var configuration: CoreAIDeviceConfigurationIdentity {
        CoreAIDeviceConfigurationIdentity(
            identifier: "iphone-static",
            sha256Digest: String(repeating: "b", count: 64),
            preferredComputeUnit: .neuralEngine,
            expectsFrequentReshapes: false,
            contextTokens: 2_048,
            staticInputShapes: ["tokens": [1, 2_048]]
        )
    }

    private var validShapeRequest: CoreAIDeviceShapeAuthoringRequest {
        CoreAIDeviceShapeAuthoringRequest(
            requestedContextTokens: 2_048,
            maximumContextTokens: 4_096,
            expectsFrequentReshapes: false,
            shapes: [
                CoreAIDeviceShapeDefinition(id: "tokens", dimensions: [1, 2_048])
            ]
        )
    }

    private var expectation: CoreAIDeviceEvidenceExpectation {
        CoreAIDeviceEvidenceExpectation(
            artifact: artifact,
            configurationIdentifier: configuration.identifier,
            configurationSHA256Digest: configuration.sha256Digest
        )
    }

    private func checks(
        result: CoreAINECompatibilityResult
    ) -> [CoreAINECompatibilityCheck] {
        CoreAINECompatibilityCategory.allCases.map { category in
            CoreAINECompatibilityCheck(
                category: category,
                result: result,
                detail: result == .notEvaluated
                    ? "This dimension was not evaluated."
                    : "The recorded compatibility check completed.",
                source: result == .notEvaluated ? nil : "coreai-build report"
            )
        }
    }

    private func trial(
        id: String = "trial-1",
        mode: CoreAIDeviceRunMode,
        specializationStatus: CoreAIDeviceTrialStatus,
        inferenceStatus: CoreAIDeviceTrialStatus,
        checks: [CoreAINECompatibilityCheck],
        placement: CoreAIDevicePlacementEvidence
    ) -> CoreAIDeviceTrialEvidence {
        CoreAIDeviceTrialEvidence(
            id: id,
            runMode: mode,
            capturedAt: "2027-01-02T03:04:05Z",
            device: device,
            artifact: artifact,
            configuration: configuration,
            specialization: CoreAIDeviceTrialOutcome(
                status: specializationStatus,
                durationMilliseconds: nil,
                detail: "Specialization trial state."
            ),
            inference: CoreAIDeviceTrialOutcome(
                status: inferenceStatus,
                durationMilliseconds: nil,
                detail: "Inference trial state."
            ),
            latency: .unavailable,
            memory: .unavailable,
            thermal: .unavailable,
            energy: .unavailable,
            placement: placement,
            neuralEngineCompatibilityChecks: checks
        )
    }
}
