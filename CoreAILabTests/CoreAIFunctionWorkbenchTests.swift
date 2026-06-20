import CoreAI
import Foundation
import Testing
@testable import CoreAILab

struct CoreAIFunctionWorkbenchTests {
    @Test
    func seededRandomGenerationIsRepeatable() {
        var first = CoreAISeededRandomNumberGenerator(seed: 42)
        var second = CoreAISeededRandomNumberGenerator(seed: 42)
        var different = CoreAISeededRandomNumberGenerator(seed: 43)

        let firstValues = (0..<8).map { _ in first.next() }
        let secondValues = (0..<8).map { _ in second.next() }
        let differentValues = (0..<8).map { _ in different.next() }

        #expect(firstValues == secondValues)
        #expect(firstValues != differentValues)
    }

    @MainActor
    @Test
    func scalarTensorDraftAcceptsAnEmptyShape() throws {
        let contract = CoreAIFunctionValueContract(
            name: "temperature",
            kind: .tensor(
                CoreAITensorContract(
                    scalarType: .float32,
                    shape: [],
                    hasDynamicShape: false,
                    minimumByteCount: MemoryLayout<Float>.size
                )
            )
        )

        let draft = try #require(CoreAIFunctionInputDraft(contract: contract))
        #expect(try draft.plan().shape == [])
    }

    @MainActor
    @Test
    func imageInputsRemainInspectableWithoutCreatingTensorDrafts() {
        let contract = CoreAIFunctionValueContract(
            name: "image",
            kind: .image(
                CoreAIImageContract(
                    width: 224,
                    height: 224,
                    pixelFormatType: 0
                )
            )
        )

        #expect(CoreAIFunctionInputDraft(contract: contract) == nil)
    }

    @MainActor
    @Test
    func newestSpecializationWinsWhenContractLoadsOverlap() async throws {
        let firstContract = contract(named: "first")
        let secondContract = contract(named: "second")
        let runtime = CoreAISpecializationServiceStub(
            contractResponses: [[firstContract], [secondContract]],
            delayedContractLookup: 1
        )
        let workspace = CoreAIFunctionWorkbenchWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            runtimeService: runtime
        )
        await workspace.loadAsset(from: URL(filePath: "/tmp/valid.aimodel"))
        await workspace.assetWorkspace.specialize()
        let firstResult = try #require(workspace.assetWorkspace.specializationResult)

        let staleLoad = Task {
            await workspace.specializationChanged(firstResult)
        }
        while workspace.phase != .preparingContracts {
            await Task.yield()
        }

        workspace.assetWorkspace.selectedProfile = .cpuOnly
        await workspace.specializationChanged(nil)
        await workspace.assetWorkspace.specialize()
        let secondResult = try #require(workspace.assetWorkspace.specializationResult)
        await workspace.specializationChanged(secondResult)
        await staleLoad.value

        #expect(workspace.contracts == [secondContract])
        #expect(workspace.selectedFunctionName == "second")
        #expect(workspace.phase == .ready)
    }

    @MainActor
    @Test
    func failedReplacementPreservesTheRunnableWorkbench() async throws {
        let validURL = URL(filePath: "/tmp/valid.aimodel")
        let validContract = contract(named: "main")
        let runtime = CoreAISpecializationServiceStub(
            contractResponses: [[validContract]]
        )
        let workspace = CoreAIFunctionWorkbenchWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            runtimeService: runtime
        )
        await workspace.loadAsset(from: validURL)
        await workspace.assetWorkspace.specialize()
        let result = try #require(workspace.assetWorkspace.specializationResult)
        await workspace.specializationChanged(result)
        #expect(workspace.canRun)

        await workspace.loadAsset(from: URL(filePath: "/tmp/invalid.aimodel"))

        #expect(workspace.assetWorkspace.report?.url == validURL)
        #expect(workspace.contracts == [validContract])
        #expect(workspace.selectedFunctionName == "main")
        #expect(workspace.canRun)
        #expect(workspace.assetWorkspace.isShowingError)
    }

    @MainActor
    @Test
    func failedContractLoadExposesRetryAndCanRecover() async throws {
        let recoveredContract = contract(named: "recovered")
        let runtime = CoreAISpecializationServiceStub(
            contractResponses: [[recoveredContract]],
            failingContractLookups: [1]
        )
        let workspace = CoreAIFunctionWorkbenchWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            runtimeService: runtime
        )
        await workspace.loadAsset(from: URL(filePath: "/tmp/valid.aimodel"))
        await workspace.assetWorkspace.specialize()
        let result = try #require(workspace.assetWorkspace.specializationResult)

        await workspace.specializationChanged(result)
        #expect(workspace.contracts.isEmpty)
        #expect(workspace.contractLoadFailureMessage != nil)

        await workspace.reloadContracts()
        #expect(workspace.contracts == [recoveredContract])
        #expect(workspace.contractLoadFailureMessage == nil)
        #expect(workspace.selectedFunctionName == "recovered")
    }

    @Test
    func allNonFiniteOutputKeepsItsDiagnosticCount() {
        let array = NDArray(
            scalars: [Float.nan, Float.infinity, -Float.infinity],
            shape: [3]
        )
        let summary = CoreAIOutputInspector.summarize(name: "values", array: array)

        #expect(summary.sampledElementCount == 3)
        #expect(summary.nonFiniteCount == 3)
        #expect(summary.minimum == nil)
        #expect(summary.maximum == nil)
        #expect(summary.mean == nil)
    }

    @Test
    func realCoreAIFixtureRunsFloatAndIntegerFunctions() async throws {
        let service = CoreAISpecializationService()
        let fixtureURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/CoreAILabTensorFixture.aimodel")
        try? await service.removeCachedEntries(at: fixtureURL)

        do {
            let specialization = try await service.specialize(
                at: fixtureURL,
                profile: .automatic,
                cachePolicy: .standard
            )
            #expect(
                specialization.functionNames == [
                    "increment_tokens",
                    "scale_and_bias",
                ]
            )
            #expect(
                try await service.isCached(
                    at: fixtureURL,
                    profile: .automatic
                )
            )

            let contracts = try await service.functionContracts()
            #expect(contracts.map(\.name) == specialization.functionNames)
            #expect(contracts.allSatisfy { $0.isRunnable })

            let floatResult = try await service.runFunction(
                named: "scale_and_bias",
                inputs: [
                    CoreAIFunctionInputPlan(
                        name: "values",
                        shape: [1, 4],
                        generator: .zeros,
                        seed: 42
                    )
                ]
            )
            let floatOutput = try #require(floatResult.outputs.first)
            #expect(floatOutput.name == "scaled_values")
            #expect(floatOutput.shape == [1, 4])
            #expect(floatOutput.minimum == 1)
            #expect(floatOutput.maximum == 1)
            #expect(floatOutput.mean == 1)
            #expect(floatOutput.preview == ["1", "1", "1", "1"])

            let integerResult = try await service.runFunction(
                named: "increment_tokens",
                inputs: [
                    CoreAIFunctionInputPlan(
                        name: "tokens",
                        shape: [1, 4],
                        generator: .zeros,
                        seed: 42
                    )
                ]
            )
            let integerOutput = try #require(integerResult.outputs.first)
            #expect(integerOutput.name == "incremented_tokens")
            #expect(integerOutput.shape == [1, 4])
            #expect(integerOutput.preview == ["1", "1", "1", "1"])

            try await service.removeCachedEntries(at: fixtureURL)
            #expect(
                try await service.isCached(
                    at: fixtureURL,
                    profile: .automatic
                ) == false
            )
        } catch {
            try? await service.removeCachedEntries(at: fixtureURL)
            throw error
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
}
