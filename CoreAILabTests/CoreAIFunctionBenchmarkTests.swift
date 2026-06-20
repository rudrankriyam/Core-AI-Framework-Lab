import Foundation
import Testing
@testable import CoreAILab

struct CoreAIFunctionBenchmarkTests {
    @Test
    func defaultProtocolUsesOneWarmupAndFiveMeasuredRuns() throws {
        let configuration = CoreAIFunctionBenchmarkConfiguration()

        try configuration.validate()
        #expect(configuration.warmupRuns == 1)
        #expect(configuration.measuredRuns == 5)
    }

    @Test
    func protocolRejectsCountsOutsideItsBoundedRanges() {
        let invalidWarmup = CoreAIFunctionBenchmarkConfiguration(
            warmupRuns: 11,
            measuredRuns: 5
        )
        let invalidMeasuredRuns = CoreAIFunctionBenchmarkConfiguration(
            warmupRuns: 1,
            measuredRuns: 0
        )

        #expect(throws: CoreAIFunctionBenchmarkError.self) {
            try invalidWarmup.validate()
        }
        #expect(throws: CoreAIFunctionBenchmarkError.self) {
            try invalidMeasuredRuns.validate()
        }
    }

    @Test
    func statisticsKeepEveryTrialAndHideP95ForSmallSamples() throws {
        let trials = [10, 20, 30, 40].enumerated().map { index, milliseconds in
            CoreAIBenchmarkTrial(
                index: index + 1,
                duration: .milliseconds(milliseconds)
            )
        }

        let statistics = try CoreAIBenchmarkStatistics(trials: trials)

        #expect(milliseconds(statistics.minimum) == 10)
        #expect(milliseconds(statistics.median) == 25)
        #expect(milliseconds(statistics.mean) == 25)
        #expect(milliseconds(statistics.maximum) == 40)
        #expect(abs(milliseconds(statistics.standardDeviation) - 11.18034) < 0.0001)
        #expect(abs(statistics.runsPerSecond - 40) < 0.0001)
        #expect(statistics.p95 == nil)
    }

    @Test
    func throughputUsesTheWholeSequentialBatchRatherThanTheMedian() throws {
        let trials = [1, 1, 100].enumerated().map { index, milliseconds in
            CoreAIBenchmarkTrial(
                index: index + 1,
                duration: .milliseconds(milliseconds)
            )
        }

        let statistics = try CoreAIBenchmarkStatistics(trials: trials)

        #expect(abs(statistics.runsPerSecond - (3 / 0.102)) < 0.0001)
    }

    @Test
    func statisticsExposeNearestRankP95AtTwentyTrials() throws {
        let trials = (1...20).map {
            CoreAIBenchmarkTrial(index: $0, duration: .milliseconds($0))
        }

        let statistics = try CoreAIBenchmarkStatistics(trials: trials)

        #expect(milliseconds(try #require(statistics.p95)) == 19)
    }

    @MainActor
    @Test
    func reshapeExpectationIsPartOfCacheAndRemovalIdentity() async {
        let fixed = CoreAISpecializationConfiguration(
            profile: .automatic,
            expectFrequentReshapes: false
        )
        let dynamic = CoreAISpecializationConfiguration(
            profile: .automatic,
            expectFrequentReshapes: true
        )
        let runtime = CoreAISpecializationServiceStub(
            cachedConfigurations: [fixed]
        )
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            specializationService: runtime
        )
        let assetURL = URL(filePath: "/tmp/fixture.aimodel")

        await workspace.inspect(url: assetURL)
        #expect(workspace.cacheStatus == .cached)

        workspace.expectFrequentReshapes = true
        #expect(workspace.selectedConfiguration == dynamic)
        #expect(workspace.cacheStatus == .unchecked)
        await workspace.refreshCacheStatus()
        #expect(workspace.cacheStatus == .notCached)

        await workspace.specialize()
        #expect(workspace.specializationResult?.configuration == dynamic)
        workspace.prepareCacheRemoval(.selectedProfile)
        await workspace.removePreparedCacheEntry()

        let removal = await runtime.removalSnapshot()
        #expect(removal.configurations == [dynamic])
        #expect(removal.profileURLs == [assetURL])
    }

    @MainActor
    @Test
    func sessionHistoryComparesSpecializationConfigurations() async throws {
        let runtime = CoreAISpecializationServiceStub(
            contractResponses: [[contract(named: "main")], [contract(named: "main")]]
        )
        let workspace = CoreAIFunctionWorkbenchWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            runtimeService: runtime
        )
        await prepare(workspace)

        workspace.startBenchmark()
        await waitForBenchmark(workspace)
        #expect(workspace.benchmarkHistory.count == 1)
        #expect(workspace.benchmarkHistory[0].result.warmupDurations.count == 1)
        #expect(workspace.benchmarkHistory[0].result.trials.count == 5)
        #expect(
            workspace.benchmarkHistory[0].specializationConfiguration.profile
                == .automatic
        )

        workspace.assetWorkspace.selectedProfile = .cpuOnly
        await workspace.specializationChanged(nil)
        await workspace.assetWorkspace.specialize()
        let secondSpecialization = try #require(
            workspace.assetWorkspace.specializationResult
        )
        await workspace.specializationChanged(secondSpecialization)
        workspace.startBenchmark()
        await waitForBenchmark(workspace)

        #expect(workspace.benchmarkHistory.count == 2)
        #expect(
            workspace.benchmarkHistory.map {
                $0.specializationConfiguration.profile
            } == [.cpuOnly, .automatic]
        )
    }

    @MainActor
    @Test
    func stopWaitsForTheActiveRunAndRetainsCompletedTrials() async throws {
        let runtime = CoreAISpecializationServiceStub(
            contractResponses: [[contract(named: "main")]],
            benchmarkRunDelay: .milliseconds(50)
        )
        let workspace = CoreAIFunctionWorkbenchWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            runtimeService: runtime
        )
        await prepare(workspace)

        workspace.startBenchmark()
        while await runtime.completedBenchmarkRunCount() < 2 {
            await Task.yield()
        }
        workspace.stopBenchmarkAfterCurrentInference()
        await waitForBenchmark(workspace)

        let completedRuns = await runtime.completedBenchmarkRunCount()
        #expect(completedRuns >= 2)
        #expect(completedRuns < 6)
        #expect(workspace.benchmarkHistory.count == 1)
        #expect(workspace.benchmarkHistory[0].result.stoppedEarly)
        #expect(workspace.benchmarkHistory[0].result.trials.isEmpty == false)
        #expect(workspace.benchmarkHistory[0].result.trials.count < 5)
        #expect(
            workspace.benchmarkStatusMessage?.localizedCaseInsensitiveContains("stopped")
                == true
        )
        #expect(workspace.phase == .ready)
    }

    @MainActor
    @Test
    func leavingTheWorkbenchStopsAfterTheActiveInference() async throws {
        let runtime = CoreAISpecializationServiceStub(
            contractResponses: [[contract(named: "main")]],
            benchmarkRunDelay: .milliseconds(50)
        )
        let workspace = CoreAIFunctionWorkbenchWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            runtimeService: runtime
        )
        await prepare(workspace)
        workspace.startBenchmark()
        while await runtime.completedBenchmarkRunCount() < 2 {
            await Task.yield()
        }

        workspace.cancelBenchmark()
        await waitForBenchmark(workspace)

        #expect(await runtime.completedBenchmarkRunCount() < 6)
        #expect(workspace.phase == .ready)
    }

    @Test
    func realFixtureRunsWarmupAndMeasuredInference() async throws {
        let service = CoreAISpecializationService()
        let fixtureURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/CoreAILabTensorFixture.aimodel")
        try? await service.removeCachedEntries(at: fixtureURL)

        do {
            _ = try await service.specialize(
                at: fixtureURL,
                configuration: CoreAISpecializationConfiguration(profile: .automatic),
                cachePolicy: .standard
            )
            let result = try await service.benchmarkFunction(
                named: "scale_and_bias",
                inputs: [
                    CoreAIFunctionInputPlan(
                        name: "values",
                        shape: [1, 4],
                        generator: .zeros,
                        seed: 42
                    )
                ],
                configuration: CoreAIFunctionBenchmarkConfiguration(
                    warmupRuns: 1,
                    measuredRuns: 3
                )
            )

            #expect(result.warmupDurations.count == 1)
            #expect(result.trials.count == 3)
            #expect(!result.stoppedEarly)
            #expect(result.trials.allSatisfy { $0.duration > .zero })
            #expect(result.statistics.p95 == nil)
            #expect(result.environment.deviceArchitectureName.isEmpty == false)
            #expect(result.environment.availableComputeUnits.isEmpty == false)
            #expect(result.outputs.first?.mean == 1)
            try await service.removeCachedEntries(at: fixtureURL)
        } catch {
            try? await service.removeCachedEntries(at: fixtureURL)
            throw error
        }
    }

    @MainActor
    private func prepare(
        _ workspace: CoreAIFunctionWorkbenchWorkspaceModel
    ) async {
        await workspace.loadAsset(from: URL(filePath: "/tmp/valid.aimodel"))
        await workspace.assetWorkspace.specialize()
        if let specialization = workspace.assetWorkspace.specializationResult {
            await workspace.specializationChanged(specialization)
        }
    }

    @MainActor
    private func waitForBenchmark(
        _ workspace: CoreAIFunctionWorkbenchWorkspaceModel
    ) async {
        while workspace.phase == .benchmarking {
            await Task.yield()
        }
    }

    private func contract(named name: String) -> CoreAIFunctionContract {
        CoreAIFunctionContract(
            name: name,
            inputs: [],
            states: [],
            outputs: [],
            unsupportedReason: nil
        )
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return (
            Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
        ) * 1_000
    }
}
