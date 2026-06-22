import Foundation
import Observation

@MainActor
@Observable
final class CoreAIRecipeStudioWorkspaceModel {
    var recipe: CoreAIRecipeManifest
    var selectedSourceEndpoint: CoreAIPipelineEndpoint?
    var selectedDestinationEndpoint: CoreAIPipelineEndpoint?
    private(set) var generatedArtifacts: [CoreAIRecipeGeneratedArtifact] = []

    init(recipe: CoreAIRecipeManifest = .starter) {
        self.recipe = recipe
    }

    var validationIssues: [CoreAIRecipeValidationIssue] {
        CoreAIRecipeValidator.issues(in: recipe)
    }

    var pipelineIssues: [CoreAIPipelineValidationIssue] {
        CoreAIPipelineValidator.issues(in: recipe.pipeline)
    }

    var tensorInputNames: [String] {
        recipe.exampleInputs
            .filter { $0.kind == .tensor }
            .map(\.name)
            .sorted()
    }

    var sourceEndpoints: [CoreAIPipelineEndpoint] {
        recipe.pipeline.nodes.flatMap { node in
            node.outputs.map {
                CoreAIPipelineEndpoint(nodeID: node.id, portName: $0.name)
            }
        }
    }

    var destinationEndpoints: [CoreAIPipelineEndpoint] {
        recipe.pipeline.nodes.flatMap { node in
            node.inputs.map {
                CoreAIPipelineEndpoint(nodeID: node.id, portName: $0.name)
            }
        }
    }

    var canConnectSelectedEndpoints: Bool {
        guard let selectedSourceEndpoint,
              let selectedDestinationEndpoint,
              let source = port(at: selectedSourceEndpoint, output: true),
              let destination = port(at: selectedDestinationEndpoint, output: false)
        else {
            return false
        }
        let edge = CoreAIPipelineEdge(
            source: selectedSourceEndpoint,
            destination: selectedDestinationEndpoint
        )
        return source.value.isCompatible(with: destination.value)
            && !recipe.pipeline.edges.contains(edge)
            && !recipe.pipeline.edges.contains {
                $0.destination == selectedDestinationEndpoint
            }
    }

    func addExampleInput() {
        let name = uniqueName(prefix: "input", existing: recipe.exampleInputs.map(\.name))
        recipe.exampleInputs.append(CoreAIRecipeExampleInput(
            id: uniqueID(prefix: name),
            name: name,
            kind: .tensor,
            scalarType: "float32",
            shape: [1],
            fixturePath: "",
            literalValue: ""
        ))
    }

    func removeExampleInput(id: String) {
        guard let input = recipe.exampleInputs.first(where: { $0.id == id }) else {
            return
        }
        recipe.exampleInputs.removeAll { $0.id == id }
        recipe.dynamicDimensions.removeAll { $0.inputName == input.name }
        for index in recipe.functionEntrypoints.indices {
            recipe.functionEntrypoints[index].inputNames.removeAll { $0 == input.name }
        }
    }

    func addDynamicDimension() {
        guard let input = recipe.exampleInputs.first(where: { $0.kind == .tensor }),
              !input.shape.isEmpty else {
            return
        }
        let usedAxes = Set(recipe.dynamicDimensions.filter {
            $0.inputName == input.name
        }.map(\.axis))
        let axis = input.shape.indices.first { !usedAxes.contains($0) } ?? 0
        recipe.dynamicDimensions.append(CoreAIRecipeDynamicDimension(
            id: uniqueID(prefix: "dimension"),
            inputName: input.name,
            axis: axis,
            symbol: uniqueName(
                prefix: "dimension",
                existing: recipe.dynamicDimensions.map(\.symbol)
            ),
            minimum: 1,
            maximum: max(1, input.shape[axis])
        ))
    }

    func removeDynamicDimension(id: String) {
        recipe.dynamicDimensions.removeAll { $0.id == id }
    }

    func addStateBinding() {
        let name = uniqueName(prefix: "state", existing: recipe.stateBindings.map(\.name))
        recipe.stateBindings.append(CoreAIRecipeStateBinding(
            id: uniqueID(prefix: name),
            name: name,
            inputName: "\(name)_input",
            outputName: "\(name)_output",
            initialValueReference: "",
            isMutable: true
        ))
    }

    func removeStateBinding(id: String) {
        guard let state = recipe.stateBindings.first(where: { $0.id == id }) else {
            return
        }
        recipe.stateBindings.removeAll { $0.id == id }
        for index in recipe.functionEntrypoints.indices {
            recipe.functionEntrypoints[index].stateNames.removeAll { $0 == state.name }
        }
    }

    func addExternalizationRule() {
        let resourceName = uniqueName(
            prefix: "weights",
            existing: recipe.externalizationRules.map(\.resourceName)
        )
        recipe.externalizationRules.append(CoreAIRecipeExternalizationRule(
            id: uniqueID(prefix: "externalization"),
            modulePath: recipe.module.modulePath,
            strategy: .automatic,
            minimumBytes: 1_048_576,
            resourceName: resourceName
        ))
    }

    func removeExternalizationRule(id: String) {
        recipe.externalizationRules.removeAll { $0.id == id }
    }

    func addFunctionEntrypoint() {
        let name = uniqueName(
            prefix: "function",
            existing: recipe.functionEntrypoints.map(\.name)
        )
        recipe.functionEntrypoints.append(CoreAIRecipeFunctionEntrypoint(
            id: uniqueID(prefix: name),
            name: name,
            moduleMethod: name,
            inputNames: [],
            outputNames: ["output"],
            stateNames: []
        ))
    }

    func removeFunctionEntrypoint(id: String) {
        recipe.functionEntrypoints.removeAll { $0.id == id }
    }

    func generateStubs(for finding: CoreAIUnsupportedOperationFinding) {
        let artifacts = CoreAIRecipeStubGenerator.artifacts(for: finding)
        generatedArtifacts.removeAll { existing in
            artifacts.contains { $0.relativePath == existing.relativePath }
        }
        generatedArtifacts.append(contentsOf: artifacts)
        generatedArtifacts.sort { $0.relativePath < $1.relativePath }
    }

    func addPipelineNode(kind: CoreAIPipelineNodeKind) {
        let value = recipe.pipeline.nodes.lazy
            .flatMap(\.outputs)
            .first?.value
            ?? CoreAIPipelineValueContract(
                kind: .tensor,
                scalarType: "float32",
                shape: [.fixed(1)]
            )
        let id = uniqueID(prefix: kind.rawValue)
        let inputs: [CoreAIPipelinePort] = switch kind {
        case .input, .state, .seededRandom:
            []
        case .assetFunction, .hostOperator, .output:
            [CoreAIPipelinePort(name: "input", value: value)]
        case .boundedLoop:
            [
                CoreAIPipelinePort(name: "input", value: value),
                CoreAIPipelinePort(
                    name: "stop",
                    value: CoreAIPipelineValueContract(
                        kind: .scalar,
                        scalarType: "bool"
                    )
                )
            ]
        }
        let outputs: [CoreAIPipelinePort] = switch kind {
        case .output, .state:
            []
        case .input, .assetFunction, .hostOperator, .seededRandom, .boundedLoop:
            [CoreAIPipelinePort(name: "output", value: value)]
        }
        var node = CoreAIPipelineNode(
            id: id,
            kind: kind,
            title: kind.title,
            reference: [.assetFunction, .hostOperator].contains(kind)
                ? "executable.reference"
                : nil,
            inputs: inputs,
            outputs: outputs,
            stateKey: kind == .state ? "state" : nil,
            ownerNodeID: kind == .state ? executableNodeIDs.first : nil,
            fixedSeed: kind == .seededRandom ? 0 : nil,
            maximumIterations: kind == .boundedLoop ? 1 : nil,
            stopConditionInputPort: kind == .boundedLoop ? "stop" : nil
        )
        node.applyConfigurationDefaults()
        recipe.pipeline.nodes.append(node)
    }

    func removePipelineNode(id: String) {
        recipe.pipeline.nodes.removeAll { $0.id == id }
        recipe.pipeline.edges.removeAll {
            $0.source.nodeID == id || $0.destination.nodeID == id
        }
        if selectedSourceEndpoint?.nodeID == id {
            selectedSourceEndpoint = nil
        }
        if selectedDestinationEndpoint?.nodeID == id {
            selectedDestinationEndpoint = nil
        }
    }

    func connectSelectedEndpoints() {
        guard canConnectSelectedEndpoints,
              let selectedSourceEndpoint,
              let selectedDestinationEndpoint else {
            return
        }
        recipe.pipeline.edges.append(CoreAIPipelineEdge(
            source: selectedSourceEndpoint,
            destination: selectedDestinationEndpoint
        ))
        self.selectedSourceEndpoint = nil
        self.selectedDestinationEndpoint = nil
    }

    func removePipelineEdge(id: CoreAIPipelineEdge.ID) {
        recipe.pipeline.edges.removeAll { $0.id == id }
    }

    private var executableNodeIDs: [String] {
        recipe.pipeline.nodes.filter {
            [.assetFunction, .hostOperator, .boundedLoop].contains($0.kind)
        }.map(\.id)
    }

    private func port(
        at endpoint: CoreAIPipelineEndpoint,
        output: Bool
    ) -> CoreAIPipelinePort? {
        guard let node = recipe.pipeline.nodes.first(where: {
            $0.id == endpoint.nodeID
        }) else {
            return nil
        }
        return (output ? node.outputs : node.inputs).first {
            $0.name == endpoint.portName
        }
    }

    private func uniqueID(prefix: String) -> String {
        let suffix = UUID().uuidString.replacing("-", with: "").lowercased()
        return "\(prefix)_\(suffix)"
    }

    private func uniqueName(prefix: String, existing: [String]) -> String {
        let existing = Set(existing)
        if !existing.contains(prefix) {
            return prefix
        }
        var index = 2
        while existing.contains("\(prefix)_\(index)") {
            index += 1
        }
        return "\(prefix)_\(index)"
    }
}
