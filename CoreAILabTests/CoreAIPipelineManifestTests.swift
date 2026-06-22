import Foundation
import Testing
@testable import CoreAILab

struct CoreAIPipelineManifestTests {
    @Test
    func validManifestRoundTripsDeterministically() throws {
        let manifest = validManifest()

        let first = try CoreAIPipelineCodec.encode(manifest)
        let decoded = try CoreAIPipelineCodec.decode(first)
        let second = try CoreAIPipelineCodec.encode(decoded)

        #expect(decoded == manifest)
        #expect(first == second)
    }

    @Test
    func unsupportedSchemaAndUnsafeIdentifiersFail() {
        let manifest = CoreAIPipelineManifest(
            schemaVersion: 99,
            id: "../unsafe",
            displayName: "Unsafe",
            hostOperatorRegistryVersion: 1,
            nodes: [],
            edges: []
        )

        let codes = Set(CoreAIPipelineValidator.issues(in: manifest).map(\.code))

        #expect(codes.contains(.unsupportedSchemaVersion))
        #expect(codes.contains(.invalidIdentifier))
    }

    @Test
    func cyclesAreRejected() {
        let tensor = tensorContract(shape: [.fixed(1)])
        let first = CoreAIPipelineNode(
            id: "first",
            kind: .hostOperator,
            title: "First",
            inputs: [CoreAIPipelinePort(name: "input", value: tensor)],
            outputs: [CoreAIPipelinePort(name: "output", value: tensor)]
        )
        let second = CoreAIPipelineNode(
            id: "second",
            kind: .hostOperator,
            title: "Second",
            inputs: [CoreAIPipelinePort(name: "input", value: tensor)],
            outputs: [CoreAIPipelinePort(name: "output", value: tensor)]
        )
        let manifest = CoreAIPipelineManifest(
            id: "cycle",
            displayName: "Cycle",
            hostOperatorRegistryVersion: 1,
            nodes: [first, second],
            edges: [
                edge(from: "first", to: "second"),
                edge(from: "second", to: "first")
            ]
        )

        #expect(CoreAIPipelineValidator.issues(in: manifest).contains {
            $0.code == .cycle
        })
    }

    @Test
    func incompatibleValuesAndMultiplyConnectedInputsFail() {
        let tensor = tensorContract(shape: [.fixed(4)])
        let image = CoreAIPipelineValueContract(kind: .image)
        let first = sourceNode(id: "first", contract: tensor)
        let second = sourceNode(id: "second", contract: tensor)
        let destination = CoreAIPipelineNode(
            id: "destination",
            kind: .output,
            title: "Destination",
            inputs: [CoreAIPipelinePort(name: "input", value: image)]
        )
        let manifest = CoreAIPipelineManifest(
            id: "incompatible",
            displayName: "Incompatible",
            hostOperatorRegistryVersion: 1,
            nodes: [first, second, destination],
            edges: [
                edge(from: "first", to: "destination"),
                edge(from: "second", to: "destination")
            ]
        )

        let codes = Set(CoreAIPipelineValidator.issues(in: manifest).map(\.code))
        #expect(codes.contains(.incompatibleValue))
        #expect(codes.contains(.multiplyConnectedInput))
    }

    @Test
    func stateRequiresOneExistingOwner() {
        let owner = CoreAIPipelineNode(
            id: "owner",
            kind: .assetFunction,
            title: "Owner"
        )
        let firstState = CoreAIPipelineNode(
            id: "firstState",
            kind: .state,
            title: "First state",
            stateKey: "cache",
            ownerNodeID: owner.id
        )
        let secondOwner = CoreAIPipelineNode(
            id: "secondOwner",
            kind: .assetFunction,
            title: "Second owner"
        )
        let secondState = CoreAIPipelineNode(
            id: "secondState",
            kind: .state,
            title: "Second state",
            stateKey: "cache",
            ownerNodeID: secondOwner.id
        )
        let manifest = CoreAIPipelineManifest(
            id: "stateOwnership",
            displayName: "State ownership",
            hostOperatorRegistryVersion: 1,
            nodes: [owner, firstState, secondOwner, secondState],
            edges: []
        )

        #expect(CoreAIPipelineValidator.issues(in: manifest).contains {
            $0.code == .duplicateStateOwnership
        })
    }

    @Test
    func randomnessRequiresExactlyOneSeedSource() {
        let unseeded = CoreAIPipelineNode(
            id: "random",
            kind: .seededRandom,
            title: "Random"
        )
        let overspecified = CoreAIPipelineNode(
            id: "randomTwice",
            kind: .seededRandom,
            title: "Random twice",
            inputs: [
                CoreAIPipelinePort(
                    name: "seed",
                    value: CoreAIPipelineValueContract(kind: .scalar)
                )
            ],
            fixedSeed: 42,
            seedInputPort: "seed"
        )
        let manifest = CoreAIPipelineManifest(
            id: "randomness",
            displayName: "Randomness",
            hostOperatorRegistryVersion: 1,
            nodes: [unseeded, overspecified],
            edges: []
        )

        #expect(CoreAIPipelineValidator.issues(in: manifest).count(where: {
            $0.code == .unseededRandomness
        }) == 2)
    }

    @Test
    func loopsRequireABoundAndStopCondition() {
        let invalidLoop = CoreAIPipelineNode(
            id: "loop",
            kind: .boundedLoop,
            title: "Loop",
            maximumIterations: 0,
            stopConditionInputPort: "stop"
        )
        let manifest = CoreAIPipelineManifest(
            id: "loopValidation",
            displayName: "Loop validation",
            hostOperatorRegistryVersion: 1,
            nodes: [invalidLoop],
            edges: []
        )

        let codes = Set(CoreAIPipelineValidator.issues(in: manifest).map(\.code))
        #expect(codes.contains(.invalidLoopBound))
        #expect(codes.contains(.missingLoopStopCondition))
    }

    @Test
    func requiredInputsAndExecutableReferencesCannotBeImplicit() {
        let tensor = tensorContract(shape: [.fixed(1)])
        let node = CoreAIPipelineNode(
            id: "model",
            kind: .assetFunction,
            title: "Model",
            inputs: [CoreAIPipelinePort(name: "input", value: tensor)]
        )
        let manifest = CoreAIPipelineManifest(
            id: "implicit",
            displayName: "Implicit",
            hostOperatorRegistryVersion: 1,
            nodes: [node],
            edges: []
        )

        let codes = Set(CoreAIPipelineValidator.issues(in: manifest).map(\.code))
        #expect(codes.contains(.missingReference))
        #expect(codes.contains(.unconnectedRequiredInput))
    }

    @Test
    func sourceConstraintsMustFitInsideDestinationConstraints() {
        let source = tensorContract(shape: [
            .dynamic("sequence", minimum: 1, maximum: 128)
        ])
        let widerDestination = tensorContract(shape: [
            .dynamic("tokens", minimum: 1, maximum: 256)
        ])
        let overlappingDestination = tensorContract(shape: [
            .dynamic("tokens", minimum: 64, maximum: 256)
        ])
        let fixedSource = tensorContract(shape: [.fixed(64)])

        #expect(source.isCompatible(with: widerDestination))
        #expect(!source.isCompatible(with: overlappingDestination))
        #expect(fixedSource.isCompatible(with: widerDestination))
    }

    @Test
    func destinationRequirementsCannotBeSatisfiedByMissingSourceMetadata() {
        let unspecified = CoreAIPipelineValueContract(kind: .tensor)
        let required = tensorContract(shape: [.fixed(4)])

        #expect(!unspecified.isCompatible(with: required))
        #expect(required.isCompatible(with: unspecified))
    }

    @Test
    func controlPortsMustBeRequiredTypedAndConnected() {
        let random = CoreAIPipelineNode(
            id: "random",
            kind: .seededRandom,
            title: "Random",
            inputs: [
                CoreAIPipelinePort(
                    name: "seed",
                    value: CoreAIPipelineValueContract(
                        kind: .scalar,
                        scalarType: "float32"
                    ),
                    isOptional: true
                )
            ],
            seedInputPort: "seed"
        )
        let loop = CoreAIPipelineNode(
            id: "loop",
            kind: .boundedLoop,
            title: "Loop",
            inputs: [
                CoreAIPipelinePort(
                    name: "stop",
                    value: CoreAIPipelineValueContract(
                        kind: .scalar,
                        scalarType: "bool"
                    ),
                    isOptional: true
                )
            ],
            maximumIterations: 10,
            stopConditionInputPort: "stop"
        )
        let manifest = CoreAIPipelineManifest(
            id: "controls",
            displayName: "Controls",
            hostOperatorRegistryVersion: 1,
            nodes: [random, loop],
            edges: []
        )

        let issues = CoreAIPipelineValidator.issues(in: manifest)
        #expect(issues.contains { $0.code == .unseededRandomness })
        #expect(issues.contains { $0.code == .incompatibleValue })
        #expect(issues.count(where: { $0.code == .unconnectedRequiredInput }) == 2)
    }

    @Test
    func optionalOutputsCannotSatisfyRequiredInputs() {
        let scalar = CoreAIPipelineValueContract(
            kind: .scalar,
            scalarType: "bool"
        )
        let source = CoreAIPipelineNode(
            id: "source",
            kind: .input,
            title: "Source",
            outputs: [
                CoreAIPipelinePort(
                    name: "output",
                    value: scalar,
                    isOptional: true
                )
            ]
        )
        let destination = CoreAIPipelineNode(
            id: "destination",
            kind: .output,
            title: "Destination",
            inputs: [CoreAIPipelinePort(name: "input", value: scalar)]
        )
        let manifest = CoreAIPipelineManifest(
            id: "optionalSource",
            displayName: "Optional source",
            hostOperatorRegistryVersion: 1,
            nodes: [source, destination],
            edges: [edge(from: source.id, to: destination.id)]
        )

        #expect(CoreAIPipelineValidator.issues(in: manifest).contains {
            $0.code == .incompatibleValue
                && $0.message.contains("optional output")
        })
    }

    @Test
    func executableReferencesMustBeSafeLogicalIdentifiers() {
        let nodes = ["   ", "../../asset"].enumerated().map { index, reference in
            CoreAIPipelineNode(
                id: "model\(index)",
                kind: .assetFunction,
                title: "Model",
                reference: reference
            )
        }
        let manifest = CoreAIPipelineManifest(
            id: "unsafeReferences",
            displayName: "Unsafe references",
            hostOperatorRegistryVersion: 1,
            nodes: nodes,
            edges: []
        )

        #expect(CoreAIPipelineValidator.issues(in: manifest).count(where: {
            $0.code == .invalidReference
        }) == 2)
    }

    @Test
    func futureSchemaIsRejectedBeforeUnknownNodeKindsDecode() {
        let data = Data(#"""
        {
          "schemaVersion": 2,
          "id": "future",
          "displayName": "Future",
          "hostOperatorRegistryVersion": 1,
          "nodes": [{"id":"future","kind":"futureNode"}],
          "edges": []
        }
        """#.utf8)

        do {
            _ = try CoreAIPipelineCodec.decode(data)
            Issue.record("Expected an unsupported-schema error")
        } catch let error as CoreAIPipelineValidationError {
            #expect(error.issues.map(\.code) == [.unsupportedSchemaVersion])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func nodeKindsRejectContradictoryConfigurationAndBoundaryStateOwners() {
        let input = CoreAIPipelineNode(
            id: "input",
            kind: .input,
            title: "Input",
            reference: "model.main"
        )
        let state = CoreAIPipelineNode(
            id: "state",
            kind: .state,
            title: "State",
            stateKey: "cache",
            ownerNodeID: input.id,
            fixedSeed: 42
        )
        let manifest = CoreAIPipelineManifest(
            id: "closedPayload",
            displayName: "Closed payload",
            hostOperatorRegistryVersion: 1,
            nodes: [input, state],
            edges: []
        )

        let codes = Set(CoreAIPipelineValidator.issues(in: manifest).map(\.code))
        #expect(codes.contains(.invalidNodeConfiguration))
        #expect(codes.contains(.invalidStateOwnership))
    }

    @Test
    func edgeIdentityCannotCollideWhenEndpointsContainDots() {
        let first = CoreAIPipelineEdge(
            source: CoreAIPipelineEndpoint(nodeID: "a.b", portName: "c"),
            destination: CoreAIPipelineEndpoint(nodeID: "d", portName: "e")
        )
        let second = CoreAIPipelineEdge(
            source: CoreAIPipelineEndpoint(nodeID: "a", portName: "b.c"),
            destination: CoreAIPipelineEndpoint(nodeID: "d", portName: "e")
        )

        #expect(first.id != second.id)
    }

    @Test
    func stateDiagnosticsAreIndependentOfManifestNodeOrder() {
        let owner = CoreAIPipelineNode(
            id: "owner",
            kind: .hostOperator,
            title: "Owner",
            reference: "operator.owner"
        )
        let first = CoreAIPipelineNode(
            id: "aState",
            kind: .state,
            title: "A",
            stateKey: "cache",
            ownerNodeID: owner.id
        )
        let second = CoreAIPipelineNode(
            id: "zState",
            kind: .state,
            title: "Z",
            stateKey: "cache",
            ownerNodeID: owner.id
        )
        func issues(_ nodes: [CoreAIPipelineNode]) -> [CoreAIPipelineValidationIssue] {
            CoreAIPipelineValidator.issues(in: CoreAIPipelineManifest(
                id: "deterministicState",
                displayName: "Deterministic state",
                hostOperatorRegistryVersion: 1,
                nodes: nodes,
                edges: []
            ))
        }

        #expect(issues([owner, first, second]) == issues([second, owner, first]))
    }

    private func validManifest() -> CoreAIPipelineManifest {
        let tensor = tensorContract(shape: [
            .fixed(1),
            .dynamic("sequence", minimum: 1, maximum: 256)
        ])
        let input = sourceNode(id: "prompt", contract: tensor)
        let model = CoreAIPipelineNode(
            id: "model",
            kind: .assetFunction,
            title: "Model",
            reference: "model.main",
            inputs: [CoreAIPipelinePort(name: "input", value: tensor)],
            outputs: [CoreAIPipelinePort(name: "output", value: tensor)]
        )
        let output = CoreAIPipelineNode(
            id: "result",
            kind: .output,
            title: "Result",
            inputs: [CoreAIPipelinePort(name: "input", value: tensor)]
        )
        return CoreAIPipelineManifest(
            id: "fixture.pipeline",
            displayName: "Fixture pipeline",
            hostOperatorRegistryVersion: 1,
            nodes: [input, model, output],
            edges: [
                edge(from: "prompt", to: "model"),
                edge(from: "model", to: "result")
            ]
        )
    }

    private func sourceNode(
        id: String,
        contract: CoreAIPipelineValueContract
    ) -> CoreAIPipelineNode {
        CoreAIPipelineNode(
            id: id,
            kind: .input,
            title: id,
            outputs: [CoreAIPipelinePort(name: "output", value: contract)]
        )
    }

    private func edge(from source: String, to destination: String) -> CoreAIPipelineEdge {
        CoreAIPipelineEdge(
            source: CoreAIPipelineEndpoint(nodeID: source, portName: "output"),
            destination: CoreAIPipelineEndpoint(nodeID: destination, portName: "input")
        )
    }

    private func tensorContract(
        shape: [CoreAIPipelineDimension]
    ) -> CoreAIPipelineValueContract {
        CoreAIPipelineValueContract(
            kind: .tensor,
            scalarType: "float32",
            shape: shape
        )
    }
}
