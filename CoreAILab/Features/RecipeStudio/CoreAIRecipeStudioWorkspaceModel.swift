import Foundation
import Observation

@MainActor
@Observable
final class CoreAIRecipeStudioWorkspaceModel {
    var recipe: CoreAIRecipeAuthoringManifest
    var selectedSourceEndpoint: CoreAIPipelineEndpoint?
    var selectedDestinationEndpoint: CoreAIPipelineEndpoint?
    private(set) var generatedArtifacts: [CoreAIRecipeGeneratedArtifact] = []

    init(recipe: CoreAIRecipeAuthoringManifest = .starter) {
        self.recipe = recipe
    }

    var validationIssues: [CoreAIRecipeValidationIssue] {
        CoreAIRecipeValidator.issues(in: recipe)
    }

    var pipelineIssues: [CoreAIPipelineValidationIssue] {
        CoreAIPipelineValidator.issues(in: recipe.pipeline)
    }

    var tensorInputNames: [String] {
        Set(recipe.exampleInputs
            .filter { $0.kind == .tensor }
            .map(\.name))
            .sorted()
    }

    var unambiguousExampleInputNames: [String] {
        recipe.exampleInputs.compactMap { input in
            recipe.exampleInputs.count(where: { $0.name == input.name }) == 1
                ? input.name
                : nil
        }
    }

    var unambiguousStateNames: [String] {
        recipe.stateBindings.compactMap { state in
            recipe.stateBindings.count(where: { $0.name == state.name }) == 1
                ? state.name
                : nil
        }
    }

    var canAddDynamicDimension: Bool {
        nextAvailableDynamicDimension != nil
    }

    var sourceEndpoints: [CoreAIPipelineEndpoint] {
        uniqueValues(recipe.pipeline.nodes.flatMap { node in
            node.outputs.compactMap { port in
                guard node.outputs.count(where: { $0.name == port.name }) == 1 else {
                    return nil
                }
                return CoreAIPipelineEndpoint(nodeID: node.id, portName: port.name)
            }
        })
    }

    var destinationEndpoints: [CoreAIPipelineEndpoint] {
        uniqueValues(recipe.pipeline.nodes.flatMap { node in
            node.inputs.compactMap { port in
                guard node.inputs.count(where: { $0.name == port.name }) == 1 else {
                    return nil
                }
                return CoreAIPipelineEndpoint(nodeID: node.id, portName: port.name)
            }
        })
    }

    var displayedPipelineEdges: [CoreAIPipelineEdge] {
        uniqueValues(recipe.pipeline.edges)
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
        return (!source.isOptional || destination.isOptional)
            && source.value.isCompatible(with: destination.value)
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
        let nameIsUnique = recipe.exampleInputs.count(where: {
            $0.name == input.name
        }) == 1
        recipe.exampleInputs.removeAll { $0.id == id }
        if nameIsUnique {
            recipe.dynamicDimensions.removeAll { $0.inputName == input.name }
            for index in recipe.functionEntrypoints.indices {
                recipe.functionEntrypoints[index].inputNames.removeAll { $0 == input.name }
            }
        }
    }

    func renameExampleInput(id: String, to name: String) {
        guard let index = recipe.exampleInputs.firstIndex(where: { $0.id == id }) else {
            return
        }
        let previousName = recipe.exampleInputs[index].name
        guard previousName != name else { return }
        let previousNameWasUnique = recipe.exampleInputs.count(where: {
            $0.name == previousName
        }) == 1
        recipe.exampleInputs[index].name = name
        if previousNameWasUnique {
            for index in recipe.dynamicDimensions.indices
            where recipe.dynamicDimensions[index].inputName == previousName {
                recipe.dynamicDimensions[index].inputName = name
            }
            for index in recipe.functionEntrypoints.indices {
                recipe.functionEntrypoints[index].inputNames = recipe.functionEntrypoints[index]
                    .inputNames.map { $0 == previousName ? name : $0 }
            }
        }
    }

    func addDynamicDimension() {
        guard let (input, axis) = nextAvailableDynamicDimension else {
            return
        }
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
        let nameIsUnique = recipe.stateBindings.count(where: {
            $0.name == state.name
        }) == 1
        recipe.stateBindings.removeAll { $0.id == id }
        if nameIsUnique {
            for index in recipe.functionEntrypoints.indices {
                recipe.functionEntrypoints[index].stateNames.removeAll { $0 == state.name }
            }
        }
    }

    func renameStateBinding(id: String, to name: String) {
        guard let index = recipe.stateBindings.firstIndex(where: { $0.id == id }) else {
            return
        }
        let previousName = recipe.stateBindings[index].name
        guard previousName != name else { return }
        let previousNameWasUnique = recipe.stateBindings.count(where: {
            $0.name == previousName
        }) == 1
        recipe.stateBindings[index].name = name
        if previousNameWasUnique {
            for index in recipe.functionEntrypoints.indices {
                recipe.functionEntrypoints[index].stateNames = recipe.functionEntrypoints[index]
                    .stateNames.map { $0 == previousName ? name : $0 }
            }
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

    func updatePipelineNodeKind(id: String, to kind: CoreAIPipelineNodeKind) {
        guard let index = recipe.pipeline.nodes.firstIndex(where: { $0.id == id }) else {
            return
        }
        recipe.pipeline.nodes[index].kind = kind
        recipe.pipeline.nodes[index].applyConfigurationDefaults()
        if kind == .state,
           recipe.pipeline.nodes[index].ownerNodeID?.isEmpty ?? true {
            recipe.pipeline.nodes[index].ownerNodeID = executableNodeIDs.first
        }
        pruneInvalidPipelineEdges()
    }

    func renamePipelinePort(
        nodeID: String,
        output: Bool,
        index: Int,
        to name: String
    ) {
        guard let nodeIndex = recipe.pipeline.nodes.firstIndex(where: { $0.id == nodeID }) else {
            return
        }
        let previousName: String
        let previousNameWasUnique: Bool
        if output {
            guard recipe.pipeline.nodes[nodeIndex].outputs.indices.contains(index) else { return }
            previousName = recipe.pipeline.nodes[nodeIndex].outputs[index].name
            previousNameWasUnique = recipe.pipeline.nodes[nodeIndex].outputs.count(where: {
                $0.name == previousName
            }) == 1
            recipe.pipeline.nodes[nodeIndex].outputs[index].name = name
        } else {
            guard recipe.pipeline.nodes[nodeIndex].inputs.indices.contains(index) else { return }
            previousName = recipe.pipeline.nodes[nodeIndex].inputs[index].name
            previousNameWasUnique = recipe.pipeline.nodes[nodeIndex].inputs.count(where: {
                $0.name == previousName
            }) == 1
            recipe.pipeline.nodes[nodeIndex].inputs[index].name = name
            if previousNameWasUnique,
               recipe.pipeline.nodes[nodeIndex].seedInputPort == previousName {
                recipe.pipeline.nodes[nodeIndex].seedInputPort = name
            }
            if previousNameWasUnique,
               recipe.pipeline.nodes[nodeIndex].stopConditionInputPort == previousName {
                recipe.pipeline.nodes[nodeIndex].stopConditionInputPort = name
            }
        }
        guard previousName != name else { return }
        if previousNameWasUnique {
            for edgeIndex in recipe.pipeline.edges.indices {
                if output,
                   recipe.pipeline.edges[edgeIndex].source.nodeID == nodeID,
                   recipe.pipeline.edges[edgeIndex].source.portName == previousName {
                    recipe.pipeline.edges[edgeIndex].source.portName = name
                }
                if !output,
                   recipe.pipeline.edges[edgeIndex].destination.nodeID == nodeID,
                   recipe.pipeline.edges[edgeIndex].destination.portName == previousName {
                    recipe.pipeline.edges[edgeIndex].destination.portName = name
                }
            }
            if output,
               selectedSourceEndpoint
                == CoreAIPipelineEndpoint(nodeID: nodeID, portName: previousName) {
                selectedSourceEndpoint = CoreAIPipelineEndpoint(nodeID: nodeID, portName: name)
            }
            if !output,
               selectedDestinationEndpoint
                == CoreAIPipelineEndpoint(nodeID: nodeID, portName: previousName) {
                selectedDestinationEndpoint = CoreAIPipelineEndpoint(nodeID: nodeID, portName: name)
            }
            deduplicatePipelineEdges()
        }
    }

    func removePipelinePort(nodeID: String, output: Bool, index: Int) {
        guard let nodeIndex = recipe.pipeline.nodes.firstIndex(where: { $0.id == nodeID }) else {
            return
        }
        let name: String
        if output {
            guard recipe.pipeline.nodes[nodeIndex].outputs.indices.contains(index) else { return }
            name = recipe.pipeline.nodes[nodeIndex].outputs[index].name
            let nameWasUnique = recipe.pipeline.nodes[nodeIndex].outputs.count(where: {
                $0.name == name
            }) == 1
            recipe.pipeline.nodes[nodeIndex].outputs.remove(at: index)
            if nameWasUnique {
                recipe.pipeline.edges.removeAll {
                    $0.source == CoreAIPipelineEndpoint(nodeID: nodeID, portName: name)
                }
                if selectedSourceEndpoint
                    == CoreAIPipelineEndpoint(nodeID: nodeID, portName: name) {
                    selectedSourceEndpoint = nil
                }
            }
        } else {
            guard recipe.pipeline.nodes[nodeIndex].inputs.indices.contains(index) else { return }
            let inputName = recipe.pipeline.nodes[nodeIndex].inputs[index].name
            let nameWasUnique = recipe.pipeline.nodes[nodeIndex].inputs.count(where: {
                $0.name == inputName
            }) == 1
            if nameWasUnique,
               inputName == recipe.pipeline.nodes[nodeIndex].seedInputPort
                || inputName == recipe.pipeline.nodes[nodeIndex].stopConditionInputPort {
                return
            }
            name = inputName
            recipe.pipeline.nodes[nodeIndex].inputs.remove(at: index)
            if nameWasUnique {
                recipe.pipeline.edges.removeAll {
                    $0.destination == CoreAIPipelineEndpoint(nodeID: nodeID, portName: name)
                }
                if selectedDestinationEndpoint
                    == CoreAIPipelineEndpoint(nodeID: nodeID, portName: name) {
                    selectedDestinationEndpoint = nil
                }
            }
        }
    }

    private var executableNodeIDs: [String] {
        recipe.pipeline.nodes.filter {
            [.assetFunction, .hostOperator, .boundedLoop].contains($0.kind)
        }.map(\.id)
    }

    private var nextAvailableDynamicDimension: (
        input: CoreAIRecipeExampleInput,
        axis: Int
    )? {
        for input in recipe.exampleInputs
        where input.kind == .tensor
            && recipe.exampleInputs.count(where: { $0.name == input.name }) == 1 {
            let usedAxes = Set(recipe.dynamicDimensions.lazy.filter {
                $0.inputName == input.name
            }.map(\.axis))
            if let axis = input.shape.indices.first(where: { !usedAxes.contains($0) }) {
                return (input, axis)
            }
        }
        return nil
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
        let ports = output ? node.outputs : node.inputs
        guard ports.count(where: { $0.name == endpoint.portName }) == 1 else {
            return nil
        }
        return ports.first {
            $0.name == endpoint.portName
        }
    }

    private func pruneInvalidPipelineEdges() {
        let outputEndpoints = Set(recipe.pipeline.nodes.flatMap { node in
            node.outputs.map {
                CoreAIPipelineEndpoint(nodeID: node.id, portName: $0.name)
            }
        })
        let inputEndpoints = Set(recipe.pipeline.nodes.flatMap { node in
            node.inputs.map {
                CoreAIPipelineEndpoint(nodeID: node.id, portName: $0.name)
            }
        })
        recipe.pipeline.edges.removeAll { edge in
            !outputEndpoints.contains(edge.source)
                || !inputEndpoints.contains(edge.destination)
        }
        if let selectedSourceEndpoint,
           !outputEndpoints.contains(selectedSourceEndpoint) {
            self.selectedSourceEndpoint = nil
        }
        if let selectedDestinationEndpoint,
           !inputEndpoints.contains(selectedDestinationEndpoint) {
            self.selectedDestinationEndpoint = nil
        }
        deduplicatePipelineEdges()
    }

    private func deduplicatePipelineEdges() {
        var seen = Set<CoreAIPipelineEdge.ID>()
        recipe.pipeline.edges.removeAll { !seen.insert($0.id).inserted }
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

    private func uniqueValues<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value>()
        return values.filter { seen.insert($0).inserted }
    }
}
