import Foundation
import Testing
@testable import CoreAILab

@MainActor
struct CoreAIRecipeStudioTests {
    @Test
    func completeRecipeRoundTripsDeterministically() throws {
        var recipe = CoreAIRecipeAuthoringManifest.starter
        recipe.source = CoreAIRecipeSource(
            kind: .huggingFaceRepository,
            location: "organization/model",
            revision: "0123456789abcdef"
        )
        recipe.stateBindings = [
            CoreAIRecipeStateBinding(
                id: "kv_cache",
                name: "kv_cache",
                inputName: "kv_cache_input",
                outputName: "kv_cache_output",
                initialValueReference: "fixtures/empty-cache.safetensors",
                isMutable: true
            )
        ]
        recipe.externalizationRules = [
            CoreAIRecipeExternalizationRule(
                id: "transformer_weights",
                modulePath: "model.transformer",
                strategy: .separateWeights,
                minimumBytes: 1_048_576,
                resourceName: "transformer_weights"
            )
        ]
        recipe.functionEntrypoints[0].stateNames = ["kv_cache"]
        recipe.unsupportedOperations = [finding()]

        let firstEncoding = try CoreAIRecipeCodec.encode(recipe)
        let decoded = try CoreAIRecipeCodec.decode(firstEncoding)
        let secondEncoding = try CoreAIRecipeCodec.encode(decoded)

        #expect(decoded == recipe)
        #expect(firstEncoding == secondEncoding)
        #expect(String(decoding: firstEncoding, as: UTF8.self).contains("\"pipeline\""))
    }

    @Test
    func unsupportedSchemaVersionStopsBeforePartialDecoding() {
        let data = Data(#"{"schemaVersion":99}"#.utf8)

        #expect(throws: CoreAIRecipeValidationError.self) {
            try CoreAIRecipeCodec.decode(data)
        }
    }

    @Test
    func validationReportsDanglingAuthoringReferencesAndAttribution() {
        var recipe = CoreAIRecipeAuthoringManifest.starter
        recipe.dynamicDimensions[0].inputName = "missing_input"
        recipe.functionEntrypoints[0].stateNames = ["missing_state"]
        recipe.unsupportedOperations = [
            CoreAIUnsupportedOperationFinding(
                id: "missing_attribution",
                severity: .blocker,
                operatorName: "aten.example",
                modulePath: "",
                sourceFile: "",
                sourceLine: 0,
                message: "Unsupported",
                exampleShapes: [],
                suggestedRewriteID: ""
            )
        ]

        let issues = CoreAIRecipeValidator.issues(in: recipe)
        let codes = Set(issues.map(\.code))

        #expect(codes.contains(.unknownReference))
        #expect(codes.contains(.incompleteAttribution))
        #expect(issues.contains { $0.location.contains("dynamicDimensions") })
        #expect(issues.contains { $0.location.contains("stateNames") })
    }

    @Test
    func builtInRewriteCatalogHasStableUniqueEvidenceBackedEntries() {
        let rewrites = CoreAIRecipeRewriteCatalog.builtIn

        #expect(Set(rewrites.map(\.id)).count == rewrites.count)
        #expect(rewrites.contains { $0.id == "fixed_filter_fourier" })
        #expect(rewrites.contains { $0.strategy == .customLowering })
        #expect(rewrites.allSatisfy { !$0.operatorNames.isEmpty && !$0.evidence.isEmpty })
    }

    @Test
    func generatedEscapeHatchesFailUntilImplemented() throws {
        let artifacts = CoreAIRecipeStubGenerator.artifacts(for: finding())
        let lowering = try #require(artifacts.first { $0.kind == .customLowering })
        let metal = try #require(artifacts.first { $0.kind == .metalKernel })

        #expect(artifacts.count == 2)
        #expect(!artifacts.contains { $0.relativePath.contains("..") })
        #expect(lowering.contents.contains("register_torch_lowering"))
        #expect(lowering.contents.contains("NotImplementedError"))
        #expect(lowering.contents.contains("vocoder.fourier"))
        #expect(lowering.contents.contains("vocoder.py:136"))
        #expect(metal.contents.contains("#error"))
        #expect(metal.contents.contains("thread_position_in_grid"))
    }

    @Test
    func workspaceConnectsTypedNodesAndRemovesEdgesWithTheirNode() throws {
        let workspace = CoreAIRecipeStudioWorkspaceModel()
        workspace.addPipelineNode(kind: .hostOperator)
        let node = try #require(workspace.recipe.pipeline.nodes.last)
        workspace.selectedSourceEndpoint = CoreAIPipelineEndpoint(
            nodeID: "model_forward",
            portName: "output"
        )
        workspace.selectedDestinationEndpoint = CoreAIPipelineEndpoint(
            nodeID: node.id,
            portName: "input"
        )

        #expect(workspace.canConnectSelectedEndpoints)
        workspace.connectSelectedEndpoints()
        #expect(workspace.pipelineIssues.isEmpty)

        workspace.removePipelineNode(id: node.id)
        #expect(!workspace.recipe.pipeline.edges.contains {
            $0.source.nodeID == node.id || $0.destination.nodeID == node.id
        })
        #expect(workspace.pipelineIssues.isEmpty)
    }

    @Test
    func workspaceRenamesAuthoringReferencesAndStopsAtAvailableDynamicAxes() throws {
        let workspace = CoreAIRecipeStudioWorkspaceModel()
        let input = try #require(workspace.recipe.exampleInputs.first)

        workspace.renameExampleInput(id: input.id, to: "renamed_features")

        #expect(workspace.recipe.dynamicDimensions.first?.inputName == "renamed_features")
        #expect(workspace.recipe.functionEntrypoints.first?.inputNames == ["renamed_features"])

        workspace.addStateBinding()
        let state = try #require(workspace.recipe.stateBindings.first)
        workspace.recipe.functionEntrypoints[0].stateNames = [state.name]
        workspace.renameStateBinding(id: state.id, to: "renamed_state")

        #expect(workspace.recipe.functionEntrypoints[0].stateNames == ["renamed_state"])

        workspace.addDynamicDimension()
        workspace.addDynamicDimension()
        let completeAxisCount = workspace.recipe.dynamicDimensions.count
        workspace.addDynamicDimension()

        #expect(completeAxisCount == input.shape.count)
        #expect(workspace.recipe.dynamicDimensions.count == completeAxisCount)
        #expect(
            Set(workspace.recipe.dynamicDimensions.map { "\($0.inputName):\($0.axis)" }).count
                == completeAxisCount
        )
        #expect(!workspace.canAddDynamicDimension)
    }

    @Test
    func dynamicDimensionAdditionAdvancesAcrossTensorInputs() {
        let workspace = CoreAIRecipeStudioWorkspaceModel()
        workspace.recipe.exampleInputs.append(CoreAIRecipeExampleInput(
            id: "attention_mask",
            name: "attention_mask",
            kind: .tensor,
            scalarType: "int32",
            shape: [1, 300],
            fixturePath: "",
            literalValue: ""
        ))

        workspace.addDynamicDimension()
        workspace.addDynamicDimension()
        workspace.addDynamicDimension()

        #expect(workspace.recipe.dynamicDimensions.last?.inputName == "attention_mask")
        #expect(workspace.recipe.dynamicDimensions.last?.axis == 0)
        #expect(workspace.canAddDynamicDimension)

        workspace.addDynamicDimension()

        #expect(workspace.recipe.dynamicDimensions.last?.inputName == "attention_mask")
        #expect(workspace.recipe.dynamicDimensions.last?.axis == 1)
        #expect(!workspace.canAddDynamicDimension)
    }

    @Test
    func duplicateAuthoringNamesDoNotStealSharedReferences() throws {
        let renameWorkspace = CoreAIRecipeStudioWorkspaceModel()
        var duplicateInput = try #require(renameWorkspace.recipe.exampleInputs.first)
        duplicateInput.id = "features_duplicate"
        renameWorkspace.recipe.exampleInputs.append(duplicateInput)

        #expect(!renameWorkspace.unambiguousExampleInputNames.contains("features"))
        #expect(!renameWorkspace.canAddDynamicDimension)

        renameWorkspace.renameExampleInput(id: duplicateInput.id, to: "renamed_features")

        #expect(renameWorkspace.recipe.dynamicDimensions.first?.inputName == "features")
        #expect(renameWorkspace.recipe.functionEntrypoints.first?.inputNames == ["features"])

        renameWorkspace.addStateBinding()
        var duplicateState = try #require(renameWorkspace.recipe.stateBindings.first)
        duplicateState.id = "state_duplicate"
        renameWorkspace.recipe.stateBindings.append(duplicateState)
        renameWorkspace.recipe.functionEntrypoints[0].stateNames = [duplicateState.name]

        #expect(!renameWorkspace.unambiguousStateNames.contains("state"))

        renameWorkspace.renameStateBinding(id: duplicateState.id, to: "renamed_state")

        #expect(renameWorkspace.recipe.functionEntrypoints[0].stateNames == ["state"])

        let removalWorkspace = CoreAIRecipeStudioWorkspaceModel()
        duplicateInput = try #require(removalWorkspace.recipe.exampleInputs.first)
        duplicateInput.id = "features_duplicate"
        removalWorkspace.recipe.exampleInputs.append(duplicateInput)
        removalWorkspace.removeExampleInput(id: duplicateInput.id)

        #expect(removalWorkspace.recipe.dynamicDimensions.first?.inputName == "features")
        #expect(removalWorkspace.recipe.functionEntrypoints.first?.inputNames == ["features"])

        removalWorkspace.addStateBinding()
        duplicateState = try #require(removalWorkspace.recipe.stateBindings.first)
        duplicateState.id = "state_duplicate"
        removalWorkspace.recipe.stateBindings.append(duplicateState)
        removalWorkspace.recipe.functionEntrypoints[0].stateNames = [duplicateState.name]
        removalWorkspace.removeStateBinding(id: duplicateState.id)

        #expect(removalWorkspace.recipe.functionEntrypoints[0].stateNames == ["state"])
    }

    @Test
    func outputNameAllocationStaysUniqueAfterRemoval() {
        let values = ["output_1", "output_3"]

        #expect(CoreAIRecipeOutputListEditorView.nextOutputName(in: values) == "output_4")
    }

    @Test
    func referenceChoicesRemainStableWhenDraftNamesCollide() throws {
        let values = ["features", "features", "attention_mask", "features"]

        #expect(CoreAIRecipeReferenceListEditorView.uniqueValues(values) == [
            "features", "attention_mask"
        ])

        var recipe = CoreAIRecipeAuthoringManifest.starter
        let duplicateInput = try #require(recipe.exampleInputs.first)
        recipe.exampleInputs.append(duplicateInput)
        recipe.exampleInputs.append(duplicateInput)
        let issues = CoreAIRecipeValidator.issues(in: recipe)

        #expect(issues.contains { $0.code == .duplicateValue })
        #expect(Set(issues.map(\.id)).count == issues.count)
    }

    @Test
    func pipelinePortMutationsKeepOrRemoveEdgesAtomically() throws {
        let workspace = CoreAIRecipeStudioWorkspaceModel()

        workspace.renamePipelinePort(
            nodeID: "model_forward",
            output: false,
            index: 0,
            to: "renamed_features"
        )
        #expect(workspace.recipe.pipeline.edges.contains {
            $0.destination
                == CoreAIPipelineEndpoint(
                    nodeID: "model_forward",
                    portName: "renamed_features"
                )
        })
        #expect(workspace.pipelineIssues.isEmpty)

        workspace.removePipelinePort(
            nodeID: "model_forward",
            output: true,
            index: 0
        )
        #expect(!workspace.recipe.pipeline.edges.contains {
            $0.source.nodeID == "model_forward"
        })

        workspace.updatePipelineNodeKind(id: "model_forward", to: .output)
        #expect(!workspace.recipe.pipeline.edges.contains {
            $0.source.nodeID == "model_forward"
        })
        #expect(!workspace.pipelineIssues.contains { $0.code == .missingPort })
    }

    @Test
    func pipelineKindChangesMaintainStructuralConfiguration() throws {
        let workspace = CoreAIRecipeStudioWorkspaceModel()

        workspace.updatePipelineNodeKind(id: "model_forward", to: .boundedLoop)
        let loop = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "model_forward"
        })
        let stopIndex = try #require(loop.inputs.firstIndex {
            $0.name == loop.stopConditionInputPort
        })

        workspace.removePipelinePort(
            nodeID: "model_forward",
            output: false,
            index: stopIndex
        )

        let preservedLoop = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "model_forward"
        })
        #expect(preservedLoop.stopConditionInputPort == "stop")
        #expect(preservedLoop.inputs.contains { $0.name == "stop" })

        workspace.updatePipelineNodeKind(id: "model_forward", to: .assetFunction)
        let function = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "model_forward"
        })
        #expect(function.stopConditionInputPort == nil)
        #expect(!function.inputs.contains { $0.name == "stop" })

        workspace.addPipelineNode(kind: .assetFunction)
        let ownerID = try #require(workspace.recipe.pipeline.nodes.last?.id)
        workspace.updatePipelineNodeKind(id: "model_forward", to: .state)
        let state = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "model_forward"
        })
        #expect(state.ownerNodeID == ownerID)
    }

    @Test
    func pipelineSpecialPortRenamesPreserveConfigurationAndRemovalGuards() throws {
        let workspace = CoreAIRecipeStudioWorkspaceModel()

        workspace.updatePipelineNodeKind(id: "model_forward", to: .boundedLoop)
        let loop = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "model_forward"
        })
        let stopIndex = try #require(loop.inputs.firstIndex {
            $0.name == loop.stopConditionInputPort
        })
        workspace.renamePipelinePort(
            nodeID: loop.id,
            output: false,
            index: stopIndex,
            to: "should_stop"
        )

        var renamedLoop = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == loop.id
        })
        #expect(renamedLoop.stopConditionInputPort == "should_stop")
        #expect(!workspace.pipelineIssues.contains { $0.code == .missingLoopStopCondition })

        workspace.updatePipelineNodeKind(id: renamedLoop.id, to: .boundedLoop)
        renamedLoop = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == loop.id
        })
        #expect(renamedLoop.stopConditionInputPort == "should_stop")
        #expect(renamedLoop.inputs.contains { $0.name == "should_stop" })
        #expect(!renamedLoop.inputs.contains { $0.name == "stop" })
        #expect(renamedLoop.inputs.filter { $0.name != "should_stop" }.map(\.name) == ["features"])

        let renamedStopIndex = try #require(renamedLoop.inputs.firstIndex {
            $0.name == renamedLoop.stopConditionInputPort
        })
        workspace.removePipelinePort(
            nodeID: renamedLoop.id,
            output: false,
            index: renamedStopIndex
        )
        renamedLoop = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == loop.id
        })
        #expect(renamedLoop.inputs.contains { $0.name == "should_stop" })

        let seedValue = CoreAIPipelineValueContract(
            kind: .scalar,
            scalarType: "int64"
        )
        workspace.recipe.pipeline.nodes.append(CoreAIPipelineNode(
            id: "random",
            kind: .seededRandom,
            title: "Random",
            inputs: [CoreAIPipelinePort(name: "seed", value: seedValue)],
            outputs: [CoreAIPipelinePort(name: "output", value: seedValue)],
            seedInputPort: "seed"
        ))
        workspace.renamePipelinePort(
            nodeID: "random",
            output: false,
            index: 0,
            to: "random_seed"
        )

        var random = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "random"
        })
        #expect(random.seedInputPort == "random_seed")
        #expect(!workspace.pipelineIssues.contains { issue in
            issue.code == .missingPort && issue.location.contains("random")
        })

        workspace.removePipelinePort(nodeID: random.id, output: false, index: 0)
        random = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "random"
        })
        #expect(random.inputs.contains { $0.name == "random_seed" })

        workspace.updatePipelineNodeKind(id: random.id, to: .seededRandom)
        random = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "random"
        })
        #expect(random.fixedSeed == nil)
        #expect(random.seedInputPort == "random_seed")
        #expect(random.inputs.contains { $0.name == "random_seed" })

        workspace.updatePipelineNodeKind(id: random.id, to: .hostOperator)
        random = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "random"
        })
        #expect(random.seedInputPort == nil)
        #expect(!random.inputs.contains { $0.name == "random_seed" })
    }

    @Test
    func connectionEligibilityMatchesOptionalityValidation() throws {
        let workspace = CoreAIRecipeStudioWorkspaceModel()
        let sourceEndpoint = CoreAIPipelineEndpoint(
            nodeID: "features_input",
            portName: "features"
        )
        let destinationEndpoint = CoreAIPipelineEndpoint(
            nodeID: "model_forward",
            portName: "features"
        )
        workspace.recipe.pipeline.edges.removeAll {
            $0.source == sourceEndpoint && $0.destination == destinationEndpoint
        }
        let sourceIndex = try #require(workspace.recipe.pipeline.nodes.firstIndex {
            $0.id == sourceEndpoint.nodeID
        })
        let destinationIndex = try #require(workspace.recipe.pipeline.nodes.firstIndex {
            $0.id == destinationEndpoint.nodeID
        })
        workspace.recipe.pipeline.nodes[sourceIndex].outputs[0].isOptional = true
        workspace.recipe.pipeline.nodes[destinationIndex].inputs[0].isOptional = false
        workspace.selectedSourceEndpoint = sourceEndpoint
        workspace.selectedDestinationEndpoint = destinationEndpoint

        #expect(!workspace.canConnectSelectedEndpoints)

        workspace.recipe.pipeline.nodes[destinationIndex].inputs[0].isOptional = true

        #expect(workspace.canConnectSelectedEndpoints)
    }

    @Test
    func pipelineEndpointIdentityKeepsStructuredComponentsDistinct() {
        let first = CoreAIPipelineEndpoint(nodeID: "a.b", portName: "c")
        let second = CoreAIPipelineEndpoint(nodeID: "a", portName: "b.c")

        #expect(first.diagnosticDescription == second.diagnosticDescription)
        #expect(first.id != second.id)
    }

    @Test
    func pipelinePickersRemainStableWhileDuplicateNamesAreInvalid() throws {
        let workspace = CoreAIRecipeStudioWorkspaceModel()
        let nodeIndex = try #require(workspace.recipe.pipeline.nodes.firstIndex {
            $0.id == "model_forward"
        })
        let output = try #require(workspace.recipe.pipeline.nodes[nodeIndex].outputs.first)
        workspace.recipe.pipeline.nodes[nodeIndex].outputs.append(output)
        workspace.recipe.pipeline.nodes[nodeIndex].outputs.append(output)
        let duplicateEdge = try #require(workspace.recipe.pipeline.edges.first)
        workspace.recipe.pipeline.edges.append(duplicateEdge)

        let endpoint = CoreAIPipelineEndpoint(
            nodeID: "model_forward",
            portName: output.name
        )
        #expect(workspace.sourceEndpoints.count(where: { $0 == endpoint }) == 0)
        #expect(workspace.displayedPipelineEdges.count == workspace.recipe.pipeline.edges.count - 1)
        #expect(workspace.pipelineIssues.contains { $0.code == .duplicatePort })
        #expect(workspace.pipelineIssues.contains { $0.code == .duplicateEdge })
        #expect(Set(workspace.pipelineIssues.map(\.id)).count == workspace.pipelineIssues.count)
    }

    @Test
    func duplicatePipelinePortEditsLeaveSharedEndpointsIntact() throws {
        let workspace = CoreAIRecipeStudioWorkspaceModel()
        let nodeIndex = try #require(workspace.recipe.pipeline.nodes.firstIndex {
            $0.id == "model_forward"
        })
        let input = try #require(workspace.recipe.pipeline.nodes[nodeIndex].inputs.first)
        let output = try #require(workspace.recipe.pipeline.nodes[nodeIndex].outputs.first)
        let inputEndpoint = CoreAIPipelineEndpoint(
            nodeID: "model_forward",
            portName: input.name
        )
        let outputEndpoint = CoreAIPipelineEndpoint(
            nodeID: "model_forward",
            portName: output.name
        )
        workspace.recipe.pipeline.nodes[nodeIndex].inputs.append(input)
        workspace.recipe.pipeline.nodes[nodeIndex].outputs.append(output)
        workspace.selectedDestinationEndpoint = inputEndpoint
        workspace.selectedSourceEndpoint = outputEndpoint

        workspace.renamePipelinePort(
            nodeID: "model_forward",
            output: false,
            index: 1,
            to: "alternate_input"
        )
        workspace.renamePipelinePort(
            nodeID: "model_forward",
            output: true,
            index: 1,
            to: "alternate_output"
        )

        #expect(workspace.selectedDestinationEndpoint == inputEndpoint)
        #expect(workspace.selectedSourceEndpoint == outputEndpoint)
        #expect(workspace.recipe.pipeline.edges.contains { $0.destination == inputEndpoint })
        #expect(workspace.recipe.pipeline.edges.contains { $0.source == outputEndpoint })

        workspace.recipe.pipeline.nodes[nodeIndex].inputs.append(input)
        workspace.recipe.pipeline.nodes[nodeIndex].outputs.append(output)
        workspace.removePipelinePort(nodeID: "model_forward", output: false, index: 2)
        workspace.removePipelinePort(nodeID: "model_forward", output: true, index: 2)

        #expect(workspace.recipe.pipeline.edges.contains { $0.destination == inputEndpoint })
        #expect(workspace.recipe.pipeline.edges.contains { $0.source == outputEndpoint })
        #expect(workspace.selectedDestinationEndpoint == inputEndpoint)
        #expect(workspace.selectedSourceEndpoint == outputEndpoint)

        workspace.updatePipelineNodeKind(id: "model_forward", to: .boundedLoop)
        let loop = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == "model_forward"
        })
        let stop = try #require(loop.inputs.first {
            $0.name == loop.stopConditionInputPort
        })
        let currentLoopIndex = try #require(workspace.recipe.pipeline.nodes.firstIndex {
            $0.id == loop.id
        })
        workspace.recipe.pipeline.nodes[currentLoopIndex].inputs.append(stop)
        let duplicateStopIndex = workspace.recipe.pipeline.nodes[currentLoopIndex].inputs.count - 1
        workspace.removePipelinePort(
            nodeID: loop.id,
            output: false,
            index: duplicateStopIndex
        )
        let updatedLoop = try #require(workspace.recipe.pipeline.nodes.first {
            $0.id == loop.id
        })

        #expect(updatedLoop.stopConditionInputPort == stop.name)
        #expect(updatedLoop.inputs.count(where: { $0.name == stop.name }) == 1)
    }

    private func finding() -> CoreAIUnsupportedOperationFinding {
        CoreAIUnsupportedOperationFinding(
            id: "stft",
            severity: .blocker,
            operatorName: "aten.stft.default",
            modulePath: "vocoder.fourier",
            sourceFile: "vocoder.py",
            sourceLine: 136,
            message: "The converter did not lower this fixed-window Fourier operation.",
            exampleShapes: ["waveform: [1, 24000]"],
            suggestedRewriteID: "fixed_filter_fourier"
        )
    }
}
