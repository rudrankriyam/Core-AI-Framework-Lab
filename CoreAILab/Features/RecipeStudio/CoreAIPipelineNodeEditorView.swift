import SwiftUI

struct CoreAIPipelineNodeEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel
    @Binding var node: CoreAIPipelineNode

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
                    ForEach(node.inputs.indices, id: \.self) { index in
                        CoreAIPipelinePortEditorView(
                            port: $node.inputs[index],
                            renamePort: { name in
                                workspace.renamePipelinePort(
                                    nodeID: node.id,
                                    output: false,
                                    index: index,
                                    to: name
                                )
                            }
                        )
                        Button(
                            "Remove Input Port",
                            systemImage: "minus.circle",
                            action: { removeInputPort(at: index) }
                        )
                    }
                    Button("Add Input Port", systemImage: "plus", action: addInputPort)
                        .disabled(node.kind == .input)
                }
            }

            GroupBox("Outputs") {
                VStack(alignment: .leading) {
                    ForEach(node.outputs.indices, id: \.self) { index in
                        CoreAIPipelinePortEditorView(
                            port: $node.outputs[index],
                            renamePort: { name in
                                workspace.renamePipelinePort(
                                    nodeID: node.id,
                                    output: true,
                                    index: index,
                                    to: name
                                )
                            }
                        )
                        Button(
                            "Remove Output Port",
                            systemImage: "minus.circle",
                            action: { removeOutputPort(at: index) }
                        )
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
            set: { workspace.updatePipelineNodeKind(id: node.id, to: $0) }
        )
    }

    private func addInputPort() {
        node.inputs.append(defaultPort(prefix: "input", existing: node.inputs))
    }

    private func addOutputPort() {
        node.outputs.append(defaultPort(prefix: "output", existing: node.outputs))
    }

    private func removeInputPort(at index: Int) {
        workspace.removePipelinePort(nodeID: node.id, output: false, index: index)
    }

    private func removeOutputPort(at index: Int) {
        workspace.removePipelinePort(nodeID: node.id, output: true, index: index)
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
