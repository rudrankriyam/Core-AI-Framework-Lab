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
}
