import SwiftUI

struct CoreAIPipelineNodeEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel
    @Binding var node: CoreAIPipelineNode
    @State private var inputPortIDs: [UUID]
    @State private var outputPortIDs: [UUID]

    init(
        workspace: CoreAIRecipeStudioWorkspaceModel,
        node: Binding<CoreAIPipelineNode>
    ) {
        self.workspace = workspace
        _node = node
        _inputPortIDs = State(initialValue: node.wrappedValue.inputs.map { _ in UUID() })
        _outputPortIDs = State(initialValue: node.wrappedValue.outputs.map { _ in UUID() })
    }

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("Node ID") {
                Text(node.id)
                    .monospaced()
                    .textSelection(.enabled)
            }
            TextField("Title", text: $node.title)
            Picker("Kind", selection: nodeKindBinding) {
                ForEach(CoreAIPipelineNodeKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            if let reference = Binding($node.reference) {
                TextField("Executable reference", text: reference)
                    .coreAIRecipeIdentifierInput()
            }
            if let stateKey = Binding($node.stateKey) {
                TextField("State key", text: stateKey)
                    .coreAIRecipeIdentifierInput()
            }
            if let ownerNodeID = Binding($node.ownerNodeID) {
                TextField("Owner node ID", text: ownerNodeID)
                    .coreAIRecipeIdentifierInput()
            }
            if let fixedSeed = Binding($node.fixedSeed) {
                TextField("Fixed seed", value: fixedSeed, format: .number)
                    .coreAIRecipeIntegerInput()
            }
            if let maximumIterations = Binding($node.maximumIterations) {
                TextField("Maximum iterations", value: maximumIterations, format: .number)
                    .coreAIRecipeIntegerInput()
            }

            GroupBox("Inputs") {
                VStack(alignment: .leading) {
                    ForEach(inputPortIDs, id: \.self) { portID in
                        if let port = inputPortBinding(for: portID) {
                            CoreAIPipelinePortEditorView(
                                port: port,
                                renamePort: { name in
                                    renameInputPort(id: portID, to: name)
                                }
                            )
                            Button(
                                "Remove Input Port",
                                systemImage: "minus.circle",
                                action: { removeInputPort(id: portID) }
                            )
                            .disabled(isProtectedInputPort(id: portID))
                        }
                    }
                    Button("Add Input Port", systemImage: "plus", action: addInputPort)
                        .disabled(node.kind == .input)
                }
            }

            GroupBox("Outputs") {
                VStack(alignment: .leading) {
                    ForEach(outputPortIDs, id: \.self) { portID in
                        if let port = outputPortBinding(for: portID) {
                            CoreAIPipelinePortEditorView(
                                port: port,
                                renamePort: { name in
                                    renameOutputPort(id: portID, to: name)
                                }
                            )
                            Button(
                                "Remove Output Port",
                                systemImage: "minus.circle",
                                action: { removeOutputPort(id: portID) }
                            )
                        }
                    }
                    Button("Add Output Port", systemImage: "plus", action: addOutputPort)
                        .disabled(node.kind == .output)
                }
            }
        }
    }

    private var nodeKindBinding: Binding<CoreAIPipelineNodeKind> {
        Binding(
            get: { node.kind },
            set: { updateNodeKind(to: $0) }
        )
    }

    private func addInputPort() {
        node.inputs.append(defaultPort(prefix: "input", existing: node.inputs))
        inputPortIDs.append(UUID())
    }

    private func addOutputPort() {
        node.outputs.append(defaultPort(prefix: "output", existing: node.outputs))
        outputPortIDs.append(UUID())
    }

    private func updateNodeKind(to kind: CoreAIPipelineNodeKind) {
        let previousInputs = node.inputs
        let previousOutputs = node.outputs
        let previousInputIDs = inputPortIDs
        let previousOutputIDs = outputPortIDs
        workspace.updatePipelineNodeKind(id: node.id, to: kind)
        inputPortIDs = reconciledPortIDs(
            previousPorts: previousInputs,
            previousIDs: previousInputIDs,
            currentPorts: node.inputs
        )
        outputPortIDs = reconciledPortIDs(
            previousPorts: previousOutputs,
            previousIDs: previousOutputIDs,
            currentPorts: node.outputs
        )
    }

    private func renameInputPort(id: UUID, to name: String) {
        guard let index = inputPortIDs.firstIndex(of: id),
              node.inputs.indices.contains(index) else {
            return
        }
        workspace.renamePipelinePort(
            nodeID: node.id,
            output: false,
            index: index,
            to: name
        )
    }

    private func renameOutputPort(id: UUID, to name: String) {
        guard let index = outputPortIDs.firstIndex(of: id),
              node.outputs.indices.contains(index) else {
            return
        }
        workspace.renamePipelinePort(
            nodeID: node.id,
            output: true,
            index: index,
            to: name
        )
    }

    private func removeInputPort(id: UUID) {
        guard let index = inputPortIDs.firstIndex(of: id),
              node.inputs.indices.contains(index) else {
            return
        }
        let previousCount = node.inputs.count
        workspace.removePipelinePort(nodeID: node.id, output: false, index: index)
        if node.inputs.count < previousCount {
            inputPortIDs.remove(at: index)
        }
    }

    private func removeOutputPort(id: UUID) {
        guard let index = outputPortIDs.firstIndex(of: id),
              node.outputs.indices.contains(index) else {
            return
        }
        workspace.removePipelinePort(nodeID: node.id, output: true, index: index)
        outputPortIDs.remove(at: index)
    }

    private func isProtectedInputPort(id: UUID) -> Bool {
        guard let index = inputPortIDs.firstIndex(of: id),
              node.inputs.indices.contains(index) else {
            return true
        }
        let name = node.inputs[index].name
        let nameIsUnique = node.inputs.count(where: { $0.name == name }) == 1
        return nameIsUnique
            && (name == node.seedInputPort || name == node.stopConditionInputPort)
    }

    private func inputPortBinding(for id: UUID) -> Binding<CoreAIPipelinePort>? {
        guard let index = inputPortIDs.firstIndex(of: id),
              node.inputs.indices.contains(index) else {
            return nil
        }
        return $node.inputs[index]
    }

    private func outputPortBinding(for id: UUID) -> Binding<CoreAIPipelinePort>? {
        guard let index = outputPortIDs.firstIndex(of: id),
              node.outputs.indices.contains(index) else {
            return nil
        }
        return $node.outputs[index]
    }

    private func reconciledPortIDs(
        previousPorts: [CoreAIPipelinePort],
        previousIDs: [UUID],
        currentPorts: [CoreAIPipelinePort]
    ) -> [UUID] {
        var previous = Array(zip(previousPorts, previousIDs))
        return currentPorts.map { port in
            guard let index = previous.firstIndex(where: { $0.0.name == port.name }) else {
                return UUID()
            }
            return previous.remove(at: index).1
        }
    }

    private func defaultPort(
        prefix: String,
        existing: [CoreAIPipelinePort]
    ) -> CoreAIPipelinePort {
        let names = Set(existing.map(\.name))
        var index = existing.count + 1
        while names.contains("\(prefix)_\(index)") {
            index += 1
        }
        return CoreAIPipelinePort(
            name: "\(prefix)_\(index)",
            value: CoreAIPipelineValueContract(
                kind: .tensor,
                scalarType: "float32",
                shape: [.fixed(1)]
            )
        )
    }
}
